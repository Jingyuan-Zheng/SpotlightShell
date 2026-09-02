import Foundation

struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitStatus: Int32
    let signal: Int32?
    let timedOut: Bool
    let stdoutTruncated: Bool
    let stderrTruncated: Bool

    var report: String {
        var lines = ["Exit status: \(exitStatus)"]
        if let signal { lines.append("Terminated by signal: \(signal)") }
        if timedOut {
            lines.append("Background time limit reached. Use Terminal mode for interactive or long-running commands.")
        }
        if exitStatus != 0 {
            lines.append("Background has no terminal and stdin is closed. If input or a TTY is needed, choose Terminal.")
        }
        lines.append("stdout:\n\(stdout.isEmpty ? "(empty)" : stdout)")
        if stdoutTruncated { lines.append("[stdout truncated at 64 KiB]") }
        lines.append("stderr:\n\(stderr.isEmpty ? "(empty)" : stderr)")
        if stderrTruncated { lines.append("[stderr truncated at 64 KiB]") }
        return lines.joined(separator: "\n")
    }

    var dialog: String {
        let text: String
        if exitStatus == 0, !timedOut, stderr.isEmpty {
            // Match ordinary Terminal output for the common successful case.
            text = stdout
        } else {
            text = report
        }
        return text.count <= 3_000 ? text : String(text.prefix(3_000))
            + "\n[Display shortened; the action's Text result contains the captured report.]"
    }
}
