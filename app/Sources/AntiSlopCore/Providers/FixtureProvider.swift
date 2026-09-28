import Foundation

/// Deterministic development provider. It is never a real connection: its
/// readiness is `.fixtureOnly`, the panel labels its output "Fixture preview —
/// not live AI", and it is only reachable through an explicit developer switch
/// (`--fixture-provider` / `ANTISLOP_FIXTURE_PROVIDER=1`) or tests.
public final class FixtureProvider: RewriteProvider, @unchecked Sendable {
    public enum Behavior: Sendable {
        /// Strip a few stock lead-ins; otherwise return the selection unchanged.
        case lightEdit
        case fixed(intent: String, text: String, note: String?)
        case rawJSON(String)
        case fail(ProviderFailure)
        case hang
    }

    public let id: ProviderID
    public let isFixture = true
    private let lock = NSLock()
    private var _behavior: Behavior
    private let delay: TimeInterval
    private var _requests: [ComposedRequest] = []

    public init(id: ProviderID = .claudeCode, behavior: Behavior = .lightEdit, delay: TimeInterval = 0.6) {
        self.id = id
        self._behavior = behavior
        self.delay = delay
    }

    public var behavior: Behavior {
        get { lock.lock(); defer { lock.unlock() }; return _behavior }
        set { lock.lock(); _behavior = newValue; lock.unlock() }
    }

    /// Requests received, for composition assertions in tests.
    public var requests: [ComposedRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    private func record(_ composed: ComposedRequest) -> Behavior {
        lock.lock()
        defer { lock.unlock() }
        _requests.append(composed)
        return _behavior
    }

    public func checkReadiness() async -> ReadinessState { .fixtureOnly }
    public func signInCommand() async -> SignInCommand? { nil }

    public func rewrite(_ composed: ComposedRequest, timeout: TimeInterval) async throws -> ProviderRewrite {
        let behavior = record(composed)
        let started = Date()
        if case .hang = behavior {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw ProviderFailure.timedOut(id)
        }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        if Task.isCancelled { throw ProviderFailure.cancelled }
        let original = composed.request.selectedText
        let json: String
        switch behavior {
        case .lightEdit:
            json = try Self.json(intent: Self.intent(for: composed.request), text: Self.lightEdit(original),
                                 note: "Fixture preview — not live AI.")
        case .fixed(let intent, let text, let note):
            json = try Self.json(intent: intent, text: text, note: note)
        case .rawJSON(let raw):
            json = raw
        case .fail(let f):
            throw f
        case .hang:
            throw ProviderFailure.timedOut(id)
        }
        switch ResponseValidator.validate(jsonText: json, originalSelection: original) {
        case .failure(let e): throw ProviderFailure.malformedResponse(id, e)
        case .success(let r):
            let receipt = ProviderReceipt(provider: "fixture", runtimeVersion: "fixture", model: nil,
                                          durationMs: Int(Date().timeIntervalSince(started) * 1000),
                                          profile: composed.profile.rawValue, outcome: "fixture")
            return ProviderRewrite(response: r, receipt: receipt)
        }
    }

    static func json(intent: String, text: String, note: String?) throws -> String {
        var obj: [String: Any] = ["intent": intent, "rewritten_text": text]
        obj["note"] = note ?? NSNull()
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func intent(for r: RewriteRequest) -> String {
        if let hint = r.sourceHint.contentTypeHint, !hint.isEmpty { return "Fixture: looks like \(hint)" }
        return "Fixture: context unclear"
    }

    static func lightEdit(_ s: String) -> String {
        let leadIns = ["It is worth noting that ", "It is important to note that ", "We are excited to announce that "]
        let leading = String(s.prefix { $0 == " " || $0 == "\n" || $0 == "\t" })
        var body = String(s.dropFirst(leading.count))
        for lead in leadIns where body.hasPrefix(lead) {
            body = String(body.dropFirst(lead.count))
            if let first = body.first { body = first.uppercased() + body.dropFirst() }
        }
        return leading + body
    }
}
