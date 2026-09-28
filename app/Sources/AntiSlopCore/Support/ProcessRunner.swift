import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A fully specified child process. Arguments are passed as an argv vector and
/// user content only ever travels on stdin: nothing is composed into a shell string.
public struct ProcessSpec: Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: String
    public var stdin: Data
    public var timeout: TimeInterval
    public var maxStdoutBytes: Int
    public var maxStderrBytes: Int

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String,
        stdin: Data = Data(),
        timeout: TimeInterval,
        maxStdoutBytes: Int = Limits.providerStdoutBytes,
        maxStderrBytes: Int = Limits.providerStderrBytes
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.stdin = stdin
        self.timeout = timeout
        self.maxStdoutBytes = maxStdoutBytes
        self.maxStderrBytes = maxStderrBytes
    }
}

public enum ProcessStopReason: Equatable, Sendable {
    case timedOut
    case cancelled
    case outputLimit
    /// A stream guard rejected the output (e.g. an unexpected tool call).
    case aborted(String)
}

public enum LineVerdict: Sendable {
    case proceed
    case abort(String)
}

public struct ProcessOutput: Sendable {
    public enum Termination: Equatable, Sendable {
        case exited(Int32)
        case signaled(Int32)
    }
    public let stdout: Data
    public let stderr: Data
    public let termination: Termination
    public let stopReason: ProcessStopReason?
    public let duration: TimeInterval

    public var succeeded: Bool { termination == .exited(0) && stopReason == nil }
    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public enum ProcessRunError: Error, Equatable, Sendable {
    case executableNotFound(String)
    case spawnFailed(Int32)
    case pipeFailed(Int32)
}

/// Runs one child in its own process group so cancellation, timeout and
/// output-limit stops terminate the whole tree (npm shims spawn native children).
public enum ProcessRunner {
    private static let ignoreSigpipe: Void = {
        // Writing to a child that exited early must fail with EPIPE, not kill the app.
        signal(SIGPIPE, SIG_IGN)
    }()

    public static func run(
        _ spec: ProcessSpec,
        onStdoutLine: (@Sendable (String) -> LineVerdict)? = nil
    ) async throws -> ProcessOutput {
        _ = ignoreSigpipe
        let child = try ChildProcess.spawn(spec)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ProcessOutput, Never>) in
                child.start(spec: spec, onStdoutLine: onStdoutLine) { output in
                    continuation.resume(returning: output)
                }
            }
        } onCancel: {
            child.stop(.cancelled)
        }
    }
}

final class ChildProcess: @unchecked Sendable {
    let pid: pid_t
    private let stdinFD: Int32
    private let stdoutFD: Int32
    private let stderrFD: Int32
    private let started = Date()
    private let lock = NSLock()
    private var stopReason: ProcessStopReason?
    private var reaped = false

    private init(pid: pid_t, stdinFD: Int32, stdoutFD: Int32, stderrFD: Int32) {
        self.pid = pid
        self.stdinFD = stdinFD
        self.stdoutFD = stdoutFD
        self.stderrFD = stderrFD
    }

    static func spawn(_ spec: ProcessSpec) throws -> ChildProcess {
        guard spec.executable.hasPrefix("/"), access(spec.executable, X_OK) == 0 else {
            throw ProcessRunError.executableNotFound(spec.executable)
        }
        let inPipe = try makePipe()
        let outPipe = try makePipe()
        let errPipe = try makePipe()

        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t? = nil
        var attr: posix_spawnattr_t? = nil
        #else
        var actions = posix_spawn_file_actions_t()
        var attr = posix_spawnattr_t()
        #endif
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attr)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attr)
        }
        // dup2 clears close-on-exec on 0/1/2; the originals close at exec.
        posix_spawn_file_actions_adddup2(&actions, inPipe.0, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe.1, 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe.1, 2)
        posix_spawn_file_actions_addchdir_np(&actions, spec.workingDirectory)

        var flags = Int32(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        #if canImport(Darwin)
        flags |= Int32(POSIX_SPAWN_CLOEXEC_DEFAULT)
        #endif
        posix_spawnattr_setflags(&attr, Int16(flags))
        posix_spawnattr_setpgroup(&attr, 0)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        sigaddset(&defaults, SIGTERM)
        sigaddset(&defaults, SIGINT)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attr, &mask)

        let argv: [UnsafeMutablePointer<CChar>?] = ([spec.executable] + spec.arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = spec.environment.sorted { $0.key < $1.key }
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, spec.executable, &actions, &attr, argv, envp)
        close(inPipe.0)
        close(outPipe.1)
        close(errPipe.1)
        guard rc == 0 else {
            [inPipe.1, outPipe.0, errPipe.0].forEach { close($0) }
            throw ProcessRunError.spawnFailed(rc)
        }
        return ChildProcess(pid: pid, stdinFD: inPipe.1, stdoutFD: outPipe.0, stderrFD: errPipe.0)
    }

    private static func makePipe() throws -> (Int32, Int32) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw ProcessRunError.pipeFailed(errno) }
        for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        return (fds[0], fds[1])
    }

    func start(
        spec: ProcessSpec,
        onStdoutLine: (@Sendable (String) -> LineVerdict)?,
        completion: @escaping @Sendable (ProcessOutput) -> Void
    ) {
        let group = DispatchGroup()
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let statusBox = StatusBox()

        let timeout = DispatchWorkItem { [weak self] in self?.stop(.timedOut) }
        DispatchQueue.global().asyncAfter(deadline: .now() + spec.timeout, execute: timeout)

        let input = spec.stdin
        let inFD = stdinFD
        DispatchQueue.global().async {
            input.withUnsafeBytes { raw in
                guard var p = raw.baseAddress else { return }
                var remaining = raw.count
                while remaining > 0 {
                    let n = write(inFD, p, remaining)
                    if n < 0 {
                        if errno == EINTR { continue }
                        break
                    }
                    remaining -= n
                    p = p.advanced(by: n)
                }
            }
            close(inFD)
        }

        group.enter()
        let outFD = stdoutFD
        DispatchQueue.global().async { [self] in
            var pending = Data()
            readAll(fd: outFD, box: stdoutBox, cap: spec.maxStdoutBytes) { chunk in
                guard let onStdoutLine else { return }
                pending.append(chunk)
                while let nl = pending.firstIndex(of: 0x0A) {
                    let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                    pending.removeSubrange(pending.startIndex...nl)
                    if case .abort(let why) = onStdoutLine(line) { self.stop(.aborted(why)) }
                }
            }
            if let onStdoutLine, !pending.isEmpty,
               case .abort(let why) = onStdoutLine(String(decoding: pending, as: UTF8.self)) {
                stop(.aborted(why))
            }
            close(outFD)
            group.leave()
        }

        group.enter()
        let errFD = stderrFD
        DispatchQueue.global().async { [self] in
            readAll(fd: errFD, box: stderrBox, cap: spec.maxStderrBytes, onChunk: nil)
            close(errFD)
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async { [self] in
            var st: Int32 = 0
            while waitpid(pid, &st, 0) < 0 && errno == EINTR {}
            lock.lock()
            // Clear any stragglers left in the child's group, then mark reaped so
            // later stop() calls never signal a recycled group.
            kill(-pid, SIGKILL)
            reaped = true
            lock.unlock()
            statusBox.value = st
            group.leave()
        }

        group.notify(queue: .global()) { [self] in
            timeout.cancel()
            lock.lock()
            let reason = stopReason
            lock.unlock()
            let status = statusBox.value
            let low = status & 0x7f
            let termination: ProcessOutput.Termination = low == 0 ? .exited((status >> 8) & 0xff) : .signaled(low)
            completion(ProcessOutput(
                stdout: stdoutBox.data,
                stderr: stderrBox.data,
                termination: termination,
                stopReason: reason,
                duration: Date().timeIntervalSince(started)
            ))
        }
    }

    private func readAll(fd: Int32, box: DataBox, cap: Int, onChunk: ((Data) -> Void)?) {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                return
            }
            if n == 0 { return }
            let chunk = Data(buffer[0..<n])
            if box.data.count + n > cap {
                stop(.outputLimit)
                continue // keep draining so the child is not blocked while it dies
            }
            box.data.append(chunk)
            onChunk?(chunk)
        }
    }

    /// First stop reason wins. SIGTERM the group, then SIGKILL after a grace period.
    func stop(_ reason: ProcessStopReason) {
        lock.lock()
        if stopReason == nil { stopReason = reason }
        if !reaped { kill(-pid, SIGTERM) }
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if !self.reaped { kill(-self.pid, SIGKILL) }
            self.lock.unlock()
        }
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

private final class StatusBox: @unchecked Sendable {
    var value: Int32 = 0
}

/// Minimal environment for provider runtimes. Inherited API keys, alternate
/// provider switches and unrelated secrets are never forwarded, so a runtime
/// cannot silently bill an API key found in the environment.
public enum ProviderEnvironment {
    static let passthrough: Set<String> = [
        "HOME", "USER", "LOGNAME", "SHELL", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR",
        "HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "NO_PROXY", "no_proxy", "ALL_PROXY", "all_proxy",
        "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS", "REQUESTS_CA_BUNDLE",
        // Provider-owned configuration/credential locations (paths, not secrets).
        "CODEX_HOME", "CLAUDE_CONFIG_DIR",
    ]

    /// Names that must never reach a provider child, even if requested.
    public static let forbidden: Set<String> = [
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL",
        "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY",
        "OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_BASE_URL", "AZURE_OPENAI_API_KEY",
        "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_PROFILE",
        "GOOGLE_APPLICATION_CREDENTIALS",
    ]

    public static func make(
        base: [String: String] = ProcessInfo.processInfo.environment,
        executable: String,
        extra: [String: String] = [:],
        explicitPassthrough: [String] = []
    ) -> [String: String] {
        var env: [String: String] = [:]
        for (k, v) in base where passthrough.contains(k) { env[k] = v }
        for k in explicitPassthrough where !forbidden.contains(k) {
            if let v = base[k] { env[k] = v }
        }
        let exeDir = (executable as NSString).deletingLastPathComponent
        let resolvedDir = ((executable as NSString).resolvingSymlinksInPath as NSString).deletingLastPathComponent
        var path: [String] = [exeDir, resolvedDir]
        path += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        if let home = base["HOME"] {
            path += ["\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin", "\(home)/.bun/bin"]
        }
        var seen = Set<String>()
        env["PATH"] = path.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        for (k, v) in extra where !forbidden.contains(k) { env[k] = v }
        return env
    }
}
