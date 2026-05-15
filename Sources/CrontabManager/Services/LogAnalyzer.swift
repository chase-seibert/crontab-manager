import Foundation

final class LogAnalyzer {
    private let maximumTailBytes = 96_000

    func analyze(job: CronJob) -> JobStatus {
        let paths = job.logPaths
        guard !paths.isEmpty else {
            return JobStatus(
                lastSuccessfulRun: nil,
                recentErrorExcerpt: nil,
                logFiles: [],
                note: "No log redirection"
            )
        }

        let summaries = paths.map { summary(for: $0) }
        var detectedErrorExcerpt: LogErrorExcerpt?

        for summary in summaries.sorted(by: { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }) where summary.exists {
            let tail = (try? readTail(resolvedPath: summary.resolvedPath)) ?? ""
            if let excerpt = recentErrorExcerpt(in: tail, filePath: summary.displayPath) {
                detectedErrorExcerpt = excerpt
                break
            }
        }

        let newestLogWrite = summaries.compactMap(\.modifiedAt).max()
        let lastSuccessfulRun = detectedErrorExcerpt == nil ? newestLogWrite : nil

        return JobStatus(
            lastSuccessfulRun: lastSuccessfulRun,
            recentErrorExcerpt: detectedErrorExcerpt,
            logFiles: summaries,
            note: summaries.contains(where: { $0.exists }) ? nil : "Log file not found"
        )
    }

    func readTail(displayPath: String) throws -> String {
        try readTail(resolvedPath: PathResolver.resolve(displayPath))
    }

    private func readTail(resolvedPath: String) throws -> String {
        let url = URL(fileURLWithPath: resolvedPath)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let offset = size > UInt64(maximumTailBytes) ? size - UInt64(maximumTailBytes) : 0
        try handle.seek(toOffset: offset)

        let data = try handle.readToEnd() ?? Data()
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private func summary(for displayPath: String) -> LogFileSummary {
        let resolvedPath = PathResolver.resolve(displayPath)
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0

        return LogFileSummary(
            displayPath: displayPath,
            resolvedPath: resolvedPath,
            exists: attributes != nil,
            modifiedAt: attributes?[.modificationDate] as? Date,
            byteCount: size
        )
    }

    private func recentErrorExcerpt(in content: String, filePath: String) -> LogErrorExcerpt? {
        let lines = content.components(separatedBy: .newlines)
        let recentLines = Array(lines.suffix(120))
        let baseLineNumber = max(0, lines.count - recentLines.count)

        guard let errorOffset = recentLines.indices.last(where: { index in
            looksLikeError(recentLines[index].trimmingCharacters(in: .whitespacesAndNewlines))
        }) else {
            return nil
        }

        let tracebackOffset = recentLines[...errorOffset].indices.last { index in
            recentLines[index].localizedCaseInsensitiveContains("Traceback (most recent call last):")
        }

        let startOffset: Int
        if let tracebackOffset, errorOffset - tracebackOffset <= 40 {
            startOffset = tracebackOffset
        } else if let blankOffset = recentLines[..<errorOffset].indices.last(where: { recentLines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            startOffset = max(blankOffset + 1, errorOffset - 10)
        } else {
            startOffset = max(0, errorOffset - 10)
        }

        let endOffset = min(recentLines.count - 1, errorOffset + 6)
        let excerptLines = Array(recentLines[startOffset...endOffset])
            .drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .reversed()
            .drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .reversed()

        guard !excerptLines.isEmpty else { return nil }

        return LogErrorExcerpt(
            filePath: filePath,
            startLineNumber: baseLineNumber + startOffset + 1,
            lines: Array(excerptLines)
        )
    }

    private func looksLikeError(_ line: String) -> Bool {
        let lower = line.lowercased()
        let patterns = [
            "error",
            "exception",
            "traceback",
            "failed",
            "failure",
            "fatal",
            "panic",
            "permission denied",
            "not found",
            "command not found",
            "exit 1",
            "exited with 1"
        ]
        return patterns.contains { lower.contains($0) }
    }

}

enum PathResolver {
    static func resolve(_ path: String) -> String {
        var resolved = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = NSHomeDirectory()
        let user = NSUserName()

        if resolved == "~" {
            resolved = home
        } else if resolved.hasPrefix("~/") {
            resolved = home + resolved.dropFirst(1)
        }

        resolved = resolved
            .replacingOccurrences(of: "${HOME}", with: home)
            .replacingOccurrences(of: "$HOME", with: home)
            .replacingOccurrences(of: "${USER}", with: user)
            .replacingOccurrences(of: "$USER", with: user)

        if resolved.hasPrefix("/") {
            return resolved
        }

        return URL(fileURLWithPath: home).appendingPathComponent(resolved).path
    }
}
