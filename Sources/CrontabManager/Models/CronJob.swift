import Foundation

struct CronJob: Identifiable, Equatable {
    let id: String
    let lineIndex: Int
    var isEnabled: Bool
    var scheduleExpression: String
    var command: String
    var rawLine: String

    var activeLine: String {
        "\(scheduleExpression) \(command)"
    }

    var redirection: CommandRedirection {
        CommandRedirection.parse(command)
    }

    var title: String {
        JobTitleFormatter.title(for: command)
    }

    var scheduleDescription: String {
        CronSchedule.humanDescription(for: scheduleExpression)
    }

    var logPaths: [String] {
        redirection.logPaths
    }

    static func parse(rawLine: String, lineIndex: Int) -> CronJob? {
        let disabledCandidate = DisabledLine.unwrap(rawLine)
        let isEnabled = disabledCandidate == nil
        let candidate = (disabledCandidate ?? rawLine).trimmingCharacters(in: .whitespaces)

        guard !candidate.isEmpty else { return nil }
        guard let parsed = CronSchedule.splitScheduleAndCommand(candidate) else { return nil }

        return CronJob(
            id: "line-\(lineIndex)",
            lineIndex: lineIndex,
            isEnabled: isEnabled,
            scheduleExpression: parsed.schedule,
            command: parsed.command,
            rawLine: rawLine
        )
    }
}

enum DisabledLine {
    static func unwrap(_ rawLine: String) -> String? {
        let trimmedLeading = rawLine.drop { $0 == " " || $0 == "\t" }
        guard trimmedLeading.first == "#" else { return nil }
        let afterHash = trimmedLeading.dropFirst().drop { $0 == " " || $0 == "\t" }
        let candidate = String(afterHash)
        return CronSchedule.splitScheduleAndCommand(candidate) == nil ? nil : candidate
    }

    static func wrap(_ activeLine: String) -> String {
        "# \(activeLine)"
    }
}
