import AppKit
import Carbon
import XCTest

final class ShellTests: XCTestCase {
    func testStreamsAndExitStatus() async throws {
        let request = try ShellRequest(command: "printf 'hello\\n'; printf 'problem\\n' >&2; exit 7", workingDirectory: nil)
        let result = try await BackgroundRunner.run(request)
        XCTAssertEqual(result.stdout, "hello\n")
        XCTAssertEqual(result.stderr, "problem\n")
        XCTAssertEqual(result.exitStatus, 7)
        XCTAssertTrue(result.report.contains("Exit status: 7"))
        XCTAssertTrue(result.report.contains("problem"))
    }

    func testWorkingDirectoryIsData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotlightShell-\(UUID()) space ' \" $ ` 中文\nline")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = try ShellRequest(command: "/bin/pwd -P", workingDirectory: directory.path)
        let result = try await BackgroundRunner.run(request)
        XCTAssertEqual(result.exitStatus, 0)
        let physicalPath = try XCTUnwrap(realpath(directory.path, nil))
        defer { free(physicalPath) }
        XCTAssertEqual(result.stdout, String(cString: physicalPath) + "\n")
    }

    func testClosedInputAndNoTTY() async throws {
        let request = try ShellRequest(command: "if read -r reply; then exit 8; fi; test ! -t 0 && test ! -t 1 && printf 'no tty\\n'", workingDirectory: nil)
        let result = try await BackgroundRunner.run(request)
        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertEqual(result.stdout, "no tty\n")
    }

    func testTimeoutStopsCommandIgnoringTERM() async throws {
        let request = try ShellRequest(command: "trap '' TERM; while true; do :; done", workingDirectory: nil)
        let start = Date()
        let result = try await BackgroundRunner.run(request, timeout: 0.4)
        XCTAssertTrue(result.timedOut)
        XCTAssertNotEqual(result.exitStatus, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testBothPipesDrainWithoutDeadlockAndAreBounded() async throws {
        let request = try ShellRequest(command: "for ((i=0;i<10000;i++)); do printf 'abcdefghij'; printf '0123456789' >&2; done", workingDirectory: nil)
        let result = try await BackgroundRunner.run(request)
        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertEqual(result.stdout.utf8.count, 65_536)
        XCTAssertEqual(result.stderr.utf8.count, 65_536)
        XCTAssertTrue(result.stdoutTruncated)
        XCTAssertTrue(result.stderrTruncated)
    }

    func testCancellation() async throws {
        let request = try ShellRequest(command: "/bin/sleep 10", workingDirectory: nil)
        let task = Task { try await BackgroundRunner.run(request) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
    }

    func testOrdinaryChildDoesNotSurviveShellExit() async throws {
        let request = try ShellRequest(command: "/bin/sleep 10 & print -r -- $!", workingDirectory: nil)
        let result = try await BackgroundRunner.run(request)
        let child = try XCTUnwrap(Int32(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
        // A killed orphan may briefly remain a zombie until launchd reaps it.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(kill(child, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testValidationAndTextPreservation() throws {
        XCTAssertThrowsError(try ShellRequest(command: " \n", workingDirectory: nil))
        XCTAssertThrowsError(try ShellRequest(command: "hello\0there", workingDirectory: nil))
        XCTAssertThrowsError(try ShellRequest(command: "pwd", workingDirectory: "relative"))
        XCTAssertThrowsError(try ShellRequest(command: "pwd", workingDirectory: "/bin/zsh"))
        XCTAssertThrowsError(try ShellRequest(command: "pwd", workingDirectory: "/nonexistent-\(UUID())"))
        let text = "  printf 'hello'  \n"
        XCTAssertEqual(try ShellRequest(command: text, workingDirectory: nil).command, text)
        XCTAssertEqual(try ShellRequest(command: "pwd", workingDirectory: "~").directory,
                       FileManager.default.homeDirectoryForCurrentUser)
    }

    func testEnvironmentFallbacksPreserveOrdering() {
        let environment = ShellRequest.loginEnvironment(["PATH": "/custom/bin:/usr/bin", "CUSTOM": "kept"])
        XCTAssertTrue(environment["PATH"]!.hasPrefix("/custom/bin:/usr/bin:"))
        XCTAssertTrue(environment["PATH"]!.contains("/opt/homebrew/bin"))
        XCTAssertEqual(environment["CUSTOM"], "kept")
        XCTAssertEqual(environment["SHELL"], "/bin/zsh")
    }

    func testLoginShell() async throws {
        let result = try await BackgroundRunner.run(ShellRequest(
            command: "[[ -o login ]] && printf '%s\\n' \"$SHELL\"", workingDirectory: nil))
        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertEqual(result.stdout, "/bin/zsh\n")
    }

    func testShellQuotingRoundTrip() async throws {
        let original = "spaces ' \" $HOME $(printf injected) `printf injected` \\ 中文\nend"
        let result = try await BackgroundRunner.run(ShellRequest(
            command: "printf '%s' \(ShellQuoting.quote(original))", workingDirectory: nil))
        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertEqual(result.stdout, original)
    }

    func testTerminalPayloadPreservesWholeCommandAndDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotlightShell-\(UUID()) ' $ ` 中文")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = try ShellRequest(command: "/bin/pwd -P; printf '%s\\n' 'literal $ ` \" 中文'; [[ -o interactive ]]", workingDirectory: directory.path)
        let payload = TerminalRunner.script(for: request)
        // Runs the identical payload through zsh without launching Terminal or requesting TCC.
        let result = try await BackgroundRunner.run(ShellRequest(command: payload, workingDirectory: nil))
        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertTrue(result.stdout.contains(directory.resolvingSymlinksInPath().path + "\n"))
        XCTAssertTrue(result.stdout.contains("literal $ ` \" 中文\n"))
    }

    func testFailedTerminalDirectoryDoesNotExecuteAnyUserCommand() async throws {
        let request = try ShellRequest(command: "printf forbidden; printf forbidden", workingDirectory: nil)
        let payload = TerminalRunner.script(for: request)
            .replacingOccurrences(of: ShellQuoting.quote(request.directory.path),
                                  with: ShellQuoting.quote("/nonexistent-\(UUID())"))
        let result = try await BackgroundRunner.run(ShellRequest(command: payload, workingDirectory: nil))
        XCTAssertNotEqual(result.exitStatus, 0)
        XCTAssertFalse(result.stdout.contains("forbidden"))
    }

    func testAppleEventStringRoundTrip() {
        let text = "' \" $ ` 中文\nline"
        XCTAssertEqual(NSAppleEventDescriptor(string: text).stringValue, text)
    }
}
