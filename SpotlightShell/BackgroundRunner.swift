import Darwin
import Foundation
import Synchronization

/// A bounded child process, not a service. All blocking POSIX work stays off the main actor.
enum BackgroundRunner {
    // Explicit environment injection lets tests exercise real login startup with
    // an isolated HOME, without changing process-global environment or dotfiles.
    static func run(_ request: ShellRequest, timeout: TimeInterval = 20,
                    environment: [String: String] = ShellRequest.loginEnvironment()) async throws -> CommandResult {
        let cancelled = CancellationState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try execute(request, timeout: timeout, environment: environment, cancelled: cancelled)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancelled.value.withLock { $0 = true }
        }
    }

    private static func execute(_ request: ShellRequest, timeout: TimeInterval, environment: [String: String],
                                cancelled: CancellationState) throws -> CommandResult {
        if cancelled.value.withLock({ $0 }) { throw CancellationError() }
        let output = try OutputPipe()
        let errors = try OutputPipe()
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        try check(posix_spawn_file_actions_adddup2(&actions, output.writeFD, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, errors.writeFD, STDERR_FILENO))
        try check(posix_spawn_file_actions_addchdir(&actions, request.directory.path))
        // The child leads its own process group; never signal the app's process group.
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGINT, SIGTERM, SIGHUP, SIGPIPE, SIGQUIT] { sigaddset(&defaults, signal) }
        try check(posix_spawnattr_setsigmask(&attributes, &emptyMask))
        try check(posix_spawnattr_setsigdefault(&attributes, &defaults))
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP
            | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT)))

        // posix_spawn includes argv[0]. Foundation Process's equivalent would be
        // executableURL = /bin/zsh, arguments = ["-lc", request.command].
        // Keep command as one argument: no wrapper, escaping, -i, or explicit source.
        let arguments = CStringArray(["/bin/zsh", "-lc", request.command])
        let environment = CStringArray(environment.map { "\($0.key)=\($0.value)" })
        var pid: pid_t = 0
        let spawnStatus = arguments.withPointers { argv in
            environment.withPointers { envp in
                posix_spawn(&pid, "/bin/zsh", &actions, &attributes, argv, envp)
            }
        }
        try check(spawnStatus)
        output.closeWriter()
        errors.closeWriter()

        let deadline = ProcessInfo.processInfo.systemUptime + max(0.05, timeout)
        var timedOut = false
        var observedExit = false
        var observationError: Int32?
        while true {
            output.drain()
            errors.drain()
            var info = siginfo_t()
            // Keep the leader unreaped until group cleanup, preventing PID/group ID reuse.
            let status = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT)
            if status == 0 && info.si_pid == pid { observedExit = true; break }
            if status == -1 && errno != EINTR { observationError = errno; break }
            if cancelled.value.withLock({ $0 }) { break }
            if ProcessInfo.processInfo.systemUptime >= deadline { timedOut = true; break }
            var descriptors = [pollfd(fd: output.eof ? -1 : output.readFD, events: Int16(POLLIN), revents: 0),
                               pollfd(fd: errors.eof ? -1 : errors.readFD, events: Int16(POLLIN), revents: 0)]
            // After EOF, poll would otherwise spin on POLLHUP.
            if output.eof && errors.eof { usleep(20_000) }
            else { _ = poll(&descriptors, nfds_t(descriptors.count), 20) }
        }

        // Also clean up ordinary '&' descendants after their shell exits. Deliberately
        // detached sessions (setsid/daemonization) cannot be contained by process groups.
        if observationError == nil {
            _ = kill(-pid, SIGTERM)
            if !observedExit { _ = kill(pid, SIGTERM) }
            let graceEnd = ProcessInfo.processInfo.systemUptime + 0.2
            repeat {
                output.drain()
                errors.drain()
                usleep(10_000)
            } while ProcessInfo.processInfo.systemUptime < graceEnd
            _ = kill(-pid, SIGKILL)
            if !observedExit { _ = kill(pid, SIGKILL) }
        }
        var status: Int32 = 0
        var waited: pid_t
        repeat { waited = waitpid(pid, &status, 0) } while waited == -1 && errno == EINTR
        output.drain()
        errors.drain()
        if cancelled.value.withLock({ $0 }) { throw CancellationError() }
        if let observationError { throw ShellError("Could not observe shell completion: \(String(cString: strerror(observationError)))") }
        guard waited == pid else { throw ShellError("Could not collect the shell exit status.") }
        let signal = status & 0x7f
        let exitStatus = signal == 0 ? (status >> 8) & 0xff : 128 + signal
        return CommandResult(stdout: output.text, stderr: errors.text, exitStatus: exitStatus,
                             signal: signal == 0 ? nil : signal, timedOut: timedOut,
                             stdoutTruncated: output.truncated, stderrTruncated: errors.truncated)
    }

    private static func check(_ status: Int32) throws {
        guard status == 0 else {
            throw ShellError("Could not start the shell: \(String(cString: strerror(status)))")
        }
    }
}

private final class CancellationState: Sendable {
    let value = Mutex(false)
}

private final class OutputPipe {
    let readFD: Int32
    private(set) var writeFD: Int32
    private var bytes = Data()
    private(set) var truncated = false
    private(set) var eof = false
    private let limit = 65_536
    var text: String { String(decoding: bytes, as: UTF8.self) }

    init() throws {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw ShellError("Could not create output pipes.") }
        readFD = fds[0]
        writeFD = fds[1]
        guard fcntl(readFD, F_SETFL, O_NONBLOCK) != -1,
              fcntl(readFD, F_SETFD, FD_CLOEXEC) != -1,
              fcntl(writeFD, F_SETFD, FD_CLOEXEC) != -1 else {
            close(readFD); close(writeFD)
            throw ShellError("Could not configure output pipes.")
        }
    }

    func closeWriter() {
        if writeFD >= 0 { close(writeFD); writeFD = -1 }
    }

    func drain() {
        guard !eof else { return }
        var buffer = [UInt8](repeating: 0, count: 8_192)
        // A continuously writing command cannot starve timeout/cancellation checks.
        for _ in 0..<32 {
            let count = Darwin.read(readFD, &buffer, buffer.count)
            if count == 0 { eof = true; return }
            if count < 0 {
                if errno == EINTR { continue }
                return
            }
            let kept = min(count, limit - bytes.count)
            bytes.append(contentsOf: buffer.prefix(kept))
            if kept < count { truncated = true }
        }
    }

    deinit { close(readFD); closeWriter() }
}

private final class CStringArray {
    private let strings: [UnsafeMutablePointer<CChar>?]
    init(_ values: [String]) { strings = values.map { strdup($0) } + [nil] }
    func withPointers<T>(_ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> T) -> T {
        var pointers = strings
        return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    }
    deinit { strings.forEach { free($0) } }
}
