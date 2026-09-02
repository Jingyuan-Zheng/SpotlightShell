import AppKit
import Carbon

/// A single-quoted POSIX word; shell syntax inside the value stays literal.
enum ShellQuoting {
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum TerminalRunner {
    static func script(for request: ShellRequest) -> String {
        // Only the outer command uses Terminal's configured shell (normally zsh).
        // The complete user command is one argument to an interactive login zsh.
        "cd -- \(ShellQuoting.quote(request.directory.path)) && /bin/zsh -lic \(ShellQuoting.quote(request.command))"
    }

    @MainActor
    static func run(_ request: ShellRequest) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw ShellError("Apple Terminal.app could not be found.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let terminal = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        let pid = terminal.processIdentifier
        let text = script(for: request)
        // Construct the event in the worker; no untrusted text becomes AppleScript source.
        try await Task.detached(priority: .userInitiated) {
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite),
                                              eventID: AEEventID(0x646f7363), // 'dosc', Terminal.sdef
                                              targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                              returnID: AEReturnID(kAutoGenerateReturnID),
                                              transactionID: AETransactionID(kAnyTransactionID))
            event.setParam(NSAppleEventDescriptor(string: text), forKeyword: AEKeyword(keyDirectObject))
            do {
                let reply = try event.sendEvent(options: [.waitForReply, .canInteract, .dontRecord], timeout: 10)
                if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), error.int32Value != 0 {
                    throw ShellError("Terminal returned Apple Event error \(error.int32Value).")
                }
            } catch {
                let code = (error as NSError).code
                if code == -1743 {
                    throw ShellError("Terminal control was denied. Allow SpotlightShell → Terminal in System Settings → Privacy & Security → Automation, then try again.")
                }
                if code == -1712 {
                    throw ShellError("Terminal did not reply in time. Check its window before retrying: the command may already have started.")
                }
                throw ShellError("Could not send the command to Terminal: \(error.localizedDescription)")
            }
        }.value
        terminal.activate(options: [])
    }
}
