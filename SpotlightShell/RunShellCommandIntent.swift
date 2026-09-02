import AppIntents

struct RunShellCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Shell Command"
    static let description = IntentDescription(
        "Run a command in a login zsh. Background captures output for up to 20 seconds with no terminal or input. Choose Terminal for interactive or long-running commands.",
        categoryName: "Shell")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let isDiscoverable = true

    @Parameter(title: "Command",
               inputOptions: .init(capitalizationType: .none, multiline: true, autocorrect: false,
                                   smartQuotes: false, smartDashes: false),
               requestValueDialog: "What shell command would you like to run?")
    var command: String

    @Parameter(title: "Working Directory", description: "Absolute path or ~/ path. Defaults to your home folder.",
               inputOptions: .init(capitalizationType: .none, autocorrect: false, smartQuotes: false, smartDashes: false))
    var workingDirectory: String?

    @Parameter(title: "Run Mode", default: .auto)
    var runMode: ShellRunMode

    static var parameterSummary: some ParameterSummary {
        // Keep the required command inline in Spotlight. The optional directory
        // is intentionally omitted from the sentence so Spotlight does not
        // render it as an unresolved required-looking slot.
        Summary("Run \(\.$command) in \(\.$runMode)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        await AppLifetime.shared.begin()
        do {
            let request = try ShellRequest(command: command, workingDirectory: workingDirectory)
            let report: String
            let dialog: String
            switch runMode {
            case .auto:
                if ShellCommandRouting.prefersTerminal(command) {
                    try await TerminalRunner.run(request)
                    report = "Sent to Apple Terminal. Output and exit status are shown there."
                    dialog = report
                } else {
                    let result = try await BackgroundRunner.run(request)
                    report = result.dialog
                    dialog = result.dialog
                }
            case .background:
                let result = try await BackgroundRunner.run(request)
                report = result.dialog
                dialog = result.dialog
            case .terminal:
                try await TerminalRunner.run(request)
                report = "Sent to Apple Terminal. Output and exit status are shown there."
                dialog = report
            }
            await AppLifetime.shared.end()
            return .result(value: report, dialog: "\(dialog)")
        } catch {
            await AppLifetime.shared.end()
            throw error
        }
    }
}

enum ShellRunMode: String, AppEnum {
    case auto
    case background
    case terminal

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Run Mode"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .auto: "Auto",
        .background: "Background",
        .terminal: "Terminal"
    ]
}

enum ShellCommandRouting {
    static func prefersTerminal(_ command: String) -> Bool {
        let lower = command.lowercased()
        let interactive = ["ssh", "vim", "nvim", "nano", "top", "htop", "less", "man", "codex", "sudo", "read", "stty", "tput"]
        let persistent = ["tail -f", "watch ", "npm run dev", "yarn dev", "pnpm dev", "while true", "sleep infinity"]
        return interactive.contains { containsCommand(lower, $0) } || persistent.contains { lower.contains($0) }
    }

    private static func containsCommand(_ text: String, _ name: String) -> Bool {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == ";" || $0 == "|" }).contains { $0 == name }
    }
}

struct SpotlightShellShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunShellCommandIntent(),
                    phrases: ["Run a shell command with \(.applicationName)"],
                    shortTitle: "Run Shell Command", systemImageName: "terminal")
    }
}
