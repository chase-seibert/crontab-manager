import Foundation

enum TerminalRunCommand {
    static func command(for job: CronJob) throws -> String {
        let baseCommand = CommandRedirection.parse(job.command)
            .baseCommand
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseCommand.isEmpty else {
            throw CrontabServiceError.emptyManualRunCommand
        }

        return baseCommand
    }

    static func appleScript(forTerminalCommand command: String) -> String {
        """
        tell application "Terminal"
            activate
            do script \(appleScriptString(command))
        end tell
        """
    }

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")

        return "\"\(escaped)\""
    }
}
