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

    @Parameter(title: "Run Mode", default: .background)
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
            case .background:
                let result = try await BackgroundRunner.run(request)
                report = result.report
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
    case background
    case terminal

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Run Mode"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .background: "Background",
        .terminal: "Terminal"
    ]
}

struct SpotlightShellShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunShellCommandIntent(),
                    phrases: ["Run a shell command with \(.applicationName)"],
                    shortTitle: "Run Shell Command", systemImageName: "terminal")
    }
}
