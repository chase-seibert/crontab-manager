import Foundation

struct JobDraft: Equatable {
    var scheduleText: String
    var commandText: String
    var stdoutLogPath: String
    var stderrLogPath: String
    var sendsStderrToStdout: Bool

    init(
        scheduleText: String,
        commandText: String,
        stdoutLogPath: String,
        stderrLogPath: String,
        sendsStderrToStdout: Bool
    ) {
        self.scheduleText = scheduleText
        self.commandText = commandText
        self.stdoutLogPath = stdoutLogPath
        self.stderrLogPath = stderrLogPath
        self.sendsStderrToStdout = sendsStderrToStdout
    }

    init() {
        scheduleText = "hourly"
        commandText = "/usr/bin/true"
        stdoutLogPath = "~/Library/Logs/crontab-manager.log"
        stderrLogPath = ""
        sendsStderrToStdout = true
    }

    init(job: CronJob) {
        scheduleText = CronSchedule.humanWritableText(for: job.scheduleExpression)
        let parsed = job.redirection
        commandText = parsed.baseCommand
        stdoutLogPath = parsed.stdoutPath ?? ""
        stderrLogPath = parsed.stderrPath ?? ""
        sendsStderrToStdout = parsed.stderrToStdout
    }

    func renderedCommand() -> String {
        CommandRedirection(
            baseCommand: commandText,
            stdoutPath: stdoutLogPath.nilIfBlank,
            stderrPath: stderrLogPath.nilIfBlank,
            stderrToStdout: sendsStderrToStdout
        )
        .renderedCommand()
    }
}
