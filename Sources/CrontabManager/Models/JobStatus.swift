import Foundation

struct JobStatus: Equatable {
    var lastSuccessfulRun: Date?
    var recentErrorExcerpt: LogErrorExcerpt?
    var logFiles: [LogFileSummary]
    var note: String?

    static let empty = JobStatus(
        lastSuccessfulRun: nil,
        recentErrorExcerpt: nil,
        logFiles: [],
        note: nil
    )

    var hasRecentError: Bool {
        recentErrorExcerpt != nil
    }
}

struct LogErrorExcerpt: Identifiable, Equatable {
    var id: String { "\(filePath)-\(startLineNumber)-\(lines.joined(separator: "|"))" }
    var filePath: String
    var startLineNumber: Int
    var lines: [String]

    var text: String {
        lines.joined(separator: "\n")
    }
}

struct LogFileSummary: Identifiable, Equatable {
    var id: String { resolvedPath }
    var displayPath: String
    var resolvedPath: String
    var exists: Bool
    var modifiedAt: Date?
    var byteCount: UInt64
}

struct ManualRunResult: Identifiable, Equatable {
    var id: String { jobID }
    var jobID: CronJob.ID
    var launchedAt: Date
    var command: String
}
