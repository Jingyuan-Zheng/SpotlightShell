import AppKit

@MainActor
final class AppLifetime {
    static let shared = AppLifetime()
    private var activeRuns = 0
    private var idleTask: Task<Void, Never>?

    func launched() { scheduleExit(after: 15) }
    func holdForAboutPanel() {
        idleTask?.cancel()
        idleTask = nil
    }
    func begin() {
        idleTask?.cancel()
        idleTask = nil
        activeRuns += 1
    }
    func end() {
        activeRuns -= 1
        if activeRuns == 0 { scheduleExit(after: 5) }
    }
    private func scheduleExit(after seconds: UInt64) {
        idleTask?.cancel()
        idleTask = Task {
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) }
            catch { return }
            if activeRuns == 0 { NSApplication.shared.terminate(nil) }
        }
    }
}
