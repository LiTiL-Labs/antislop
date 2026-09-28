import Foundation

/// Claude Code through the unmodified official CLI in print mode, under the
/// user's own `claude auth login` sign-in. Verified against Claude Code
/// 2.1.283; capabilities are rechecked from `--help` on each discovery.
///
/// Isolation (flags are omitted only when an older runtime lacks them, and the
/// stream guard below enforces the result either way):
/// - `--tools ""`: no built-in tools. `--json-schema` adds only the internal
///   `StructuredOutput` tool, which is the one tool the guard allows.
/// - `--safe-mode`, `--setting-sources ""`, `--settings {"disableAllHooks":true}`:
///   no CLAUDE.md, skills, plugins, hooks, custom agents or user/project settings.
/// - `--strict-mcp-config` with no config: no MCP servers.
/// - `--no-session-persistence`, `--disable-slash-commands`, `--permission-prompts none`.
/// - Private empty working directory and an allowlisted environment (no inherited API keys).
public final class ClaudeCodeProvider: RewriteProvider, @unchecked Sendable {
    public let id: ProviderID = .claudeCode
    let locator: ExecutableLocator
    let baseEnvironment: [String: String]
    let explicitPassthrough: [String]
    let modelOverride: String?

    /// `apiKeySource` values from the stream's init event that mean account
    /// sign-in rather than API-key billing.
    static let accountKeySources: Set<String> = ["none"]
    static let requiredFlags = ["--print", "--output-format", "--json-schema", "--tools",
                                "--no-session-persistence", "--strict-mcp-config", "--system-prompt"]
    static let allowedTools: Set<String> = ["StructuredOutput"]

    struct Runtime {
        let executable: String
        let version: String
        let flags: Set<String>
        let hasAuthStatus: Bool
    }

    public init(
        locator: ExecutableLocator = ExecutableLocator(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        explicitPassthrough: [String] = [],
        modelOverride: String? = nil
    ) {
        self.locator = locator
        self.baseEnvironment = baseEnvironment
        self.explicitPassthrough = explicitPassthrough
        self.modelOverride = modelOverride
    }

    func environment(for exe: String) -> [String: String] {
        ProviderEnvironment.make(base: baseEnvironment, executable: exe, explicitPassthrough: explicitPassthrough)
    }

    func discover() async -> Result<Runtime, ProviderFailure> {
        guard let exe = await locator.locate("claude", extraCandidates: ["~/.claude/local/claude"]) else {
            return .failure(.notInstalled(id))
        }
        let env = environment(for: exe)
        guard let v = await RuntimeProbe.run(exe, ["--version"], env: env), v.succeeded,
              let version = RuntimeProbe.firstVersionToken(v.stdoutText) else {
            return .failure(.incompatibleRuntime(id, "version check failed"))
        }
        guard let help = await RuntimeProbe.run(exe, ["--help"], env: env), help.succeeded else {
            return .failure(.incompatibleRuntime(id, "help check failed"))
        }
        let flags = Self.parseFlags(help.stdoutText)
        let missing = Self.requiredFlags.filter { !flags.contains($0) }
        guard missing.isEmpty else {
            return .failure(.incompatibleRuntime(id, "missing \(missing.joined(separator: ","))"))
        }
        let hasAuth = help.stdoutText.contains("\n  auth ")
        return .success(Runtime(executable: exe, version: version, flags: flags, hasAuthStatus: hasAuth))
    }

    static func parseFlags(_ help: String) -> Set<String> {
        var out = Set<String>()
        for token in help.split(whereSeparator: { " ,\n\t".contains($0) }) where token.hasPrefix("--") {
            out.insert(String(token.prefix { $0 != "=" && $0 != "<" && $0 != "[" }))
        }
        return out
    }

    func arguments(runtime: Runtime, systemPrompt: String, schema: String) -> [String] {
        var args = ["--print", "--output-format", "stream-json", "--verbose",
                    "--json-schema", schema,
                    "--tools", "",
                    "--strict-mcp-config",
                    "--no-session-persistence",
                    "--system-prompt", systemPrompt]
        let f = runtime.flags
        if f.contains("--safe-mode") { args.append("--safe-mode") }
        if f.contains("--setting-sources") { args += ["--setting-sources", ""] }
        if f.contains("--settings") { args += ["--settings", #"{"disableAllHooks":true}"#] }
        if f.contains("--disable-slash-commands") { args.append("--disable-slash-commands") }
        if f.contains("--permission-prompts") { args += ["--permission-prompts", "none"] }
        if let modelOverride, f.contains("--model") { args += ["--model", modelOverride] }
        return args
    }

    public func signInCommand() async -> SignInCommand? {
        guard case .success(let rt) = await discover() else {
            guard let exe = await locator.locate("claude", extraCandidates: ["~/.claude/local/claude"]) else { return nil }
            return SignInCommand(executable: exe, arguments: ["auth", "login", "--claudeai"],
                                 explanation: "Opens Claude Code's own sign-in in Terminal.")
        }
        let args = rt.hasAuthStatus ? ["auth", "login", "--claudeai"] : []
        return SignInCommand(executable: rt.executable, arguments: args,
                             explanation: "Opens Claude Code's own sign-in in Terminal. Choose your Claude account.")
    }

    public func checkReadiness() async -> ReadinessState {
        let runtime: Runtime
        switch await discover() {
        case .failure(.notInstalled):
            return .unavailable("Install Claude Code, then check again.")
        case .failure(let f):
            return .constrained(f.userMessage)
        case .success(let rt):
            runtime = rt
        }
        let env = environment(for: runtime.executable)
        if runtime.hasAuthStatus,
           let st = await RuntimeProbe.run(runtime.executable, ["auth", "status", "--json"], env: env),
           let obj = try? JSONSerialization.jsonObject(with: st.stdout) as? [String: Any] {
            if (obj["loggedIn"] as? Bool) == false {
                return .signInNeeded("Sign in to Claude Code with your Claude account.")
            }
            if let provider = obj["apiProvider"] as? String, provider != "firstParty" {
                return .constrained("Claude Code is configured for \(provider), not your Claude account.")
            }
            if let method = (obj["authMethod"] as? String)?.lowercased(), method.contains("api_key") || method.contains("apikey") {
                return .constrained("Claude Code is signed in with an API key. Sign in with your Claude account instead.")
            }
        }
        // A harmless inference proves the runtime, sign-in and output contract.
        do {
            let probe = try await invoke(
                runtime: runtime,
                systemPrompt: "Anti-slop readiness check. Return {\"ok\": true} and nothing else.",
                schema: #"{"type":"object","additionalProperties":false,"properties":{"ok":{"type":"boolean"}},"required":["ok"]}"#,
                stdin: "Return ok as true.",
                timeout: Limits.readinessTimeout
            )
            guard (probe.structured["ok"] as? Bool) == true else {
                return .error("Claude Code answered, but not in the expected format.")
            }
            return .ready(ReadyDetails(runtimeVersion: runtime.version, model: probe.model,
                                       account: "Claude account", checkedAt: Date()))
        } catch let f as ProviderFailure {
            return Self.readiness(for: f)
        } catch {
            return .error("Couldn't run Claude Code.")
        }
    }

    static func readiness(for f: ProviderFailure) -> ReadinessState {
        switch f {
        case .signInNeeded: return .signInNeeded("Sign in to Claude Code with your Claude account.")
        case .accountLimit: return .accountLimit("Your Claude account has reached a usage limit.")
        case .offline: return .offline("Couldn't reach Claude. Check your connection.")
        case .apiBillingBlocked(_, let d): return .constrained("Claude Code would use API-key billing (\(d)). Sign in with your Claude account.")
        case .notInstalled: return .unavailable("Install Claude Code, then check again.")
        default: return .error(f.userMessage)
        }
    }

    public func rewrite(_ composed: ComposedRequest, timeout: TimeInterval) async throws -> ProviderRewrite {
        let runtime: Runtime
        switch await discover() {
        case .failure(let f): throw f
        case .success(let rt): runtime = rt
        }
        let started = Date()
        let result = try await invoke(runtime: runtime, systemPrompt: composed.instructions,
                                      schema: ResponseValidator.providerWireSchema,
                                      stdin: composed.dataMessage, timeout: timeout)
        switch ResponseValidator.validate(object: result.structured, originalSelection: composed.request.selectedText) {
        case .failure(let e): throw ProviderFailure.malformedResponse(id, e)
        case .success(let response):
            let receipt = ProviderReceipt(provider: id.rawValue, runtimeVersion: runtime.version, model: result.model,
                                          durationMs: Int(Date().timeIntervalSince(started) * 1000),
                                          profile: composed.profile.rawValue, outcome: "ok")
            return ProviderRewrite(response: response, receipt: receipt)
        }
    }

    struct InvocationResult {
        let structured: [String: Any]
        let model: String?
    }

    func invoke(runtime: Runtime, systemPrompt: String, schema: String, stdin: String, timeout: TimeInterval) async throws -> InvocationResult {
        let ws = try PrivateWorkspace.create()
        defer { ws.remove() }
        let guardState = StreamGuard()
        let spec = ProcessSpec(
            executable: runtime.executable,
            arguments: arguments(runtime: runtime, systemPrompt: systemPrompt, schema: schema),
            environment: environment(for: runtime.executable),
            workingDirectory: ws.url.path,
            stdin: Data(stdin.utf8),
            timeout: timeout
        )
        let out: ProcessOutput
        do {
            out = try await ProcessRunner.run(spec) { line in guardState.inspect(line) }
        } catch {
            throw ProviderFailure.notInstalled(id)
        }
        switch out.stopReason {
        case .cancelled?: throw ProviderFailure.cancelled
        case .timedOut?: throw ProviderFailure.timedOut(id)
        case .outputLimit?: throw ProviderFailure.malformedResponse(id, .tooLong("output"))
        case .aborted(let why)?:
            if why.hasPrefix("api_key_source") { throw ProviderFailure.apiBillingBlocked(id, why) }
            throw ProviderFailure.toolUseBlocked(id, why)
        case nil: break
        }
        guard let result = guardState.result else {
            throw FailureClassifier.classify(out.stderrText, provider: id)
        }
        let isError = (result["is_error"] as? Bool) ?? true
        let subtype = result["subtype"] as? String ?? ""
        if isError || subtype != "success" {
            let text = (result["result"] as? String) ?? ""
            let status = result["api_error_status"] as? Int
            throw FailureClassifier.classify(text + " " + subtype, httpStatus: status, provider: id)
        }
        guard let structured = result["structured_output"] as? [String: Any] else {
            throw ProviderFailure.malformedResponse(id, .notSingleObject)
        }
        return InvocationResult(structured: structured, model: guardState.model)
    }
}

/// Inspects the stream-json events as they arrive. It stops the process if the
/// runtime reports tools, MCP servers or an API-key credential source, or if the
/// model emits any tool call other than the structured-output mechanism.
final class StreamGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var _result: [String: Any]?
    private var _model: String?

    var result: [String: Any]? { lock.lock(); defer { lock.unlock() }; return _result }
    var model: String? { lock.lock(); defer { lock.unlock() }; return _model }

    func inspect(_ line: String) -> LineVerdict {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return .proceed }
        switch type {
        case "system" where (event["subtype"] as? String) == "init":
            let tools = (event["tools"] as? [String]) ?? []
            let extra = tools.filter { !ClaudeCodeProvider.allowedTools.contains($0) }
            if !extra.isEmpty { return .abort("tools_enabled:\(extra.count)") }
            if let mcp = event["mcp_servers"] as? [Any], !mcp.isEmpty { return .abort("mcp_servers:\(mcp.count)") }
            if let source = event["apiKeySource"] as? String, !ClaudeCodeProvider.accountKeySources.contains(source) {
                return .abort("api_key_source:\(source)")
            }
            lock.lock(); _model = event["model"] as? String; lock.unlock()
        case "assistant":
            let content = ((event["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
            for block in content where (block["type"] as? String) == "tool_use" {
                let name = block["name"] as? String ?? "?"
                if !ClaudeCodeProvider.allowedTools.contains(name) { return .abort("tool_use:\(name)") }
            }
        case "result":
            lock.lock(); _result = event; lock.unlock()
        default:
            break
        }
        return .proceed
    }
}
