import Foundation

/// Developer-only record of one provider request, for the debug inspector
/// (`--debug-prompts`). It holds the full instructions, request data and raw
/// runtime output in memory for display only: it is never logged, written to
/// disk or sent anywhere, and it does nothing unless a caller attaches it.
public final class RequestTrace: @unchecked Sendable {
    public struct Snapshot: Sendable {
        public let mode: SessionMode
        public let provider: String
        public let startedAt: Date
        public let instructions: String
        public let dataMessage: String
        /// The writer's choice as sent (nil = runtime default).
        public var requestedModel: String?
        public var requestedReasoning: String?
        /// The model the runtime reported actually serving the request.
        public var reportedModel: String?
        public var schema: String?
        /// Runtime executable and arguments, with the instructions elided.
        public var command: [String] = []
        /// The model's final answer as the runtime returned it, before validation.
        public var rawResponse: String?
        /// Every stdout line from the runtime (stream-json / JSONL events).
        public var transcript: String?
        public var stderr: String?
        /// "Accepted", or the failure class, filled in when the request ends.
        public var outcome: String?
        public var durationMs: Int?
    }

    private let lock = NSLock()
    private var _snapshot: Snapshot
    /// Called on an arbitrary thread after every change.
    public var onUpdate: (@Sendable (Snapshot) -> Void)?

    public init(mode: SessionMode, provider: String, instructions: String, dataMessage: String,
                model: String? = nil, reasoning: String? = nil) {
        _snapshot = Snapshot(mode: mode, provider: provider, startedAt: Date(),
                             instructions: instructions, dataMessage: dataMessage,
                             requestedModel: model, requestedReasoning: reasoning)
    }

    public var snapshot: Snapshot { lock.lock(); defer { lock.unlock() }; return _snapshot }

    func update(_ change: (inout Snapshot) -> Void) {
        lock.lock()
        change(&_snapshot)
        let s = _snapshot
        let callback = onUpdate
        lock.unlock()
        callback?(s)
    }

    /// Record a runtime invocation. The (long) instructions argument is replaced
    /// by a marker because it is shown in full in its own section.
    func recordInvocation(executable: String, arguments: [String], schema: String) {
        let instructions = snapshot.instructions
        let args = arguments.map { arg -> String in
            if arg == instructions { return "<instructions>" }
            if arg.hasSuffix(instructions), let eq = arg.firstIndex(of: "=") { return String(arg[...eq]) + "<instructions>" }
            return arg
        }
        update {
            $0.command = [executable] + args
            $0.schema = schema
        }
    }

    func recordOutput(_ out: ProcessOutput, rawResponse: String?, reportedModel: String? = nil) {
        update {
            if let reportedModel { $0.reportedModel = reportedModel }
            $0.transcript = out.stdoutText
            $0.stderr = out.stderrText.isEmpty ? nil : out.stderrText
            $0.rawResponse = rawResponse
        }
    }

    func finish(outcome: String) {
        update {
            $0.outcome = outcome
            $0.durationMs = Int(Date().timeIntervalSince($0.startedAt) * 1000)
        }
    }

    static func prettyJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return String(describing: object) }
        return String(decoding: data, as: UTF8.self)
    }
}
