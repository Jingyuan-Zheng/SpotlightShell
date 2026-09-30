import AppKit
import AppIntents

@main
@MainActor
final class SpotlightShellApp: NSObject, NSApplicationDelegate {
    private var aboutWindowObserver: NSObjectProtocol?

    static func main() {
        let app = NSApplication.shared
        let delegate = SpotlightShellApp()
        app.delegate = delegate
        NSAppleEventManager.shared().setEventHandler(
            delegate,
            andSelector: #selector(handleOpenApplication(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenApplication)
        )
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SpotlightShellShortcuts.updateAppShortcutParameters()
        AppLifetime.shared.launched()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentAboutPanel()
        return true
    }

    @objc private func handleOpenApplication(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        DispatchQueue.main.async { [weak self] in
            self?.presentAboutPanel()
        }
    }

    private func presentAboutPanel() {
        AppLifetime.shared.holdForAboutPanel()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: aboutCredits()])
        NSApp.activate(ignoringOtherApps: true)

        guard let aboutWindow = NSApp.keyWindow else { return }
        if let aboutWindowObserver {
            NotificationCenter.default.removeObserver(aboutWindowObserver)
        }
        aboutWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: aboutWindow,
            queue: .main
        ) { _ in
            NSApplication.shared.terminate(nil)
        }
    }

    private func aboutCredits() -> NSAttributedString {
        let isChinese = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true
        let websiteTitle = isChinese ? "个人网站" : "Personal Website"
        let repositoryTitle = isChinese ? "GitHub 仓库" : "GitHub Repository"
        let licenseTitle = isChinese ? "开源 · MIT 许可证" : "Open source · MIT License"
        let authorTitle = isChinese ? "作者：Jingyuan Zheng" : "Created by Jingyuan Zheng"
        let text = """
        \(authorTitle)

        \(websiteTitle)
        \(repositoryTitle)

        \(licenseTitle)
        """

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let credits = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .paragraphStyle: paragraphStyle
            ]
        )
        let content = credits.string as NSString
        credits.addAttribute(.link, value: URL(string: "https://jingyuan-zheng.github.io")!,
                             range: content.range(of: websiteTitle))
        let repository = URL(string: "https://github.com/Jingyuan-Zheng/SpotlightShell")!
        credits.addAttribute(.link, value: repository, range: content.range(of: repositoryTitle))
        credits.addAttribute(.link, value: repository, range: content.range(of: licenseTitle))
        return credits
    }
}
