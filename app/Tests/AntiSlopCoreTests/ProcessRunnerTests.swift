import XCTest
@testable import AntiSlopCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class ProcessRunnerTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = try PrivateWorkspace.create().url
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func spec(_ exe: String, _ args: [String], stdin: String = "", timeout: TimeInterval = 10, cap: Int = 1 << 20) -> ProcessSpec {
        ProcessSpec(executable: exe, arguments: args, environment: ["PATH": "/usr/bin:/bin"], workingDirectory: dir.path,
                    stdin: Data(stdin.utf8), timeout: timeout, maxStdoutBytes: cap)
    }

    func testStdinArgvAndWorkingDirectory() async throws {
        let text = "Selected text with $(dangerous) `backticks` and \"quotes\"\nline two ✓"
        let out = try await ProcessRunner.run(spec("/bin/cat", [], stdin: text))
        XCTAssertTrue(out.succeeded)
        XCTAssertEqual(out.stdoutText, text, "content travels on stdin untouched")
        let argv = try await ProcessRunner.run(spec("/bin/sh", ["-c", "printf '%s|' \"$@\"", "sh", "a b", "$(x)", ""]))
        XCTAssertEqual(argv.stdoutText, "a b|$(x)||", "arguments are an argv vector, never re-parsed")
        let pwd = try await ProcessRunner.run(spec("/bin/sh", ["-c", "pwd -P"]))
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let real = String(cString: realpath(dir.path, &buf))
        XCTAssertEqual(pwd.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines), real)
    }

    func testExitStatusIsReported() async throws {
        let out = try await ProcessRunner.run(spec("/bin/sh", ["-c", "echo err >&2; exit 3"]))
        XCTAssertEqual(out.termination, .exited(3))
        XCTAssertEqual(out.stderrText, "err\n")
        XCTAssertFalse(out.succeeded)
    }

    func testTimeoutKillsTheWholeProcessTree() async throws {
        let pidFile = dir.appendingPathComponent("grandchild.pid").path
        let start = Date()
        let out = try await ProcessRunner.run(spec("/bin/sh", ["-c", "sleep 30 & echo $! > \"$1\"; wait", "sh", pidFile], timeout: 0.5))
        XCTAssertEqual(out.stopReason, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        let pid = pid_t(try String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        var alive = true
        for _ in 0..<50 {
            if kill(pid, 0) != 0 { alive = false; break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(alive, "grandchild in the process group was terminated")
    }

    func testCancellationStopsPromptly() async throws {
        let s = spec("/bin/sleep", ["30"], timeout: 60)
        let task = Task { try await ProcessRunner.run(s) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let start = Date()
        task.cancel()
        let out = try await task.value
        XCTAssertEqual(out.stopReason, .cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    func testOutputCapStopsRunawayOutput() async throws {
        let out = try await ProcessRunner.run(spec("/usr/bin/yes", [], timeout: 10, cap: 4096))
        XCTAssertEqual(out.stopReason, .outputLimit)
        XCTAssertLessThanOrEqual(out.stdout.count, 4096)
    }

    func testLineGuardCanAbort() async throws {
        let out = try await ProcessRunner.run(spec("/bin/sh", ["-c", "echo ok; echo TOOL_CALL; sleep 30"], timeout: 20)) { line in
            line == "TOOL_CALL" ? .abort("tool") : .proceed
        }
        XCTAssertEqual(out.stopReason, .aborted("tool"))
    }

    func testMissingExecutableThrows() async {
        do {
            _ = try await ProcessRunner.run(spec("/nonexistent/claude", []))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? ProcessRunError, .executableNotFound("/nonexistent/claude"))
        }
    }

    /// No silent API billing: inherited keys never reach a provider process.
    func testProviderEnvironmentDropsInheritedKeys() {
        let base = ["HOME": "/Users/a", "PATH": "/usr/bin", "ANTHROPIC_API_KEY": "sk-ant-x", "OPENAI_API_KEY": "sk-x",
                    "CODEX_API_KEY": "x", "CLAUDE_CODE_USE_BEDROCK": "1", "AWS_SECRET_ACCESS_KEY": "s",
                    "HTTPS_PROXY": "http://proxy:8080", "CODEX_HOME": "/Users/a/.codex", "RANDOM_SECRET": "z"]
        let env = ProviderEnvironment.make(base: base, executable: "/opt/homebrew/bin/claude",
                                           explicitPassthrough: ["ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN"])
        for k in ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "CODEX_API_KEY", "CLAUDE_CODE_USE_BEDROCK", "AWS_SECRET_ACCESS_KEY", "RANDOM_SECRET"] {
            XCTAssertNil(env[k], k)
        }
        XCTAssertEqual(env["HTTPS_PROXY"], "http://proxy:8080")
        XCTAssertEqual(env["CODEX_HOME"], "/Users/a/.codex")
        XCTAssertTrue(env["PATH"]!.hasPrefix("/opt/homebrew/bin:"))
    }
}
