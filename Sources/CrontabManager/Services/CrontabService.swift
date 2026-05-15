import Foundation

final class CrontabService {
    private let shell = ShellClient()

    func load() async throws -> CrontabDocument {
        let result = try await shell.run("/usr/bin/crontab", arguments: ["-l"])
        if result.exitCode == 0 {
            return CrontabDocument.parse(result.standardOutput)
        }

        if result.standardError.lowercased().contains("no crontab") {
            return .empty
        }

        throw CrontabServiceError.commandFailed("crontab -l", result.standardError)
    }

    func install(_ document: CrontabDocument) async throws {
        let result = try await shell.run(
            "/usr/bin/crontab",
            arguments: ["-"],
            input: document.renderedContent()
        )
        guard result.exitCode == 0 else {
            throw CrontabServiceError.commandFailed("crontab", result.standardError)
        }
    }

    func runNow(_ job: CronJob) async throws -> ManualRunResult {
        let command = try TerminalRunCommand.command(for: job)
        let appleScript = TerminalRunCommand.appleScript(forTerminalCommand: command)
        let result = try await shell.run(
            "/usr/bin/osascript",
            arguments: ["-e", appleScript]
        )

        guard result.exitCode == 0 else {
            throw CrontabServiceError.commandFailed("open Terminal", result.standardError)
        }

        return ManualRunResult(
            jobID: job.id,
            launchedAt: Date(),
            command: command
        )
    }
}

enum CrontabServiceError: LocalizedError {
    case commandFailed(String, String)
    case emptyManualRunCommand

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, error):
            let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "\(command) failed." : "\(command) failed: \(trimmed)"
        case .emptyManualRunCommand:
            return "The command is empty after removing cron log redirection."
        }
    }
}
