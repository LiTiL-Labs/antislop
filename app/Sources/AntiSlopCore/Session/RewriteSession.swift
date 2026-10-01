import Foundation

public enum ApplyOutcome: Equatable, Sendable {
    /// Replacement written and the observed result matched the expected text.
    case confirmed(ReplacementMethod)
    /// Pre-write validation failed; nothing was written.
    case blocked(TargetChangeReason)
    /// The write did not happen (verified: source unchanged).
    case failed(String)
    /// A write was attempted and its result could not be confirmed.
    case uncertain(String)
}

public enum ReplacementMethod: String, Equatable, Sendable {
    case accessibilitySelectedText = "accessibility"
    case pasteboard = "paste"
}

public enum SessionPhase: Equatable, Sendable {
    case generating
    case ready
    case applying
    case targetChanged(TargetChangeReason)
    case failed(SessionFailure)
    case succeeded
    case cancelled

    public var isTerminal: Bool { self == .succeeded || self == .cancelled }
}

public enum SessionFailure: Equatable, Sendable {
    case provider(ProviderFailure)
    case applyFailed(String)
    case applyUncertain(String)
    case composition(CompositionError)
}

public enum ApplyAvailability: Equatable, Sendable {
    case enabled
    case disabled(reason: String?)
}

/// One selection, one proposal, one apply. A detection-mode session is the same
/// lifecycle with findings instead of a proposal, and it can never apply. Owns identity, generation and edit
/// revisions so a late provider result can never overwrite the user's edits and
/// nothing mutates the source except an explicit apply.
public final class RewriteSession {
    public let id = UUID()
    public let capture: CapturedText
    public let mode: SessionMode
    public private(set) var phase: SessionPhase
    public private(set) var generation = 0
    public private(set) var proposal: RewriteResponse?
    public private(set) var detection: DetectionResponse?
    public private(set) var draft = ""
    public private(set) var draftRevision = 0
    public private(set) var userHasEdited = false
    /// The receipt of the accepted proposal (sanitized; no content).
    public private(set) var receipt: ProviderReceipt?
    public private(set) var usedFixture = false
    private var applyAttempted = false

    public init(capture: CapturedText, mode: SessionMode = .rewrite) {
        self.capture = capture
        self.mode = mode
        self.phase = .generating
    }

    public var hasDraft: Bool { proposal != nil }
    public var intentLine: String? { proposal.map { Self.singleLine($0.intent, limit: Limits.intent) } }
    /// Display note. Placeholder strings some models emit instead of null
    /// (observed live: "None") are not shown.
    public var note: String? {
        guard let raw = proposal?.note else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["none", "null", "n/a", "nil", ""].contains(t.lowercased()) { return nil }
        return Self.singleLine(t, limit: Limits.note)
    }
    public var isUnchangedProposal: Bool { proposal?.rewrittenText == capture.selectedText }

    /// Start (or explicitly retry) generation. Allowed only before any user edit.
    @discardableResult
    public func beginGeneration() -> Int? {
        switch phase {
        case .generating where generation == 0, .failed(.provider), .failed(.composition):
            guard !userHasEdited else { return nil }
            generation += 1
            phase = .generating
            return generation
        default:
            return nil
        }
    }

    /// Accept a provider result only if it belongs to the current generation of
    /// a live session and the user has not taken ownership of the draft.
    @discardableResult
    public func receive(_ result: ProviderRewrite, generation g: Int, fixture: Bool = false) -> Bool {
        guard mode == .rewrite, g == generation, phase == .generating, !userHasEdited else { return false }
        proposal = result.response
        receipt = result.receipt
        usedFixture = fixture
        draft = result.response.rewrittenText
        draftRevision += 1
        phase = .ready
        return true
    }

    /// Accept detection findings for the current generation of a live detection session.
    @discardableResult
    public func receive(_ result: ProviderDetection, generation g: Int, fixture: Bool = false) -> Bool {
        guard mode == .detect, g == generation, phase == .generating else { return false }
        detection = result.response
        receipt = result.receipt
        usedFixture = fixture
        phase = .ready
        return true
    }

    @discardableResult
    public func receive(failure: ProviderFailure, generation g: Int) -> Bool {
        guard g == generation, phase == .generating else { return false }
        phase = failure == .cancelled ? .cancelled : .failed(.provider(failure))
        return true
    }

    public func compositionFailed(_ e: CompositionError) {
        guard phase == .generating else { return }
        phase = .failed(.composition(e))
    }

    /// The editor changed. Edit ownership begins at the first real change.
    public func edit(_ text: String) {
        guard hasDraft, !phase.isTerminal, phase != .applying else { return }
        guard text != draft else { return }
        draft = text
        draftRevision += 1
        userHasEdited = true
    }

    public var applyAvailability: ApplyAvailability {
        if mode == .detect { return .disabled(reason: nil) }
        guard phase == .ready else {
            switch phase {
            case .generating: return .disabled(reason: nil)
            case .applying: return .disabled(reason: nil)
            default: return .disabled(reason: nil)
            }
        }
        if draftIsBlankForSubstantiveSource { return .disabled(reason: "Enter replacement text to apply.") }
        return .enabled
    }

    var draftIsBlankForSubstantiveSource: Bool { draft.isBlank && !capture.selectedText.isBlank }

    /// Freeze the final draft for a single replacement transaction. The blank
    /// guard is rechecked here, immediately before any source mutation.
    public func beginApply() -> String? {
        guard applyAvailability == .enabled, !applyAttempted else { return nil }
        applyAttempted = true
        phase = .applying
        return draft
    }

    public func finishApply(_ outcome: ApplyOutcome) {
        guard phase == .applying else { return }
        switch outcome {
        case .confirmed:
            phase = .succeeded
        case .blocked(let reason):
            // Nothing was written, so a later explicit apply is still a single write.
            applyAttempted = false
            phase = .targetChanged(reason)
        case .failed(let why):
            phase = .failed(.applyFailed(why))
        case .uncertain(let why):
            phase = .failed(.applyUncertain(why))
        }
    }

    /// Recheck the target after it changed (the user restored the selection).
    public func returnToReadyAfterTargetChange() {
        if case .targetChanged = phase { phase = .ready }
    }

    public func cancel() {
        guard !phase.isTerminal, phase != .applying else { return }
        generation += 1 // invalidates any in-flight completion
        phase = .cancelled
    }

    public static func singleLine(_ s: String, limit: Int) -> String {
        let one = s.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return one.isEmpty ? "Context unclear" : one.prefixCodePoints(limit)
    }
}
