import XCTest
@testable import CrontabManager

final class CronParsingTests: XCTestCase {
    func testParsesEnabledAndDisabledJobsFromCrontab() throws {
        let document = CrontabDocument.parse("""
        SHELL=/bin/zsh
        0 9 * * 1-5 /usr/local/bin/report >> ~/Library/Logs/report.log 2>&1
        # */15 * * * * /usr/bin/uptime >> /tmp/uptime.log 2>&1
        # regular comment

        """)

        XCTAssertEqual(document.jobs.count, 2)
        XCTAssertTrue(document.jobs[0].isEnabled)
        XCTAssertFalse(document.jobs[1].isEnabled)
        XCTAssertEqual(document.jobs[0].scheduleDescription, "Weekdays at 09:00")
    }

    func testNormalizesFriendlySchedules() throws {
        XCTAssertEqual(try CronSchedule.normalizedExpression(from: "every 15 minutes"), "*/15 * * * *")
        XCTAssertEqual(try CronSchedule.normalizedExpression(from: "weekdays at 09:30"), "30 9 * * 1-5")
        XCTAssertEqual(try CronSchedule.normalizedExpression(from: "mondays at 6pm"), "0 18 * * 1")
        XCTAssertEqual(try CronSchedule.normalizedExpression(from: "@daily"), "@daily")
    }

    func testHumanDescriptionForCronNumberLists() throws {
        XCTAssertEqual(
            CronSchedule.humanDescription(for: "0 8,13,17 * * *"),
            "Daily at 08:00, 13:00, and 17:00"
        )

        XCTAssertEqual(
            CronSchedule.humanDescription(for: "0 8,13,17 * * 1-5"),
            "Weekdays at 08:00, 13:00, and 17:00"
        )
    }

    func testCommandRedirectionRoundTrip() throws {
        let parsed = CommandRedirection.parse("/usr/local/bin/job --flag >> '~/Library/Logs/job output.log' 2>&1")

        XCTAssertEqual(parsed.baseCommand, "/usr/local/bin/job --flag")
        XCTAssertEqual(parsed.stdoutPath, "~/Library/Logs/job output.log")
        XCTAssertTrue(parsed.stderrToStdout)
        XCTAssertEqual(parsed.logPaths, ["~/Library/Logs/job output.log"])
        XCTAssertEqual(parsed.renderedCommand(), "/usr/local/bin/job --flag >> '~/Library/Logs/job output.log' 2>&1")
    }

    func testCommandRedirectionInsideGroupedCommandKeepsGroupWrapper() throws {
        let parsed = CommandRedirection.parse("(cd /Users/example/projects/feed-tool && make run >> /tmp/feed.log 2>&1)")

        XCTAssertEqual(parsed.baseCommand, "(cd /Users/example/projects/feed-tool && make run)")
        XCTAssertEqual(parsed.stdoutPath, "/tmp/feed.log")
        XCTAssertTrue(parsed.stderrToStdout)
        XCTAssertNil(parsed.stderrPath)
    }

    func testJobTitlesUseUsefulExecutableNames() throws {
        XCTAssertEqual(
            JobTitleFormatter.title(for: "(cd /Users/example/projects/webpage-regex-to-rss && make run >> /tmp/cron.log 2>&1)"),
            "webpage-regex-to-rss"
        )

        XCTAssertEqual(
            JobTitleFormatter.title(for: "(cd /Users/example/projects/rsscombine && make run file=engineering-manager-blogs.env >> /tmp/cron.log 2>&1)"),
            "rsscombine engineering-manager-blogs"
        )

        XCTAssertEqual(
            JobTitleFormatter.title(for: "(cd /Users/example/projects/rsscombine && make run file=new-york-times.env >> /tmp/cron.log 2>&1)"),
            "rsscombine new-york-times"
        )

        XCTAssertEqual(
            JobTitleFormatter.title(for: "/usr/local/bin/python3 /Users/example/tools/email_trigger_watcher.py >> /tmp/watcher.log 2>&1"),
            "email_trigger_watcher.py"
        )

        XCTAssertEqual(
            JobTitleFormatter.title(for: "(cd /Users/example/projects/ics-combine && make combine-push >> /tmp/cron.log 2>&1)"),
            "ics-combine combine-push"
        )
    }

    func testTerminalRunCommandStripsCronLogRedirection() throws {
        let job = try XCTUnwrap(CronJob.parse(
            rawLine: "0 * * * * (cd /Users/example/projects/rsscombine && make run file=new-york-times.env >> /tmp/cron.log 2>&1)",
            lineIndex: 0
        ))

        let command = try TerminalRunCommand.command(for: job)

        XCTAssertEqual(command, "(cd /Users/example/projects/rsscombine && make run file=new-york-times.env)")
        XCTAssertFalse(command.contains("/tmp/cron.log"))
        XCTAssertFalse(command.contains("2>&1"))
        XCTAssertFalse(command.contains("printf"))
        XCTAssertFalse(command.contains("Command exited"))
    }

    func testLogAnalyzerReportsOneRecentErrorExcerpt() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("crontab-manager-error-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }

        let log = """
        starting job
        Traceback (most recent call last):
          File "/tmp/job.py", line 10, in <module>
            response = opener.open(url)
        urllib.error.HTTPError: HTTP Error 403: Forbidden
        make: *** [run] Error 1
        """
        try log.write(to: url, atomically: true, encoding: .utf8)

        let job = try XCTUnwrap(CronJob.parse(
            rawLine: "0 * * * * /usr/bin/python3 /tmp/job.py >> \(url.path) 2>&1",
            lineIndex: 0
        ))
        let status = LogAnalyzer().analyze(job: job)

        XCTAssertTrue(status.hasRecentError)
        XCTAssertNil(status.lastSuccessfulRun)
        XCTAssertEqual(status.recentErrorExcerpt?.filePath, url.path)
        XCTAssertTrue(status.recentErrorExcerpt?.text.contains("Traceback (most recent call last):") == true)
        XCTAssertTrue(status.recentErrorExcerpt?.text.contains("HTTP Error 403: Forbidden") == true)
    }

    func testLogFileServiceClearsLogFileInPlace() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("crontab-manager-clear-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }

        try "first line\nsecond line\n".write(to: url, atomically: true, encoding: .utf8)

        try LogFileService.clear(displayPath: url.path)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.size] as? NSNumber)?.uint64Value, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testDocumentMutationsRenderBackToCrontab() throws {
        var document = CrontabDocument.parse("0 * * * * /usr/bin/true >> /tmp/true.log 2>&1\n")
        let jobID = try XCTUnwrap(document.jobs.first?.id)

        try document.setJobEnabled(jobID: jobID, enabled: false)
        XCTAssertEqual(document.renderedContent(), "# 0 * * * * /usr/bin/true >> /tmp/true.log 2>&1\n")

        let commentedID = try XCTUnwrap(document.jobs.first?.id)
        try document.setJobEnabled(jobID: commentedID, enabled: true)
        XCTAssertEqual(document.renderedContent(), "0 * * * * /usr/bin/true >> /tmp/true.log 2>&1\n")

        try document.setJobEnabled(jobID: commentedID, enabled: false)

        let disabledID = try XCTUnwrap(document.jobs.first?.id)
        try document.updateJob(jobID: disabledID, draft: JobDraft(
            scheduleText: "daily at 09:00",
            commandText: "/usr/bin/date",
            stdoutLogPath: "/tmp/date.log",
            stderrLogPath: "",
            sendsStderrToStdout: true
        ))

        XCTAssertEqual(document.renderedContent(), "# 0 9 * * * /usr/bin/date >> /tmp/date.log 2>&1\n")
    }
}
