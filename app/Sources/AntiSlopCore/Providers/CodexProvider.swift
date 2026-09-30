import Foundation

/// Codex through `codex exec` (noninteractive mode) under the user's saved
/// ChatGPT sign-in. Flags verified against codex-cli 0.158.0 (`exec --help`,
/// `features list`, `--strict-config` override validation); a live request was
/// not possible from the development container (see app/IMPLEMENTATION_STATUS.md).
///
/// Isolation:
/// - `--ignore-user-config`, `--ignore-rules`: no user config.toml, MCP servers or
///   execpolicy rules (auth still comes from CODEX_HOME).
/// - `--disable <feature>` for every tool-granting feature the installed
///   version reports as enabled (shell, hooks, plugins, apps, browser, ...).
/// - `-s read-only`, `approval_policy="never"`, `web_search="disabled"`,
///   `project_doc_max_bytes=0` (no AGENTS.md), `--ephemeral`, private empty `-C`.
/// - `--strict-config` makes unknown override keys a hard error rather than
///   silently ignored isolation.
/// - The JSONL guard stops the run if any item other than a message,
///   reasoning or error appears (a command, file change, MCP or web call).
public final class CodexProvider: RewriteProvider, @unchecked Sendable {
    public let id: ProviderID = .codex
    let locator: ExecutableLocator
    let baseEnvironment: [String: String]
    let modelOverride: String?

    static let requiredExecFlags = ["--json", "--ephemeral", "--skip-git-repo-check", "--output-schema",
                                    "--output-last-message", "--sandbox", "--cd", "--ignore-user-config"]
    /// Features that grant tools, ambient context or side effects. Disabled when present and enabled.
    static let toolFeatures: Set<String> = [
        "hooks", "shell_tool", "unified_exec", "unified_exec_tty", "shell_snapshot", "apps", "plugins",
        "remote_plugin", "plugin_sharing", "recommended_plugins", "browser_use", "browser_use_external",
        "browser_use_full_cdp_access", "computer_use", "in_app_browser", "in_app_local_automation",
        "multi_agent", "multi_agent_v2", "image_generation", "view_image", "skill_search",
        "skill_mcp_dependency_install", "tool_suggest", "tool_call_mcp_elicitation", "goals", "memories",
        "workspace_dependencies", "sleep_tool", "code_mode_host", "realtime_conversation",
        "standalone_web_search", "apply_patch_freeform", "js_repl", "worktrees", "chronicle",
    ]
    static let allowedItemTypes: Set<String> = ["agent_message", "reasoning", "error"]

    struct Runtime {
        let executable: String
        let version: String
        let execFlags: Set<String>
        let featuresToDisable: [String]
    }

    public init(
        locator: ExecutableLocator = ExecutableLocator(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        modelOverride: String? = nil
    ) {
        self.locator = locator
        self.baseEnvironment = baseEnvironment
        self.modelOverride = modelOverride
    }

    func environment(for exe: String) -> [String: String] {
        ProviderEnvironment.make(base: baseEnvironment, executable: exe)
    }

    func discover() async -> Result<Runtime, ProviderFailure> {
        guard let exe = await locator.locate("codex") else { return .failure(.notInstalled(id)) }
        let env = environment(for: exe)
        guard let v = await RuntimeProbe.run(exe, ["--version"], env: env), v.succeeded,
              let version = RuntimeProbe.firstVersionToken(v.stdoutText) else {
            return .failure(.incompatibleRuntime(id, "version check failed"))
        }
        guard let help = await RuntimeProbe.run(exe, ["exec", "--help"], env: env), help.succeeded else {
            return .failure(.incompatibleRuntime(id, "exec help failed"))
        }
        let flags = ClaudeCodeProvider.parseFlags(help.stdoutText)
        let missing = Self.requiredExecFlags.filter { !flags.contains($0) }
        guard missing.isEmpty else {
            return .failure(.incompatibleRuntime(id, "missing \(missing.joined(separator: ","))"))
        }
        var disable: [String] = []
        if let list = await RuntimeProbe.run(exe, ["features", "list"], env: env), list.succeeded {
            disable = Self.featuresToDisable(fromList: list.stdoutText)
        }
        return .success(Runtime(executable: exe, version: version, execFlags: flags, featuresToDisable: disable))
    }

    /// Parse `codex features list` rows: `name  stage  effective`.
    static func featuresToDisable(fromList text: String) -> [String] {
        var out: [String] = []
        for line in text.split(separator: "\n") {
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard cols.count >= 3, let enabled = cols.last else { continue }
            let name = cols[0]
            let stage = cols[1...(cols.count - 2)].joined(separator: " ")
            guard toolFeatures.contains(name), stage != "removed", enabled == "true" else { continue }
            out.append(name)
        }
        return out.sorted()
    }

    /// TOML basic string for a `-c key=value` override.
    static func tomlString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// `model`/`reasoning` are the writer's choice for this request; nil sends nothing.
    func arguments(runtime: Runtime, instructions: String, schemaPath: String, lastMessagePath: String, workdir: String,
                   model: String? = nil, reasoning: String? = nil) -> [String] {
        var args = ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config",
                    "--sandbox", "read-only", "--cd", workdir,
                    "--output-schema", schemaPath, "--output-last-message", lastMessagePath]
        let f = runtime.execFlags
        if f.contains("--ignore-rules") { args.append("--ignore-rules") }
        if f.contains("--strict-config") { args.append("--strict-config") }
        if f.contains("--color") { args += ["--color", "never"] }
        args += ["-c", "approval_policy=\"never\"",
                 "-c", "web_search=\"disabled\"",
                 "-c", "project_doc_max_bytes=0",
                 "-c", "history.persistence=\"none\"",
                 "-c", "developer_instructions=" + Self.tomlString(instructions)]
        if let reasoning { args += ["-c", "model_reasoning_effort=" + Self.tomlString(reasoning)] }
        if let model = model ?? modelOverride { args += ["--model", model] }
        for feature in runtime.featuresToDisable { args += ["--disable", feature] }
        args.append("-")
        return args
    }

    public func signInCommand() async -> SignInCommand? {
        guard let exe = await locator.locate("codex") else { return nil }
        return SignInCommand(executable: exe, arguments: ["login"],
                             explanation: "Opens Codex's own sign-in in Terminal. Choose Sign in with ChatGPT.")
    }

    public func checkReadiness() async -> ReadinessState {
        let runtime: Runtime
        switch await discover() {
        case .failure(.notInstalled): return .unavailable("Install Codex, then check again.")
        case .failure(let f): return .constrained(f.userMessage)
        case .success(let rt): runtime = rt
        }
        let env = environment(for: runtime.executable)
        guard let status = await RuntimeProbe.run(runtime.executable, ["login", "status"], env: env) else {
            return .error("Couldn't run Codex.")
        }
        switch Self.loginState(status) {
        case .signedOut: return .signInNeeded("Sign in to Codex with your ChatGPT account.")
        case .apiKey: return .constrained("Codex is signed in with an API key. Sign in with ChatGPT instead.")
        case .unknown: return .error("Codex didn't report its sign-in state.")
        case .chatGPT: break
        }
        do {
            _ = try await invoke(
                runtime: runtime,
                instructions: "Anti-slop readiness check. Return {\"ok\": true} and nothing else.",
                schema: #"{"type":"object","additionalProperties":false,"properties":{"ok":{"type":"boolean"}},"required":["ok"]}"#,
                stdin: "Return ok as true.",
                timeout: Limits.readinessTimeout,
                validate: { text in
                    guard let d = text.data(using: .utf8),
                          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          (o["ok"] as? Bool) == true else { return false }
                    return true
                }
            )
            return .ready(ReadyDetails(runtimeVersion: runtime.version, model: modelOverride,
                                       account: "ChatGPT account", checkedAt: Date()))
        } catch let f as ProviderFailure {
            return ClaudeCodeProvider.readiness(for: f)
        } catch {
            return .error("Couldn't run Codex.")
        }
    }

    enum LoginState { case chatGPT, apiKey, signedOut, unknown }

    static func loginState(_ out: ProcessOutput) -> LoginState {
        let text = (out.stdoutText + "\n" + out.stderrText).lowercased()
        if text.contains("not logged in") { return .signedOut }
        if text.contains("api key") { return .apiKey }
        if text.contains("chatgpt") && out.termination == .exited(0) { return .chatGPT }
        if out.termination != .exited(0) { return .signedOut }
        return .unknown
    }

    /// Discover the runtime and recheck the login mode per request, so an
    /// API-key login is never used silently.
    func signedInRuntime() async throws -> Runtime {
        let runtime: Runtime
        switch await discover() {
        case .failure(let f): throw f
        case .success(let rt): runtime = rt
        }
        let env = environment(for: runtime.executable)
        if let status = await RuntimeProbe.run(runtime.executable, ["login", "status"], env: env) {
            switch Self.loginState(status) {
            case .signedOut: throw ProviderFailure.signInNeeded(id)
            case .apiKey: throw ProviderFailure.apiBillingBlocked(id, "api key login")
            default: break
            }
        }
        return runtime
    }

    /// The runtime's own model catalog (`codex debug models`). No inference and
    /// no sign-in needed; only models the catalog marks for listing are offered.
    public func availableModels() async throws -> [ModelOption] {
        let runtime: Runtime
        switch await discover() {
        case .failure(let f): throw f
        case .success(let rt): runtime = rt
        }
        guard let out = await RuntimeProbe.run(runtime.executable, ["debug", "models"],
                                               env: environment(for: runtime.executable)),
              out.succeeded, let models = ModelCatalogParser.codexCatalog(out.stdout) else {
            throw ProviderFailure.incompatibleRuntime(id, "model catalog unavailable")
        }
        return models
    }

    public func detect(_ composed: ComposedRequest, timeout: TimeInterval) async throws -> ProviderDetection {
        let runtime = try await signedInRuntime()
        let started = Date()
        let text = try await invoke(runtime: runtime, instructions: composed.instructions,
                                    schema: DetectionValidator.providerWireSchema,
                                    stdin: composed.dataMessage, timeout: timeout, validate: nil,
                                    model: composed.model, reasoning: composed.reasoning, trace: composed.trace)
        switch DetectionValidator.validate(jsonText: text, originalSelection: composed.request.selectedText) {
        case .failure(let e): throw ProviderFailure.malformedResponse(id, e)
        case .success(let response):
            let receipt = ProviderReceipt(provider: id.rawValue, runtimeVersion: runtime.version, model: composed.model ?? modelOverride,
                                          durationMs: Int(Date().timeIntervalSince(started) * 1000),
                                          profile: composed.profile.rawValue, outcome: "ok")
            return ProviderDetection(response: response, receipt: receipt)
        }
    }

    public func rewrite(_ composed: ComposedRequest, timeout: TimeInterval) async throws -> ProviderRewrite {
        let runtime = try await signedInRuntime()
        let started = Date()
        let text = try await invoke(runtime: runtime, instructions: composed.instructions,
                                    schema: ResponseValidator.providerWireSchema,
                                    stdin: composed.dataMessage, timeout: timeout, validate: nil,
                                    model: composed.model, reasoning: composed.reasoning, trace: composed.trace)
        switch ResponseValidator.validate(jsonText: text, originalSelection: composed.request.selectedText) {
        case .failure(let e): throw ProviderFailure.malformedResponse(id, e)
        case .success(let response):
            let receipt = ProviderReceipt(provider: id.rawValue, runtimeVersion: runtime.version, model: composed.model ?? modelOverride,
                                          durationMs: Int(Date().timeIntervalSince(started) * 1000),
                                          profile: composed.profile.rawValue, outcome: "ok")
            return ProviderRewrite(response: response, receipt: receipt)
        }
    }

    func invoke(runtime: Runtime, instructions: String, schema: String, stdin: String,
                timeout: TimeInterval, validate: ((String) -> Bool)?,
                model: String? = nil, reasoning: String? = nil, trace: RequestTrace? = nil) async throws -> String {
        let ws = try PrivateWorkspace.create()
        defer { ws.remove() }
        // Schema and last-message files live outside the (empty) working root.
        let side = try PrivateWorkspace.create()
        defer { side.remove() }
        let schemaURL = side.url.appendingPathComponent("response.schema.json")
        let lastURL = side.url.appendingPathComponent("last-message.txt")
        try Data(schema.utf8).write(to: schemaURL, options: .atomic)

        let jsonl = CodexEventGuard()
        let spec = ProcessSpec(
            executable: runtime.executable,
            arguments: arguments(runtime: runtime, instructions: instructions, schemaPath: schemaURL.path,
                                 lastMessagePath: lastURL.path, workdir: ws.url.path, model: model, reasoning: reasoning),
            environment: environment(for: runtime.executable),
            workingDirectory: ws.url.path,
            stdin: Data(stdin.utf8),
            timeout: timeout
        )
        trace?.recordInvocation(executable: spec.executable, arguments: spec.arguments, schema: schema)
        let out: ProcessOutput
        do {
            out = try await ProcessRunner.run(spec) { line in jsonl.inspect(line) }
        } catch {
            throw ProviderFailure.notInstalled(id)
        }
        trace?.recordOutput(out, rawResponse: (try? Data(contentsOf: lastURL)).map { String(decoding: $0, as: UTF8.self) })
        switch out.stopReason {
        case .cancelled?: throw ProviderFailure.cancelled
        case .timedOut?:
            // A timeout during repeated reconnects is a connectivity failure.
            if jsonl.sawReconnect { throw ProviderFailure.offline(id) }
            throw ProviderFailure.timedOut(id)
        case .outputLimit?: throw ProviderFailure.malformedResponse(id, .tooLong("output"))
        case .aborted(let why)?: throw ProviderFailure.toolUseBlocked(id, why)
        case nil: break
        }
        if out.stderrText.contains("unknown configuration field") || out.stderrText.contains("Unknown feature flag") {
            throw ProviderFailure.incompatibleRuntime(id, "config override rejected")
        }
        guard out.termination == .exited(0), !jsonl.turnFailed else {
            throw FailureClassifier.classify((jsonl.lastError ?? "") + " " + out.stderrText, provider: id)
        }
        guard let data = try? Data(contentsOf: lastURL) else {
            throw ProviderFailure.malformedResponse(id, .notJSON)
        }
        let text = String(decoding: data, as: UTF8.self)
        if let validate, !validate(text) { throw ProviderFailure.malformedResponse(id, .notSingleObject) }
        return text
    }
}

/// Watches `codex exec --json` events; only messages, reasoning and errors are allowed.
final class CodexEventGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var _lastError: String?
    private var _turnFailed = false
    private var _sawReconnect = false

    var lastError: String? { lock.lock(); defer { lock.unlock() }; return _lastError }
    var turnFailed: Bool { lock.lock(); defer { lock.unlock() }; return _turnFailed }
    var sawReconnect: Bool { lock.lock(); defer { lock.unlock() }; return _sawReconnect }

    func inspect(_ line: String) -> LineVerdict {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return .proceed }
        switch type {
        case "item.started", "item.updated", "item.completed":
            let itemType = (event["item"] as? [String: Any])?["type"] as? String ?? "unknown"
            if !CodexProvider.allowedItemTypes.contains(itemType) { return .abort("item:\(itemType)") }
        case "error":
            let msg = event["message"] as? String ?? ""
            lock.lock()
            _lastError = msg
            if msg.lowercased().contains("reconnecting") { _sawReconnect = true }
            lock.unlock()
        case "turn.failed":
            let msg = ((event["error"] as? [String: Any])?["message"] as? String) ?? ""
            lock.lock(); _turnFailed = true; _lastError = msg; lock.unlock()
        default:
            break
        }
        return .proceed
    }
}
