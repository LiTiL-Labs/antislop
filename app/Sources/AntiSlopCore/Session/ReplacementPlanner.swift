import Foundation

/// Native-independent evidence about the source control. The platform layer
/// fills it from accessibility attributes; it is never sent to a model.
public struct TargetEvidence: Equatable, Sendable {
    public var processID: Int32
    public var bundleID: String?
    public var role: String?
    public var isSecure: Bool
    /// nil when the platform cannot tell.
    public var isEditable: Bool?
    public var selectedText: String?
    public var selectedRange: TextRange?
    /// Full control value, held in memory only for drift checks and verification.
    public var fullText: String?

    public init(processID: Int32, bundleID: String? = nil, role: String? = nil, isSecure: Bool = false,
                isEditable: Bool? = nil, selectedText: String? = nil, selectedRange: TextRange? = nil,
                fullText: String? = nil) {
        self.processID = processID
        self.bundleID = bundleID
        self.role = role
        self.isSecure = isSecure
        self.isEditable = isEditable
        self.selectedText = selectedText
        self.selectedRange = selectedRange
        self.fullText = fullText
    }
}

/// What the platform observes when apply is requested.
public struct TargetObservation: Equatable, Sendable {
    public var appIsRunning: Bool
    /// Same accessibility element as captured (platform identity comparison).
    public var isSameElement: Bool
    /// That element is still its application's focused element.
    public var isFocusedInApp: Bool
    public var evidence: TargetEvidence?

    public init(appIsRunning: Bool, isSameElement: Bool, isFocusedInApp: Bool, evidence: TargetEvidence?) {
        self.appIsRunning = appIsRunning
        self.isSameElement = isSameElement
        self.isFocusedInApp = isFocusedInApp
        self.evidence = evidence
    }
}

public enum TargetChangeReason: Equatable, Sendable {
    case appClosed
    case elementGone
    case focusMoved
    case selectionChanged
    case textChanged
    case notEditable
    case evidenceUnavailable(String)

    public var message: String {
        switch self {
        case .appClosed: return "The original app closed. Your draft is safe."
        case .elementGone, .focusMoved, .selectionChanged, .textChanged:
            return "The original selection changed. Your draft is safe."
        case .notEditable: return "The original text can't be edited now. Your draft is safe."
        case .evidenceUnavailable: return "Couldn't confirm the original selection. Your draft is safe."
        }
    }
}

public enum VerificationResult: Equatable, Sendable {
    case confirmed
    /// The source still holds the original text: the write did not happen.
    case unchanged
    /// The source changed, but not to the expected text.
    case unexpected
    case unverifiable
}

/// Pure decision logic for the replacement transaction (ARCHITECTURE.md steps 5–7).
public enum ReplacementPlanner {
    /// Block unless every available piece of identity evidence still matches.
    /// Missing evidence that was present at capture blocks the write.
    public static func check(original: TargetEvidence, now obs: TargetObservation) -> TargetChangeReason? {
        guard obs.appIsRunning else { return .appClosed }
        guard obs.isSameElement else { return .elementGone }
        guard obs.isFocusedInApp else { return .focusMoved }
        guard let now = obs.evidence else { return .evidenceUnavailable("attributes") }
        guard now.processID == original.processID else { return .elementGone }
        if now.isSecure { return .notEditable }
        if now.isEditable == false { return .notEditable }

        if let r0 = original.selectedRange {
            guard let r1 = now.selectedRange else { return .evidenceUnavailable("range") }
            guard r0 == r1 else { return .selectionChanged }
        }
        guard let t0 = original.selectedText else { return .evidenceUnavailable("selection") }
        let t1 = now.selectedText ?? derivedSelection(now)
        guard let t1 else { return .evidenceUnavailable("selection") }
        guard t0 == t1 else { return .selectionChanged }

        if let f0 = original.fullText {
            guard let f1 = now.fullText else { return .evidenceUnavailable("text") }
            guard f0 == f1 else { return .textChanged }
        }
        return nil
    }

    static func derivedSelection(_ e: TargetEvidence) -> String? {
        guard let f = e.fullText, let r = e.selectedRange else { return nil }
        return ContextBuilder.split(f, at: r)?.selection
    }

    /// Full control value expected after replacing exactly the original range.
    public static func expectedFullText(original: TargetEvidence, replacement: String) -> String? {
        guard let f = original.fullText, let r = original.selectedRange,
              let parts = ContextBuilder.split(f, at: r) else { return nil }
        return parts.before + replacement + parts.after
    }

    /// Compare what the source now holds with the expected result.
    /// `observedRangeText` is the text at [location, location + replacement UTF-16 length),
    /// used when the full value is not exposed.
    public static func verify(original: TargetEvidence, replacement: String,
                              observedFullText: String?, observedRangeText: String?) -> VerificationResult {
        if let expected = expectedFullText(original: original, replacement: replacement), let observed = observedFullText {
            if observed == expected { return .confirmed }
            if observed == original.fullText { return .unchanged }
            // Some controls normalize line endings; accept only that exact difference.
            if normalizeNewlines(observed) == normalizeNewlines(expected) { return .confirmed }
            return .unexpected
        }
        if let rangeText = observedRangeText {
            return rangeText == replacement ? .confirmed : .unexpected
        }
        return .unverifiable
    }

    static func normalizeNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

// MARK: - Clipboard fallback ownership

public struct PasteboardItemSnapshot: Equatable, Sendable {
    public var dataByType: [String: Data]
    public init(dataByType: [String: Data]) { self.dataByType = dataByType }
}

public protocol PasteboardAccess: AnyObject {
    var changeCount: Int { get }
    func snapshotItems() -> [PasteboardItemSnapshot]
    /// Replace contents with plain text; returns the new change count.
    func writePlainText(_ text: String) -> Int
    /// Replace contents with saved items; returns the new change count.
    func restore(_ items: [PasteboardItemSnapshot]) -> Int
}

public enum ClipboardRestoreOutcome: Equatable, Sendable {
    case restored
    /// Someone else wrote to the clipboard during the transaction; their content wins.
    case skippedNewerContent
}

/// Clipboard fallback bookkeeping: snapshot preservable items, write plain
/// text, and restore only if Anti-slop still owns the latest change.
public final class ClipboardTransaction {
    let pasteboard: PasteboardAccess
    private let saved: [PasteboardItemSnapshot]
    public private(set) var ownedChangeCount: Int?

    public init(pasteboard: PasteboardAccess) {
        self.pasteboard = pasteboard
        self.saved = pasteboard.snapshotItems()
    }

    public func writeReplacement(_ text: String) {
        ownedChangeCount = pasteboard.writePlainText(text)
    }

    public func finish() -> ClipboardRestoreOutcome {
        guard let owned = ownedChangeCount, pasteboard.changeCount == owned else { return .skippedNewerContent }
        _ = pasteboard.restore(saved)
        return .restored
    }
}
