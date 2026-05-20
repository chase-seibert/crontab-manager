import Foundation
import XCTest
@testable import CrontabManager

final class CrontabCorpusTests: XCTestCase {
    func testGenericCrontabCorpusExpectations() throws {
        let cases = try loadCorpusCases()

        XCTAssertEqual(cases.count, 1_000)

        var strictPassCount = 0
        var trackedGapCount = 0

        for fixtureCase in cases {
            let actual = try parseActualResult(for: fixtureCase)
            let mismatches = fixtureCase.expected.mismatches(with: actual)

            switch fixtureCase.expected.status {
            case "✅":
                strictPassCount += 1
                if !mismatches.isEmpty {
                    XCTFail(fixtureCase.failureMessage(mismatches: mismatches, actual: actual))
                }
            case "❌":
                trackedGapCount += 1
                if mismatches.isEmpty {
                    XCTFail("""
                    Line \(fixtureCase.lineNumber) is marked ❌ but now passes. Change its status to ✅.
                    \(fixtureCase.cronLine)
                    """)
                }
            default:
                XCTFail("Line \(fixtureCase.lineNumber) has unsupported status \(fixtureCase.expected.status).")
            }
        }

        print("Crontab corpus: ✅ \(strictPassCount) strict rows, ❌ \(trackedGapCount) tracked parser gaps")
    }

    func testGenericCrontabCorpusDoesNotContainLocalUserData() throws {
        let contents = try String(contentsOf: corpusURL, encoding: .utf8)

        XCTAssertFalse(contents.contains("/Users/cseibert"))
        XCTAssertFalse(contents.localizedCaseInsensitiveContains("cseibert"))
    }

    private var corpusURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/generic-crontab-1000.cron")
    }

    private func loadCorpusCases() throws -> [CorpusCase] {
        let contents = try String(contentsOf: corpusURL, encoding: .utf8)
        var rows = contents.components(separatedBy: .newlines)
        if rows.last == "" {
            rows.removeLast()
        }

        return try rows.enumerated().map { index, row in
            try CorpusCase(lineNumber: index + 1, rawLine: row)
        }
    }

    private func parseActualResult(for fixtureCase: CorpusCase) throws -> CorpusExpectation {
        let job = try XCTUnwrap(
            CronJob.parse(rawLine: fixtureCase.cronLine, lineIndex: fixtureCase.lineNumber - 1),
            "Line \(fixtureCase.lineNumber) did not parse as a cron job: \(fixtureCase.cronLine)"
        )
        let redirection = CommandRedirection.parse(job.command)

        return CorpusExpectation(
            status: fixtureCase.expected.status,
            name: job.title,
            command: redirection.baseCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            logfiles: job.logPaths
        )
    }
}

private struct CorpusCase {
    let lineNumber: Int
    let rawLine: String
    let cronLine: String
    let expected: CorpusExpectation

    init(lineNumber: Int, rawLine: String) throws {
        let marker = " # EXPECT "
        guard let markerRange = rawLine.range(of: marker, options: .backwards) else {
            throw CorpusCaseError.missingExpectation(lineNumber)
        }

        self.lineNumber = lineNumber
        self.rawLine = rawLine
        self.cronLine = String(rawLine[..<markerRange.lowerBound])

        let json = String(rawLine[markerRange.upperBound...])
        let data = Data(json.utf8)
        self.expected = try JSONDecoder().decode(CorpusExpectation.self, from: data)
    }

    func failureMessage(mismatches: [String], actual: CorpusExpectation) -> String {
        """
        Line \(lineNumber) did not match expected parser output:
        \(mismatches.joined(separator: "\n"))
        cron: \(cronLine)
        actual: name=\(actual.name), command=\(actual.command), logfiles=\(actual.logfiles)
        expected: name=\(expected.name), command=\(expected.command), logfiles=\(expected.logfiles)
        """
    }
}

private struct CorpusExpectation: Codable, Equatable {
    let status: String
    let name: String
    let command: String
    let logfiles: [String]

    func mismatches(with actual: CorpusExpectation) -> [String] {
        var mismatches: [String] = []

        if name != actual.name {
            mismatches.append("- name expected \(name), got \(actual.name)")
        }

        if command != actual.command {
            mismatches.append("- command expected \(command), got \(actual.command)")
        }

        if logfiles != actual.logfiles {
            mismatches.append("- logfiles expected \(logfiles), got \(actual.logfiles)")
        }

        return mismatches
    }
}

private enum CorpusCaseError: LocalizedError {
    case missingExpectation(Int)

    var errorDescription: String? {
        switch self {
        case let .missingExpectation(lineNumber):
            return "Line \(lineNumber) is missing trailing EXPECT metadata."
        }
    }
}
