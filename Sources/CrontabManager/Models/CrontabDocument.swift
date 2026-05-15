import Foundation

enum CrontabLineKind: Equatable {
    case blank
    case comment
    case environment
    case job(CronJob)
    case other
}

struct CrontabLine: Identifiable, Equatable {
    let id: String
    var index: Int
    var raw: String
    var kind: CrontabLineKind
}

struct CrontabDocument: Equatable {
    var lines: [CrontabLine]

    static let empty = CrontabDocument(lines: [])

    var jobs: [CronJob] {
        lines.compactMap { line in
            guard case let .job(job) = line.kind else { return nil }
            return job
        }
    }

    static func parse(_ content: String) -> CrontabDocument {
        guard !content.isEmpty else { return .empty }

        var rawLines = content.components(separatedBy: .newlines)
        if content.hasSuffix("\n") {
            rawLines.removeLast()
        }

        let lines = rawLines.enumerated().map { index, rawLine in
            CrontabLine(
                id: "line-\(index)",
                index: index,
                raw: rawLine,
                kind: classify(rawLine, index: index)
            )
        }

        return CrontabDocument(lines: lines)
    }

    func renderedContent() -> String {
        guard !lines.isEmpty else { return "" }
        return lines.map(\.raw).joined(separator: "\n") + "\n"
    }

    mutating func setJobEnabled(jobID: CronJob.ID, enabled: Bool) throws {
        guard let index = lineIndex(for: jobID), case let .job(job) = lines[index].kind else {
            throw CrontabDocumentError.jobNotFound
        }

        let activeLine = job.activeLine
        lines[index].raw = enabled ? activeLine : DisabledLine.wrap(activeLine)
        reparse()
    }

    mutating func updateJob(jobID: CronJob.ID, draft: JobDraft) throws {
        guard let index = lineIndex(for: jobID), case let .job(job) = lines[index].kind else {
            throw CrontabDocumentError.jobNotFound
        }

        let schedule = try CronSchedule.normalizedExpression(from: draft.scheduleText)
        let command = draft.renderedCommand()
        guard !command.isEmpty else { throw CrontabDocumentError.emptyCommand }

        let activeLine = "\(schedule) \(command)"
        lines[index].raw = job.isEnabled ? activeLine : DisabledLine.wrap(activeLine)
        reparse()
    }

    mutating func addJob() {
        if let last = lines.last, !last.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(CrontabLine(id: "line-\(lines.count)", index: lines.count, raw: "", kind: .blank))
        }

        let logPath = "~/Library/Logs/crontab-manager.log"
        let activeLine = "0 * * * * /usr/bin/true >> \(logPath) 2>&1"
        lines.append(CrontabLine(
            id: "line-\(lines.count)",
            index: lines.count,
            raw: DisabledLine.wrap(activeLine),
            kind: .job(CronJob.parse(rawLine: DisabledLine.wrap(activeLine), lineIndex: lines.count)!)
        ))
        reparse()
    }

    mutating func removeJob(jobID: CronJob.ID) throws {
        guard let index = lineIndex(for: jobID) else {
            throw CrontabDocumentError.jobNotFound
        }
        lines.remove(at: index)
        reparse()
    }

    private mutating func reparse() {
        self = CrontabDocument.parse(renderedContent())
    }

    private func lineIndex(for jobID: CronJob.ID) -> Int? {
        lines.firstIndex { line in
            guard case let .job(job) = line.kind else { return false }
            return job.id == jobID
        }
    }

    private static func classify(_ rawLine: String, index: Int) -> CrontabLineKind {
        if rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .blank
        }

        if let job = CronJob.parse(rawLine: rawLine, lineIndex: index) {
            return .job(job)
        }

        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            return .comment
        }

        if isEnvironmentAssignment(trimmed) {
            return .environment
        }

        return .other
    }

    private static func isEnvironmentAssignment(_ line: String) -> Bool {
        guard let equalsIndex = line.firstIndex(of: "=") else { return false }
        let name = line[..<equalsIndex]
        guard let first = name.first, first == "_" || first.isLetter else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }
}

enum CrontabDocumentError: LocalizedError {
    case jobNotFound
    case emptyCommand

    var errorDescription: String? {
        switch self {
        case .jobNotFound:
            "That job is no longer in the current crontab."
        case .emptyCommand:
            "The command cannot be empty."
        }
    }
}
