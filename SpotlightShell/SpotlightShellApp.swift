import AppKit
import AppIntents

@main
@MainActor
final class SpotlightShellApp: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = SpotlightShellApp()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SpotlightShellShortcuts.updateAppShortcutParameters()
        AppLifetime.shared.launched()
    }
}
