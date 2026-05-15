import Foundation

struct ShellResult: Equatable, Sendable {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String
}

final class ShellClient {
    func run(
        _ executablePath: String,
        arguments: [String] = [],
        input: String? = nil,
        currentDirectory: URL? = nil
    ) async throws -> ShellResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let inputPipe = Pipe()
            if input != nil {
                process.standardInput = inputPipe
            }

            try process.run()

            if let input {
                inputPipe.fileHandleForWriting.write(Data(input.utf8))
                try? inputPipe.fileHandleForWriting.close()
            }

            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            return ShellResult(
                exitCode: process.terminationStatus,
                standardOutput: String(data: outputData, encoding: .utf8) ?? "",
                standardError: String(data: errorData, encoding: .utf8) ?? ""
            )
        }
        .value
    }
}
