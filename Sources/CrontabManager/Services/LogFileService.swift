import AppKit
import Foundation

enum LogFileService {
    static func clear(displayPath: String) throws {
        let resolvedPath = PathResolver.resolve(displayPath)

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw LogFileServiceError.fileNotFound(resolvedPath)
        }

        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: resolvedPath))
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
    }

    static func openExternally(displayPath: String) throws {
        let resolvedPath = PathResolver.resolve(displayPath)

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw LogFileServiceError.fileNotFound(resolvedPath)
        }

        let didOpen = NSWorkspace.shared.open(URL(fileURLWithPath: resolvedPath))
        guard didOpen else {
            throw LogFileServiceError.openFailed("macOS did not open \(resolvedPath)")
        }
    }
}

enum LogFileServiceError: LocalizedError {
    case fileNotFound(String)
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            return "Log file not found: \(path)"
        case let .openFailed(error):
            let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Could not open the log file." : "Could not open the log file: \(trimmed)"
        }
    }
}
