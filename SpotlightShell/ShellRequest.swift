import Foundation

struct ShellRequest: Sendable {
    let command: String
    let directory: URL

    init(command: String, workingDirectory: String?) throws {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShellError("Enter a shell command.")
        }
        guard !command.utf8.contains(0) else {
            throw ShellError("Commands cannot contain a NUL character.")
        }
        self.command = command // Validate without rewriting the user's text.
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let path = workingDirectory, !path.isEmpty {
            guard !path.utf8.contains(0) else {
                throw ShellError("The working directory cannot contain a NUL character.")
            }
            if path == "~" {
                directory = home
            } else if path.hasPrefix("~/") {
                directory = home.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true)
            } else if path.hasPrefix("/") {
                directory = URL(fileURLWithPath: path, isDirectory: true)
            } else {
                throw ShellError("Use an absolute working directory or a path beginning with ~/.")
            }
        } else {
            directory = home
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ShellError("The working directory does not exist or is not a folder.")
        }
    }

    static func loginEnvironment(_ inherited: [String: String] = ProcessInfo.processInfo.environment)
        -> [String: String] {
        var environment = inherited
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        environment["USER"] = NSUserName()
        environment["LOGNAME"] = NSUserName()
        environment["SHELL"] = "/bin/zsh"
        // Login startup files own PATH setup (including Homebrew). Preserve any
        // inherited PATH verbatim; only seed system tools when PATH is absent.
        if environment["PATH"] == nil {
            environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        }
        environment["TERM"] = "dumb"
        return environment
    }
}

struct ShellError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
