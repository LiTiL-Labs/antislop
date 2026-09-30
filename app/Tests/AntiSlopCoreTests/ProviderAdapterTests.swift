import XCTest
@testable import AntiSlopCore

/// Adapter behavior against fake `claude` / `codex` executables. These prove
/// the app-side contract (arguments, isolation checks, parsing, error mapping);
/// they are not evidence of live provider connectivity.
final class FakeRuntime {
    let dir: URL
    var argvFile: URL { dir.appendingPathComponent("argv.txt") }
    var stdinFile: URL { dir.appendingPathComponent("stdin.txt") }
    var envFile: URL { dir.appendingPathComponent("env.txt") }
    let exe: URL

    init(name: String, mode: String) throws {
        dir = try PrivateWorkspace.create().url
        exe = dir.appendingPathComponent(name)
        let body = name == "claude" ? FakeRuntime.claudeScript : FakeRuntime.codexScript
        let script = body
            .replacingOccurrences(of: "@MODE@", with: mode)
            .replacingOccurrences(of: "@DIR@", with: dir.path)
        try Data(script.utf8).write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    var argv: [String] { Array(((try? String(contentsOf: argvFile, encoding: .utf8)) ?? "").components(separatedBy: "\u{1}").dropLast()) }
    var stdin: String { (try? String(contentsOf: stdinFile, encoding: .utf8)) ?? "" }
    var env: String { (try? String(contentsOf: envFile, encoding: .utf8)) ?? "" }

    static let claudeScript = #"""
    #!/bin/sh
    MODE="@MODE@"; DIR="@DIR@"
    case "$1" in
      --version) echo "2.1.283 (Claude Code)"; exit 0 ;;
      --help) cat <<'EOF'
    Usage: claude [options] [command] [prompt]
    Options:
      --effort <level>  x
      --input-format <format>  x
      --json-schema <schema>  JSON Schema
      --tools <tools...>  tools
      --no-session-persistence  x
      --strict-mcp-config  x
      --system-prompt <prompt>  x
      --output-format <format>  x
      -p, --print  x
      --safe-mode  x
      --setting-sources <sources>  x
      --settings <file-or-json>  x
      --disable-slash-commands  x
      --permission-prompts <target>  x
      --model <model>  x
    Commands:
      auth  Manage authentication
    EOF
        exit 0 ;;
      auth)
        if [ "$MODE" = signedout ]; then echo '{"loggedIn":false,"authMethod":"none","apiProvider":"firstParty"}'; exit 1; fi
        if [ "$MODE" = bedrock ]; then echo '{"loggedIn":true,"authMethod":"none","apiProvider":"bedrock"}'; exit 0; fi
        echo '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty"}'; exit 0 ;;
    esac
    : > "$DIR/argv.txt"; for a in "$@"; do printf '%s\001' "$a" >> "$DIR/argv.txt"; done
    cat > "$DIR/stdin.txt"; env > "$DIR/env.txt"
    if grep -q '"subtype":"initialize"' "$DIR/stdin.txt"; then
      echo '{"type":"control_response","response":{"subtype":"success","request_id":"anti-slop-models","response":{"models":[{"value":"default","displayName":"Default (recommended)","description":"Use the default model","supportedEffortLevels":["low","high"]},{"value":"sonnet","displayName":"Sonnet","resolvedModel":"claude-sonnet-5","supportedEffortLevels":["low","medium","high"]},{"value":"--evil","displayName":"Bad"},{"value":"haiku","displayName":"Haiku"}]}}}'
      exit 0
    fi
    SRC=none; TOOLS='["StructuredOutput"]'
    [ "$MODE" = apikey ] && SRC=ANTHROPIC_API_KEY
    [ "$MODE" = tools ] && TOOLS='["StructuredOutput","Bash","Read"]'
    echo "{\"type\":\"system\",\"subtype\":\"init\",\"tools\":$TOOLS,\"mcp_servers\":[],\"apiKeySource\":\"$SRC\",\"model\":\"fake-model\"}"
    if grep -q "Return ok as true" "$DIR/stdin.txt"; then OUT='{"ok":true}'; else OUT='{"intent":"Looks like a pilot update","rewritten_text":"The pilot may reduce review time for some teams.","note":null}'; fi
    [ "$MODE" = detect ] && OUT='{"summary":"One filler opener","findings":[{"quote":"It is worth noting that","issue":"Empty lead-in."}]}'
    case "$MODE" in
      hang) sleep 30 ;;
      tooluse) echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}'; sleep 5 ;;
      limit) echo '{"type":"result","subtype":"success","is_error":true,"result":"You have hit your limit · resets 5pm","api_error_status":429}' ;;
      auth_error) echo '{"type":"result","subtype":"success","is_error":true,"result":"Invalid API key · Please run /login","api_error_status":401}' ;;
      extra) echo '{"type":"result","subtype":"success","is_error":false,"structured_output":{"intent":"x","rewritten_text":"y","note":null,"ai_probability":0.8}}' ;;
      *) echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"StructuredOutput","input":{}}]}}'
         echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"\",\"structured_output\":$OUT}" ;;
    esac
    """#

    static let codexScript = #"""
    #!/bin/sh
    MODE="@MODE@"; DIR="@DIR@"
    case "$1" in
      --version) echo "codex-cli 0.158.0"; exit 0 ;;
      login)
        case "$MODE" in
          signedout) echo "Not logged in" >&2; exit 1 ;;
          apikey) echo "Logged in using an API key - sk-***" >&2; exit 0 ;;
          *) echo "Logged in using ChatGPT" >&2; exit 0 ;;
        esac ;;
      debug)
        echo '{"models":[{"slug":"gpt-b","display_name":"B","visibility":"list","priority":2,"default_reasoning_level":"medium","supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"}]},{"slug":"gpt-a","display_name":"A","visibility":"list","priority":1,"supported_reasoning_levels":[{"effort":"low"},{"effort":"high"}]},{"slug":"hidden","visibility":"hide"}]}'
        exit 0 ;;
      features)
        printf 'hooks                stable             true\nshell_tool           stable             true\nplugins              stable             true\nmemories             stable             false\nsearch_tool          removed            false\nfast_mode            stable             true\nunified_exec         under development  true\n'
        exit 0 ;;
    esac
    if [ "$1" = exec ] && [ "$2" = --help ]; then
      echo "--json --ephemeral --skip-git-repo-check --output-schema <FILE> --output-last-message <FILE> --sandbox <MODE> --cd <DIR> --ignore-user-config --ignore-rules --strict-config --color <C>"
      exit 0
    fi
    : > "$DIR/argv.txt"; for a in "$@"; do printf '%s\001' "$a" >> "$DIR/argv.txt"; done
    cat > "$DIR/stdin.txt"; env > "$DIR/env.txt"
    LAST=""; PREV=""
    for a in "$@"; do [ "$PREV" = --output-last-message ] && LAST="$a"; PREV="$a"; done
    echo '{"type":"thread.started","thread_id":"t"}'; echo '{"type":"turn.started"}'
    if grep -q "Return ok as true" "$DIR/stdin.txt"; then OUT='{"ok":true}'; else OUT='{"intent":"Looks like a pilot update","rewritten_text":"The pilot may reduce review time for some teams.","note":null}'; fi
    [ "$MODE" = detect ] && OUT='{"summary":"One filler opener","findings":[{"quote":"It is worth noting that","issue":"Empty lead-in."}]}'
    case "$MODE" in
      command) echo '{"type":"item.started","item":{"id":"i","type":"command_execution","command":"cat ~/.ssh/id_rsa"}}'; sleep 5 ;;
      offline) echo '{"type":"error","message":"Reconnecting... 1/5 (stream disconnected before completion)"}'; sleep 30 ;;
      limit) echo '{"type":"turn.failed","error":{"message":"You have hit your usage limit. Try again later."}}'; exit 1 ;;
      prose) echo '{"type":"item.completed","item":{"id":"m","type":"agent_message","text":"x"}}'; printf 'Here you go: %s' "$OUT" > "$LAST" ;;
      *) echo '{"type":"item.completed","item":{"id":"m","type":"agent_message","text":"x"}}'; printf '%s' "$OUT" > "$LAST"
         echo '{"type":"turn.completed","usage":{}}' ;;
    esac
    """#
}

final class ProviderAdapterTests: XCTestCase {
    /// Fakes delete their directory on deinit, so keep them alive for the test.
    var fakes: [FakeRuntime] = []

    let secretKeyEnv = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "ANTHROPIC_API_KEY": "sk-ant-should-not-pass",
                        "OPENAI_API_KEY": "sk-should-not-pass"]

    func composed(_ text: String = "It is worth noting that the pilot may reduce review time for some teams.") throws -> ComposedRequest {
        try PromptComposer.compose(capture: capture(text), settings: AppSettings(providerID: .claudeCode, customWriterInstructions: "Keep the tone measured."))
    }

    func claude(_ mode: String) throws -> (ClaudeCodeProvider, FakeRuntime) {
        let fake = try FakeRuntime(name: "claude", mode: mode)
        fakes.append(fake)
        return (ClaudeCodeProvider(locator: ExecutableLocator(environment: secretKeyEnv, overridePath: fake.exe.path),
                                   baseEnvironment: secretKeyEnv), fake)
    }

    func codex(_ mode: String) throws -> (CodexProvider, FakeRuntime) {
        let fake = try FakeRuntime(name: "codex", mode: mode)
        fakes.append(fake)
        return (CodexProvider(locator: ExecutableLocator(environment: secretKeyEnv, overridePath: fake.exe.path),
                              baseEnvironment: secretKeyEnv), fake)
    }

    // MARK: Claude Code

    func testClaudeRewriteUsesIsolatedArgvAndStdin() async throws {
        let (p, fake) = try claude("ok")
        let c = try composed()
        let r = try await p.rewrite(c, timeout: 10)
        XCTAssertEqual(r.response.rewrittenText, "The pilot may reduce review time for some teams.")
        XCTAssertEqual(r.receipt.model, "fake-model")
        XCTAssertEqual(r.receipt.runtimeVersion, "2.1.283")
        let argv = fake.argv
        for flag in ["--print", "--safe-mode", "--strict-mcp-config", "--no-session-persistence", "--disable-slash-commands"] {
            XCTAssertTrue(argv.contains(flag), flag)
        }
        XCTAssertEqual(argv[argv.firstIndex(of: "--tools")! + 1], "", "all built-in tools disabled")
        XCTAssertEqual(argv[argv.firstIndex(of: "--setting-sources")! + 1], "")
        XCTAssertEqual(argv[argv.firstIndex(of: "--permission-prompts")! + 1], "none")
        XCTAssertEqual(argv[argv.firstIndex(of: "--system-prompt")! + 1], c.instructions)
        // A24/A38: selection and writer instructions only travel on stdin.
        XCTAssertFalse(argv.joined().contains("worth noting"))
        XCTAssertFalse(argv.joined().contains("Keep the tone measured"))
        XCTAssertEqual(fake.stdin, c.dataMessage)
        XCTAssertFalse(fake.env.contains("sk-ant-should-not-pass"))
        XCTAssertFalse(fake.env.contains("ANTHROPIC_API_KEY"))
    }

    func detectRequest() throws -> ComposedRequest {
        try PromptComposer.compose(capture: capture("It is worth noting that the pilot may reduce review time for some teams."),
                                   settings: AppSettings(providerID: .claudeCode), mode: .detect)
    }

    /// Slop-detection mode runs through the same isolated invocation with its own
    /// instructions and schema; a rewrite-shaped answer is never accepted as findings.
    func testClaudeDetectUsesDetectionSchemaAndInstructions() async throws {
        let (p, fake) = try claude("detect")
        let c = try detectRequest()
        let r = try await p.detect(c, timeout: 10)
        XCTAssertEqual(r.response.findings.map(\.quote), ["It is worth noting that"])
        let argv = fake.argv
        XCTAssertEqual(argv[argv.firstIndex(of: "--json-schema")! + 1], DetectionValidator.providerWireSchema)
        XCTAssertEqual(argv[argv.firstIndex(of: "--system-prompt")! + 1], c.instructions)
        XCTAssertEqual(argv[argv.firstIndex(of: "--tools")! + 1], "")
        XCTAssertEqual(fake.stdin, c.dataMessage)

        let (wrong, _) = try claude("ok")
        do {
            _ = try await wrong.detect(c, timeout: 10)
            XCTFail("a rewrite object was accepted as findings")
        } catch let f as ProviderFailure {
            guard case .malformedResponse = f else { return XCTFail("\(f)") }
        }
    }

    func testCodexDetectUsesDetectionInstructions() async throws {
        let (p, fake) = try codex("detect")
        let c = try detectRequest()
        let r = try await p.detect(c, timeout: 10)
        XCTAssertEqual(r.response.summary, "One filler opener")
        XCTAssertTrue(fake.argv.contains("developer_instructions=" + CodexProvider.tomlString(c.instructions)))
        XCTAssertEqual(fake.stdin, c.dataMessage)
        let (signedOut, _) = try codex("signedout")
        do {
            _ = try await signedOut.detect(c, timeout: 10)
            XCTFail("signed-out Codex ran")
        } catch let f as ProviderFailure {
            XCTAssertEqual(f, .signInNeeded(.codex))
        }
    }

    func testClaudeReadinessRequiresInferenceAndAccountSignIn() async throws {
        let (ok, _) = try claude("ok")
        let ready = await ok.checkReadiness()
        guard case .ready(let d) = ready else { return XCTFail("\(ready)") }
        XCTAssertEqual(d.runtimeVersion, "2.1.283")
        XCTAssertEqual(d.model, "fake-model")

        let (out, _) = try claude("signedout")
        if case .signInNeeded = await out.checkReadiness() {} else { XCTFail("signed out must not be ready") }
        let (bedrock, _) = try claude("bedrock")
        if case .constrained = await bedrock.checkReadiness() {} else { XCTFail("cloud provider switch must be surfaced") }
        let (key, _) = try claude("apikey")
        if case .constrained = await key.checkReadiness() {} else { XCTFail("API-key source must not be Ready") }
        let (limit, _) = try claude("limit")
        if case .accountLimit = await limit.checkReadiness() {} else { XCTFail("limit") }
    }

    func testClaudeGuardsAndErrorMapping() async throws {
        let c = try composed()
        func failure(_ mode: String, timeout: TimeInterval = 10) async throws -> ProviderFailure? {
            let (p, _) = try claude(mode)
            do { _ = try await p.rewrite(c, timeout: timeout); return nil } catch { return error as? ProviderFailure }
        }
        let tools = try await failure("tools")
        guard case .toolUseBlocked = tools else { return XCTFail("\(String(describing: tools))") }
        let toolUse = try await failure("tooluse")
        guard case .toolUseBlocked(_, let why) = toolUse else { return XCTFail("\(String(describing: toolUse))") }
        XCTAssertEqual(why, "tool_use:Bash")
        let key = try await failure("apikey")
        guard case .apiBillingBlocked = key else { return XCTFail("\(String(describing: key))") }
        let limit = try await failure("limit")
        XCTAssertEqual(limit, .accountLimit(.claudeCode))
        let auth = try await failure("auth_error")
        XCTAssertEqual(auth, .signInNeeded(.claudeCode))
        let extra = try await failure("extra")
        XCTAssertEqual(extra, .malformedResponse(.claudeCode, .unexpectedProperty("ai_probability")))
        let hang = try await failure("hang", timeout: 0.8)
        XCTAssertEqual(hang, .timedOut(.claudeCode))
    }

    func testClaudeCancellation() async throws {
        let (p, _) = try claude("hang")
        let c = try composed()
        let task = Task { try await p.rewrite(c, timeout: 30) }
        try await Task.sleep(nanoseconds: 400_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("expected cancellation") } catch {
            XCTAssertEqual(error as? ProviderFailure, .cancelled)
        }
    }

    // MARK: Codex

    func testCodexRewriteUsesIsolationFlagsAndDeveloperInstructions() async throws {
        let (p, fake) = try codex("ok")
        let c = try composed()
        let r = try await p.rewrite(c, timeout: 10)
        XCTAssertEqual(r.response.intent, "Looks like a pilot update")
        let argv = fake.argv
        for flag in ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules", "--strict-config"] {
            XCTAssertTrue(argv.contains(flag), flag)
        }
        XCTAssertEqual(argv[argv.firstIndex(of: "--sandbox")! + 1], "read-only")
        XCTAssertTrue(argv.contains("approval_policy=\"never\""))
        XCTAssertTrue(argv.contains("web_search=\"disabled\""))
        XCTAssertTrue(argv.contains("project_doc_max_bytes=0"))
        XCTAssertTrue(argv.contains("developer_instructions=" + CodexProvider.tomlString(c.instructions)))
        // Only enabled, present tool features are disabled (unknown flags are hard errors in Codex).
        let disabled = argv.indices.filter { argv[$0] == "--disable" }.map { argv[$0 + 1] }
        XCTAssertEqual(disabled, ["hooks", "plugins", "shell_tool", "unified_exec"])
        XCTAssertEqual(argv.last, "-")
        XCTAssertFalse(argv.joined().contains("worth noting"))
        XCTAssertEqual(fake.stdin, c.dataMessage)
        XCTAssertFalse(fake.env.contains("sk-should-not-pass"))
    }

    func testCodexReadinessAndLoginModes() async throws {
        let (ok, _) = try codex("ok")
        if case .ready(let d) = await ok.checkReadiness() { XCTAssertEqual(d.account, "ChatGPT account") } else { XCTFail("ready") }
        let (out, _) = try codex("signedout")
        if case .signInNeeded = await out.checkReadiness() {} else { XCTFail("signed out") }
        let (key, _) = try codex("apikey")
        if case .constrained = await key.checkReadiness() {} else { XCTFail("API-key login must not be Ready") }
        let c = try composed()
        do { _ = try await key.rewrite(c, timeout: 10); XCTFail("API-key login must not rewrite") } catch {
            guard case .apiBillingBlocked = error as? ProviderFailure else { return XCTFail("\(error)") }
        }
    }

    func testCodexGuardsAndErrorMapping() async throws {
        let c = try composed()
        func failure(_ mode: String, timeout: TimeInterval = 10) async throws -> ProviderFailure? {
            let (p, _) = try codex(mode)
            do { _ = try await p.rewrite(c, timeout: timeout); return nil } catch { return error as? ProviderFailure }
        }
        let command = try await failure("command")
        XCTAssertEqual(command, .toolUseBlocked(.codex, "item:command_execution"))
        let limit = try await failure("limit")
        XCTAssertEqual(limit, .accountLimit(.codex))
        let prose = try await failure("prose")
        XCTAssertEqual(prose, .malformedResponse(.codex, .notSingleObject))
        let offline = try await failure("offline", timeout: 1)
        XCTAssertEqual(offline, .offline(.codex))
    }

    func testTomlStringEscaping() {
        XCTAssertEqual(CodexProvider.tomlString("a\"b\\c\nd\te\u{1}“é”"), "\"a\\\"b\\\\c\\nd\\te\\u0001“é”\"")
    }

    func testFeatureListParsing() {
        let list = """
        WARNING: proceeding, even though we could not create PATH aliases
        hooks                                    stable             true
        memories                                 stable             false
        unified_exec                             under development  true
        search_tool                              removed            true
        fast_mode                                stable             true
        """
        XCTAssertEqual(CodexProvider.featuresToDisable(fromList: list), ["hooks", "unified_exec"])
    }

    func testVersionTokenParsing() {
        XCTAssertEqual(RuntimeProbe.firstVersionToken("2.1.283 (Claude Code)\n"), "2.1.283")
        XCTAssertEqual(RuntimeProbe.firstVersionToken("codex-cli 0.158.0"), "0.158.0")
        XCTAssertEqual(RuntimeProbe.firstVersionToken("codex-cli 0.160.0-alpha.2"), "0.160.0-alpha.2")
        XCTAssertEqual(RuntimeProbe.firstVersionToken("tool v1.4+build.7"), "1.4+build.7")
        XCTAssertEqual(RuntimeProbe.firstVersionToken("(2.0.0-dev)"), "2.0.0-dev")
        XCTAssertNil(RuntimeProbe.firstVersionToken("codex-cli dev"))
        XCTAssertNil(RuntimeProbe.firstVersionToken("1. 2.x 1.2- ٣.٤"))
    }

    func testFailureClassifier() {
        XCTAssertEqual(FailureClassifier.classify("Claude AI usage limit reached|1760000000", provider: .claudeCode), .accountLimit(.claudeCode))
        XCTAssertEqual(FailureClassifier.classify("OAuth token has expired. Please run /login", provider: .claudeCode), .signInNeeded(.claudeCode))
        XCTAssertEqual(FailureClassifier.classify("model_not_found: gpt-x", provider: .codex), .modelUnavailable(.codex))
        XCTAssertEqual(FailureClassifier.classify("error sending request for url", provider: .codex), .offline(.codex))
        XCTAssertEqual(FailureClassifier.classify("", httpStatus: 429, provider: .codex), .accountLimit(.codex))
        XCTAssertEqual(FailureClassifier.classify("weird", provider: .codex), .runtimeError(.codex, "unclassified runtime error"))
    }
}
