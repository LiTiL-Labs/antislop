import Foundation

/// Truthful connection state for the settings readiness row (UX.md).
/// Runtime presence alone is `installed`, never `ready`.
public enum ReadinessState: Equatable, Sendable {
    case unavailable(String)
    case installed(version: String)
    case checking
    case signInNeeded(String)
    case ready(ReadyDetails)
    /// Usable runtime whose configuration Anti-slop will not use silently
    /// (API-key billing, incompatible version, cloud provider switch).
    case constrained(String)
    case accountLimit(String)
    case offline(String)
    case error(String)
    /// Development-only deterministic provider. Never a real connection.
    case fixtureOnly

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case .unavailable: return "Not installed"
        case .installed: return "Installed"
        case .checking: return "Checking…"
        case .signInNeeded: return "Sign-in needed"
        case .ready: return "Ready"
        case .constrained: return "Needs attention"
        case .accountLimit: return "Account limit"
        case .offline: return "Offline"
        case .error: return "Error"
        case .fixtureOnly: return "Fixture only (not live)"
        }
    }

    public var detail: String? {
        switch self {
        case .unavailable(let s), .signInNeeded(let s), .constrained(let s), .accountLimit(let s),
             .offline(let s), .error(let s):
            return s
        case .installed(let v): return "Version \(v). Run a check to confirm your sign-in."
        case .ready(let d): return d.summary
        case .checking: return nil
        case .fixtureOnly: return "Development fixture responses; no AI connection is used."
        }
    }
}

public struct ReadyDetails: Equatable, Sendable {
    public let runtimeVersion: String
    public let model: String?
    public let account: String
    public let checkedAt: Date

    public var summary: String {
        var parts = ["\(account)", "runtime \(runtimeVersion)"]
        if let model { parts.append("model \(model)") }
        return parts.joined(separator: " · ")
    }
}

/// Official provider-owned sign-in, launched visibly for the user. Anti-slop
/// never sees a password or token.
public struct SignInCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let explanation: String
}

/// Why a rewrite did not produce a proposal. Each case maps to a concise,
/// recoverable UI message; none triggers a provider switch.
public enum ProviderFailure: Error, Equatable, Sendable {
    case notInstalled(ProviderID)
    case incompatibleRuntime(ProviderID, String)
    case signInNeeded(ProviderID)
    case apiBillingBlocked(ProviderID, String)
    case accountLimit(ProviderID)
    case modelUnavailable(ProviderID)
    case offline(ProviderID)
    case timedOut(ProviderID)
    case cancelled
    case toolUseBlocked(ProviderID, String)
    case malformedResponse(ProviderID, ResponseValidationError)
    case runtimeError(ProviderID, String)

    public var userMessage: String {
        switch self {
        case .notInstalled(let p): return "\(p.displayName) isn't installed. Open settings to set it up."
        case .incompatibleRuntime(let p, _): return "This version of \(p.displayName) isn't supported. Update it and check again."
        case .signInNeeded(let p): return "Finish signing in to \(p.displayName)."
        case .apiBillingBlocked(let p, _):
            return "\(p.displayName) is set up for API-key billing. Sign in with your \(p.accountLabel) instead."
        case .accountLimit(let p): return "Your \(p.displayName) account has reached a usage limit. Try again later."
        case .modelUnavailable(let p): return "\(p.displayName)'s model isn't available on this account."
        case .offline(let p): return "Couldn't reach \(p.displayName). Check your connection and try again."
        case .timedOut(let p): return "\(p.displayName) took too long. Try again or select less text."
        case .cancelled: return "Cancelled."
        case .toolUseBlocked(let p, _): return "\(p.displayName) tried to use a tool, so Anti-slop stopped the request."
        case .malformedResponse(let p, _): return "\(p.displayName) returned an unusable response. Try again."
        case .runtimeError(let p, _): return "\(p.displayName) couldn't complete the rewrite. Try again."
        }
    }

    /// Sanitized class for diagnostics; never includes document or response text.
    public var diagnosticClass: String {
        switch self {
        case .notInstalled: return "not_installed"
        case .incompatibleRuntime(_, let d): return "incompatible_runtime: \(d)"
        case .signInNeeded: return "sign_in_needed"
        case .apiBillingBlocked(_, let d): return "api_billing_blocked: \(d)"
        case .accountLimit: return "account_limit"
        case .modelUnavailable: return "model_unavailable"
        case .offline: return "offline"
        case .timedOut: return "timed_out"
        case .cancelled: return "cancelled"
        case .toolUseBlocked(_, let d): return "tool_use_blocked: \(d)"
        case .malformedResponse(_, let e): return "malformed_response: \(e.diagnostic)"
        case .runtimeError(_, let d): return "runtime_error: \(d)"
        }
    }

    public var suggestsSettings: Bool {
        switch self {
        case .notInstalled, .incompatibleRuntime, .signInNeeded, .apiBillingBlocked, .modelUnavailable: return true
        default: return false
        }
    }
}

/// Sanitized per-request metadata: no prompt, source, response or credential content.
public struct ProviderReceipt: Codable, Equatable, Sendable {
    public let provider: String
    public let runtimeVersion: String
    public let model: String?
    public let durationMs: Int
    public let profile: String
    public let outcome: String
}

public struct ProviderRewrite: Sendable {
    public let response: RewriteResponse
    public let receipt: ProviderReceipt
}

public protocol RewriteProvider: AnyObject, Sendable {
    var id: ProviderID { get }
    /// True only for the development fixture; the UI labels it as not live.
    var isFixture: Bool { get }
    func checkReadiness() async -> ReadinessState
    func signInCommand() async -> SignInCommand?
    func rewrite(_ composed: ComposedRequest, timeout: TimeInterval) async throws -> ProviderRewrite
}

extension RewriteProvider {
    public var isFixture: Bool { false }
}

/// Locates an installed runtime without reading any credential store.
public struct ExecutableLocator: Sendable {
    public var environment: [String: String]
    public var overridePath: String?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment, overridePath: String? = nil) {
        self.environment = environment
        self.overridePath = overridePath
    }

    public func locate(_ name: String, extraCandidates: [String] = []) async -> String? {
        let fm = FileManager.default
        if let overridePath, fm.isExecutableFile(atPath: overridePath) { return overridePath }
        let home = environment["HOME"] ?? NSHomeDirectory()
        var candidates = extraCandidates.map { $0.replacingOccurrences(of: "~", with: home) }
        candidates += [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.npm-global/bin/\(name)",
            "\(home)/.volta/bin/\(name)",
            "\(home)/.bun/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        if let path = environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/\(name)" }
        }
        for c in candidates where fm.isExecutableFile(atPath: c) { return c }
        return await loginShellLookup(name)
    }

    /// GUI apps do not inherit the user's shell PATH; ask the login shell where
    /// the command lives. `name` is a fixed runtime name, never user text.
    private func loginShellLookup(_ name: String) async -> String? {
        let shell = environment["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let spec = ProcessSpec(
            executable: shell,
            arguments: ["-lc", "command -v \(name)"],
            environment: ProviderEnvironment.make(base: environment, executable: shell),
            workingDirectory: NSTemporaryDirectory(),
            timeout: 8,
            maxStdoutBytes: 64 * 1024
        )
        guard let out = try? await ProcessRunner.run(spec), out.succeeded else { return nil }
        let line = out.stdoutText.split(separator: "\n").map(String.init).last { $0.hasPrefix("/") }
        guard let line, FileManager.default.isExecutableFile(atPath: line) else { return nil }
        return line
    }
}

/// Private, empty working directory for one provider process.
public struct PrivateWorkspace {
    public let url: URL

    public static func create() throws -> PrivateWorkspace {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anti-slop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return PrivateWorkspace(url: url)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

enum RuntimeProbe {
    /// Run a short informational command (version/help/status). Output stays in memory.
    static func run(_ exe: String, _ args: [String], env: [String: String], timeout: TimeInterval = 20) async -> ProcessOutput? {
        guard let ws = try? PrivateWorkspace.create() else { return nil }
        defer { ws.remove() }
        let spec = ProcessSpec(executable: exe, arguments: args, environment: env,
                               workingDirectory: ws.url.path, timeout: timeout, maxStdoutBytes: 1024 * 1024)
        return try? await ProcessRunner.run(spec)
    }

    static func firstVersionToken(_ text: String) -> String? {
        for token in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "v(),"))
            let parts = t.split(separator: ".")
            if parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isNumber }) }) { return t }
        }
        return nil
    }
}

/// Classifies runtime error text into failure classes. Inputs are provider
/// error strings; outputs never echo them to the UI.
enum FailureClassifier {
    static func classify(_ text: String, httpStatus: Int? = nil, provider: ProviderID) -> ProviderFailure {
        let t = text.lowercased()
        if let s = httpStatus {
            if s == 401 || s == 403 { return .signInNeeded(provider) }
            if s == 429 { return .accountLimit(provider) }
            if s == 404 { return .modelUnavailable(provider) }
        }
        let signIn = ["not logged in", "please run /login", "log in", "login", "unauthorized", "401",
                      "authentication", "invalid api key", "oauth", "token expired", "expired token", "sign in"]
        let limits = ["usage limit", "rate limit", "429", "quota", "limit reached", "hit your limit",
                      "credit balance", "too many requests", "insufficient_quota"]
        let model = ["model not found", "model_not_found", "does not exist", "not supported with", "unknown model",
                     "invalid model", "model is not available", "unsupported model"]
        let network = ["enotfound", "econnrefused", "econnreset", "network", "fetch failed", "error sending request",
                       "stream disconnected", "connection failed", "could not resolve", "timed out", "offline",
                       "dns", "unreachable", "proxy connection failed"]
        if limits.contains(where: t.contains) { return .accountLimit(provider) }
        if model.contains(where: t.contains) { return .modelUnavailable(provider) }
        if signIn.contains(where: t.contains) { return .signInNeeded(provider) }
        if network.contains(where: t.contains) { return .offline(provider) }
        return .runtimeError(provider, "unclassified runtime error")
    }
}
