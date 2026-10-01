import Foundation

/// A capture taken before the panel takes focus: model-visible text plus
/// private target evidence and an opaque platform handle for replacement.
public struct CaptureSnapshot {
    public let captured: CapturedText
    public let target: TargetEvidence
    /// Selection bounds in global Cocoa coordinates (bottom-left origin), if exposed.
    public let selectionBounds: PanelRect?
    /// Platform element reference (e.g. an AXUIElement). Never serialized.
    public let handle: AnyObject?
    public let capturedAt: Date

    public init(captured: CapturedText, target: TargetEvidence, selectionBounds: PanelRect?, handle: AnyObject?, capturedAt: Date = Date()) {
        self.captured = captured
        self.target = target
        self.selectionBounds = selectionBounds
        self.handle = handle
        self.capturedAt = capturedAt
    }
}

public protocol SelectionCapturing: AnyObject {
    func captureFocusedSelection() -> Result<CaptureSnapshot, CaptureRefusal>
}

public protocol TextReplacing: AnyObject {
    /// Revalidate the original target and replace exactly its selection, once.
    func replace(_ snapshot: CaptureSnapshot, with text: String) async -> ApplyOutcome
}

public enum TriggerResult: Equatable {
    case started
    /// A session is already active; the UI should focus it instead of starting another.
    case focusExisting
    case refused(CaptureRefusal)
}

/// Owns the single active rewrite. All mutation of UI-visible state happens on
/// the main actor; provider work runs in a cancellable task whose completion is
/// accepted only if session identity and generation still match.
@MainActor
public final class SessionCoordinator {
    public private(set) var session: RewriteSession?
    public private(set) var snapshot: CaptureSnapshot?
    public var onChange: (() -> Void)?
    /// Sanitized diagnostics sink (operation, duration, outcome class only).
    public var diagnostics: ((String) -> Void)?
    /// Developer inspector (`--debug-prompts`): when set, every provider request
    /// carries a `RequestTrace`, handed here before the request starts.
    public var onTrace: ((RequestTrace) -> Void)?

    let capturer: SelectionCapturing
    let replacer: TextReplacing
    let settings: () -> AppSettings
    let provider: (ProviderID) -> RewriteProvider
    let timeout: TimeInterval
    private var work: Task<Void, Never>?

    public init(
        capturer: SelectionCapturing,
        replacer: TextReplacing,
        settings: @escaping () -> AppSettings,
        provider: @escaping (ProviderID) -> RewriteProvider,
        timeout: TimeInterval = Limits.rewriteTimeout
    ) {
        self.capturer = capturer
        self.replacer = replacer
        self.settings = settings
        self.provider = provider
        self.timeout = timeout
    }

    public var isActive: Bool {
        guard let s = session else { return false }
        return !s.phase.isTerminal
    }

    /// Assigned key pressed (or menu "Rewrite Selection" / "Check for Slop").
    public func trigger(mode: SessionMode = .rewrite) -> TriggerResult {
        if isActive { return .focusExisting }
        switch capturer.captureFocusedSelection() {
        case .failure(let refusal):
            diagnostics?("capture refused: \(refusal)")
            return .refused(refusal)
        case .success(let snap):
            let s = RewriteSession(capture: snap.captured, mode: mode)
            session = s
            snapshot = snap
            startGeneration(s)
            return .started
        }
    }

    /// From a detection session, rewrite the same captured selection. The original
    /// capture and target evidence are kept, so apply still revalidates that exact
    /// selection. Returns false when there is no detection session to convert.
    @discardableResult
    public func switchToRewrite() -> Bool {
        guard let current = session, current.mode == .detect, snapshot != nil else { return false }
        work?.cancel()
        work = nil
        current.cancel()
        let s = RewriteSession(capture: current.capture, mode: .rewrite)
        session = s
        startGeneration(s)
        return true
    }

    /// Explicit retry after a provider failure, before any user edit.
    public func retry() {
        guard let s = session else { return }
        startGeneration(s)
    }

    private func startGeneration(_ s: RewriteSession) {
        guard let g = s.beginGeneration() else { return }
        // Settings are snapshotted per request; later changes affect the next rewrite.
        let current = settings()
        var composed: ComposedRequest
        do {
            composed = try PromptComposer.compose(capture: s.capture, settings: current, mode: s.mode)
        } catch let e as CompositionError {
            s.compositionFailed(e)
            onChange?()
            return
        } catch {
            s.compositionFailed(.invalidContext)
            onChange?()
            return
        }
        let p = provider(current.providerID)
        if let onTrace {
            let trace = RequestTrace(mode: s.mode, provider: p.isFixture ? "fixture" : p.id.displayName,
                                     instructions: composed.instructions, dataMessage: composed.dataMessage,
                                     model: composed.model, reasoning: composed.reasoning)
            composed.trace = trace
            onTrace(trace)
        }
        let trace = composed.trace
        let sessionID = s.id
        let timeout = self.timeout
        onChange?()
        let started = Date()
        let mode = s.mode
        work = Task { [weak self] in
            let outcome: Result<ProviderResult, ProviderFailure>
            do {
                switch mode {
                case .rewrite: outcome = .success(.rewrite(try await p.rewrite(composed, timeout: timeout)))
                case .detect: outcome = .success(.detection(try await p.detect(composed, timeout: timeout)))
                }
            } catch let f as ProviderFailure {
                outcome = .failure(f)
            } catch is CancellationError {
                outcome = .failure(.cancelled)
            } catch {
                outcome = .failure(.runtimeError(p.id, "unexpected error"))
            }
            switch outcome {
            case .success: trace?.finish(outcome: "Accepted")
            case .failure(let f): trace?.finish(outcome: "Failed: \(f.diagnosticClass)")
            }
            await MainActor.run {
                guard let self, let live = self.session, live.id == sessionID else { return }
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                switch outcome {
                case .success(.rewrite(let r)):
                    let accepted = live.receive(r, generation: g, fixture: p.isFixture)
                    self.diagnostics?("rewrite \(p.id.rawValue) ok \(ms)ms accepted=\(accepted)")
                case .success(.detection(let d)):
                    let accepted = live.receive(d, generation: g, fixture: p.isFixture)
                    self.diagnostics?("detect \(p.id.rawValue) ok \(ms)ms findings=\(d.response.findings.count) dropped=\(d.response.droppedFindings) accepted=\(accepted)")
                case .failure(let f):
                    live.receive(failure: f, generation: g)
                    self.diagnostics?("\(mode.rawValue) \(p.id.rawValue) failed \(f.diagnosticClass) \(ms)ms")
                }
                self.onChange?()
            }
        }
    }

    public func edit(_ text: String) {
        session?.edit(text)
        onChange?()
    }

    /// Explicit Anti-slop / Command-Return.
    public func apply() async {
        guard let s = session, let snap = snapshot, let final = s.beginApply() else { return }
        onChange?()
        let outcome = await replacer.replace(snap, with: final)
        guard session === s else { return }
        s.finishApply(outcome)
        diagnostics?("apply \(outcomeClass(outcome))")
        onChange?()
    }

    /// After the original selection changed, explicitly adopt the user's current
    /// selection as the target for the existing draft ("Use current selection").
    /// Never regenerates and never applies; the user still presses Anti-slop.
    @discardableResult
    public func retarget() -> CaptureRefusal? {
        guard let s = session, case .targetChanged = s.phase else { return nil }
        switch capturer.captureFocusedSelection() {
        case .failure(let r):
            return r
        case .success(let snap):
            snapshot = snap
            s.returnToReadyAfterTargetChange()
            onChange?()
            return nil
        }
    }

    /// Close/Escape: cancel pending work, never mutate the source.
    public func cancel() {
        work?.cancel()
        work = nil
        let before = session?.phase
        session?.cancel()
        // Notify only on a real change. Cancelling a finished session is a no-op, and a
        // listener that cancels from inside onChange (the app closing its panel after a
        // confirmed apply) must not re-notify itself without end.
        if session?.phase != before { onChange?() }
    }

    /// Forget a finished session (after the panel closes).
    public func clear() {
        if isActive { cancel() }
        session = nil
        snapshot = nil
    }

    private func outcomeClass(_ o: ApplyOutcome) -> String {
        switch o {
        case .confirmed(let m): return "confirmed \(m.rawValue)"
        case .blocked(let r): return "blocked \(r)"
        case .failed: return "failed"
        case .uncertain: return "uncertain"
        }
    }
}

private enum ProviderResult {
    case rewrite(ProviderRewrite)
    case detection(ProviderDetection)
}
