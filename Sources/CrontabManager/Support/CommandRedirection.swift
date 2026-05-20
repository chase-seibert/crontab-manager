import Foundation

struct CommandRedirection: Equatable {
    var baseCommand: String
    var stdoutPath: String?
    var stderrPath: String?
    var stderrToStdout: Bool
    var pipedLogPaths: [String]

    init(
        baseCommand: String,
        stdoutPath: String?,
        stderrPath: String?,
        stderrToStdout: Bool,
        pipedLogPaths: [String] = []
    ) {
        self.baseCommand = baseCommand
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
        self.stderrToStdout = stderrToStdout
        self.pipedLogPaths = pipedLogPaths
    }

    var logPaths: [String] {
        var paths: [String] = []
        if let stdoutPath {
            paths.append(stdoutPath)
        }
        if !stderrToStdout, let stderrPath {
            paths.append(stderrPath)
        }
        paths.append(contentsOf: pipedLogPaths)
        return Array(NSOrderedSet(array: paths)) as? [String] ?? paths
    }

    static func parse(_ command: String) -> CommandRedirection {
        let tokens = ShellLexer.tokenize(command)
        guard !tokens.isEmpty else {
            return CommandRedirection(baseCommand: "", stdoutPath: nil, stderrPath: nil, stderrToStdout: false)
        }

        var stdoutPath: String?
        var stderrPath: String?
        var stderrToStdout = false
        var pipedLogPaths: [String] = []
        var removed = Set<Int>()
        var replacements: [Int: String] = [:]

        func markRemoved(_ index: Int, replacement: String = "") {
            removed.insert(index)
            if !replacement.isEmpty {
                replacements[index] = replacement
            }
        }

        for index in tokens.indices {
            guard !removed.contains(index) else { continue }
            let token = tokens[index].text
            let tokenParts = ShellSyntaxParts(token)

            if tokenParts.core == "tee" {
                pipedLogPaths.append(contentsOf: teeLogPaths(after: index, tokens: tokens))
                continue
            }

            if tokenParts.core == "2>&1" {
                if nextTokenCore(after: index, tokens: tokens) == "|" {
                    continue
                }

                stderrToStdout = true
                markRemoved(index, replacement: tokenParts.wrapperText)
                continue
            }

            if ["&>", "&>>"].contains(tokenParts.core), tokens.indices.contains(index + 1) {
                let targetParts = ShellSyntaxParts(tokens[index + 1].text)
                stdoutPath = targetParts.core
                stderrToStdout = true
                markRemoved(index, replacement: tokenParts.wrapperText)
                markRemoved(index + 1, replacement: targetParts.wrapperText)
                continue
            }

            if let target = attachedTarget(tokenParts.core, prefixes: ["&>>", "&>"]) {
                stdoutPath = target
                stderrToStdout = true
                markRemoved(index, replacement: tokenParts.wrapperText)
                continue
            }

            if [">", "1>", ">>", "1>>"].contains(tokenParts.core), tokens.indices.contains(index + 1) {
                let targetParts = ShellSyntaxParts(tokens[index + 1].text)
                stdoutPath = targetParts.core
                markRemoved(index, replacement: tokenParts.wrapperText)
                markRemoved(index + 1, replacement: targetParts.wrapperText)
                continue
            }

            if ["2>", "2>>"].contains(tokenParts.core), tokens.indices.contains(index + 1) {
                let targetParts = ShellSyntaxParts(tokens[index + 1].text)
                stderrPath = targetParts.core
                markRemoved(index, replacement: tokenParts.wrapperText)
                markRemoved(index + 1, replacement: targetParts.wrapperText)
                continue
            }

            if let target = attachedTarget(tokenParts.core, prefixes: ["1>>", "1>", ">>", ">"]) {
                stdoutPath = target
                markRemoved(index, replacement: tokenParts.wrapperText)
                continue
            }

            if let target = attachedTarget(tokenParts.core, prefixes: ["2>>", "2>"]) {
                if target == "&1" {
                    stderrToStdout = true
                } else {
                    stderrPath = target
                }
                markRemoved(index, replacement: tokenParts.wrapperText)
                continue
            }
        }

        let keptTokens = tokens.indices
            .compactMap { index -> String? in
                if let replacement = replacements[index] {
                    return replacement
                }
                if removed.contains(index) {
                    return nil
                }
                return String(command[tokens[index].range])
            }

        return CommandRedirection(
            baseCommand: normalizeWrapperSpacing(keptTokens.joined(separator: " ")),
            stdoutPath: stdoutPath,
            stderrPath: stderrPath,
            stderrToStdout: stderrToStdout,
            pipedLogPaths: pipedLogPaths
        )
    }

    func renderedCommand() -> String {
        var pieces = [baseCommand.trimmingCharacters(in: .whitespacesAndNewlines)]

        if let stdoutPath = stdoutPath?.nilIfBlank {
            pieces.append(">> \(ShellLexer.shellQuote(stdoutPath))")
            if stderrToStdout {
                pieces.append("2>&1")
            }
        }

        if !stderrToStdout, let stderrPath = stderrPath?.nilIfBlank {
            pieces.append("2>> \(ShellLexer.shellQuote(stderrPath))")
        }

        return pieces.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func attachedTarget(_ token: String, prefixes: [String]) -> String? {
        for prefix in prefixes where token.hasPrefix(prefix) && token.count > prefix.count {
            return String(token.dropFirst(prefix.count))
        }
        return nil
    }

    private static func teeLogPaths(after teeIndex: Int, tokens: [ShellToken]) -> [String] {
        var paths: [String] = []
        var index = teeIndex + 1

        while tokens.indices.contains(index) {
            let token = ShellSyntaxParts(tokens[index].text).core
            if ["|", "&&", "||", ";"].contains(token) {
                break
            }

            if token == "--" {
                index += 1
                continue
            }

            if token.hasPrefix("-") {
                index += teeOptionConsumesFollowingValue(token) ? 2 : 1
                continue
            }

            paths.append(token)
            index += 1
        }

        return paths
    }

    private static func teeOptionConsumesFollowingValue(_ token: String) -> Bool {
        let optionName = token.split(separator: "=", maxSplits: 1).first.map(String.init) ?? token
        guard optionName == "--output-error" else { return false }
        return !token.contains("=")
    }

    private static func nextTokenCore(after index: Int, tokens: [ShellToken]) -> String? {
        let nextIndex = index + 1
        guard tokens.indices.contains(nextIndex) else { return nil }
        return ShellSyntaxParts(tokens[nextIndex].text).core
    }

    private static func normalizeWrapperSpacing(_ command: String) -> String {
        var value = command.trimmingCharacters(in: .whitespacesAndNewlines)

        while value.contains("( ") || value.contains(" )") {
            value = value
                .replacingOccurrences(of: "( ", with: "(")
                .replacingOccurrences(of: " )", with: ")")
        }

        return value
    }
}

private struct ShellSyntaxParts {
    var leading = ""
    var core: String
    var trailing = ""

    var wrapperText: String {
        leading + trailing
    }

    init(_ token: String) {
        var value = token

        while value.first == "(" {
            leading.append("(")
            value.removeFirst()
        }

        while value.last == ")" {
            trailing.insert(")", at: trailing.startIndex)
            value.removeLast()
        }

        core = value
    }
}

struct ShellToken: Equatable {
    var text: String
    var range: Range<String.Index>
}

enum ShellLexer {
    static func tokenize(_ input: String) -> [ShellToken] {
        var tokens: [ShellToken] = []
        var start: String.Index?
        var buffer = ""
        var quote: Character?
        var index = input.startIndex

        func finishToken(upTo end: String.Index) {
            guard let tokenStart = start else { return }
            tokens.append(ShellToken(text: buffer, range: tokenStart..<end))
            start = nil
            buffer = ""
        }

        while index < input.endIndex {
            let character = input[index]

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                    index = input.index(after: index)
                    continue
                }

                if character == "\\", activeQuote == "\"", input.index(after: index) < input.endIndex {
                    let nextIndex = input.index(after: index)
                    buffer.append(input[nextIndex])
                    index = input.index(after: nextIndex)
                    continue
                }

                buffer.append(character)
                index = input.index(after: index)
                continue
            }

            if character == " " || character == "\t" || character == "\n" {
                finishToken(upTo: index)
                index = input.index(after: index)
                continue
            }

            if start == nil {
                start = index
            }

            if character == "'" || character == "\"" {
                quote = character
                index = input.index(after: index)
                continue
            }

            if character == "\\", input.index(after: index) < input.endIndex {
                let nextIndex = input.index(after: index)
                buffer.append(input[nextIndex])
                index = input.index(after: nextIndex)
                continue
            }

            buffer.append(character)
            index = input.index(after: index)
        }

        finishToken(upTo: input.endIndex)
        return tokens
    }

    static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-:+=,@%~")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
