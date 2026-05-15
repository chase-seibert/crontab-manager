import Foundation

enum JobTitleFormatter {
    static func title(for command: String) -> String {
        let baseCommand = CommandRedirection.parse(command).baseCommand
        return title(forBaseCommand: baseCommand, workingDirectory: nil) ?? "(empty command)"
    }

    private static func title(forBaseCommand command: String, workingDirectory: String?) -> String? {
        let strippedCommand = stripOuterGrouping(command)
        let segments = commandSegments(from: strippedCommand)
        var currentDirectory = workingDirectory

        for segment in segments {
            let tokens = cleanedTokens(segment.map(\.text))
            guard !tokens.isEmpty else { continue }

            let commandName = executableName(tokens[0])
            if commandName == "cd", tokens.count >= 2 {
                currentDirectory = tokens[1]
                continue
            }

            if isSetupCommand(commandName) {
                continue
            }

            if commandName == "env" {
                let remaining = stripEnvironmentPrefix(Array(tokens.dropFirst()))
                if let nestedTitle = titleForExecutable(remaining, workingDirectory: currentDirectory) {
                    return nestedTitle
                }
                continue
            }

            if isShell(commandName), let nestedCommand = shellInlineCommand(from: tokens) {
                return title(forBaseCommand: nestedCommand, workingDirectory: currentDirectory)
            }

            if let title = titleForExecutable(tokens, workingDirectory: currentDirectory) {
                return title
            }
        }

        if let currentDirectory {
            return slug(currentDirectory, dropExtension: false)
        }

        return nil
    }

    private static func titleForExecutable(_ tokens: [String], workingDirectory: String?) -> String? {
        let tokens = stripEnvironmentPrefix(tokens)
        guard !tokens.isEmpty else { return nil }

        let commandName = executableName(tokens[0])

        if commandName == "env" {
            return titleForExecutable(Array(tokens.dropFirst()), workingDirectory: workingDirectory)
        }

        if isShell(commandName), let nestedCommand = shellInlineCommand(from: tokens) {
            return title(forBaseCommand: nestedCommand, workingDirectory: workingDirectory)
        }

        if commandName == "make" || commandName == "gmake" {
            return makeTitle(tokens: tokens, workingDirectory: workingDirectory)
        }

        if isInterpreter(commandName) {
            return interpreterTitle(tokens: tokens, interpreterName: commandName)
        }

        let baseName = executableName(tokens[0])
        let hints = argumentHints(Array(tokens.dropFirst()), limit: 2)
        return joinedTitle(baseName, hints: hints)
    }

    private static func makeTitle(tokens: [String], workingDirectory: String?) -> String {
        let projectName = workingDirectory.flatMap { slug($0, dropExtension: false) } ?? "make"
        var hints = makeArgumentHints(Array(tokens.dropFirst()))

        if hints.first == "run" {
            hints.removeFirst()
        }

        return joinedTitle(projectName, hints: Array(hints.prefix(2)))
    }

    private static func interpreterTitle(tokens: [String], interpreterName: String) -> String {
        var index = 1

        while index < tokens.count {
            let token = tokens[index]

            if token == "-m", tokens.indices.contains(index + 1) {
                return joinedTitle(tokens[index + 1], hints: argumentHints(Array(tokens.dropFirst(index + 2)), limit: 1))
            }

            if token == "-c" || token == "-e" {
                return interpreterName
            }

            if token.hasPrefix("-") {
                index += 1
                continue
            }

            let scriptName = executableName(token)
            let hints = argumentHints(Array(tokens.dropFirst(index + 1)), limit: 1)
            return joinedTitle(scriptName, hints: hints)
        }

        return interpreterName
    }

    private static func commandSegments(from command: String) -> [[ShellToken]] {
        var segments: [[ShellToken]] = [[]]

        for token in ShellLexer.tokenize(command) {
            if token.text == "&&" || token.text == ";" || token.text == "||" {
                if segments.last?.isEmpty == false {
                    segments.append([])
                }
            } else {
                segments[segments.count - 1].append(token)
            }
        }

        return segments.filter { !$0.isEmpty }
    }

    private static func stripEnvironmentPrefix(_ tokens: [String]) -> [String] {
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            if token.hasPrefix("-") {
                index += 1
                continue
            }

            if isEnvironmentAssignment(token) {
                index += 1
                continue
            }

            break
        }

        return Array(tokens.dropFirst(index))
    }

    private static func shellInlineCommand(from tokens: [String]) -> String? {
        for index in tokens.indices.dropFirst() where tokens[index].hasPrefix("-") && tokens[index].contains("c") {
            guard tokens.indices.contains(index + 1) else { return nil }
            return tokens[index + 1]
        }
        return nil
    }

    private static func makeArgumentHints(_ arguments: [String]) -> [String] {
        var hints: [String] = []
        var skipNext = false

        for argument in arguments {
            if skipNext {
                skipNext = false
                continue
            }

            if argument == "-C" || argument == "-f" || argument == "--file" || argument == "--directory" {
                skipNext = true
                continue
            }

            if argument.hasPrefix("-") {
                continue
            }

            if let equalsIndex = argument.firstIndex(of: "=") {
                let value = String(argument[argument.index(after: equalsIndex)...])
                if let hint = slug(value, dropExtension: true) {
                    hints.append(hint)
                }
                continue
            }

            if let hint = slug(argument, dropExtension: false) {
                hints.append(hint)
            }
        }

        return hints
    }

    private static func argumentHints(_ arguments: [String], limit: Int) -> [String] {
        var hints: [String] = []
        var skipNext = false

        for argument in arguments {
            guard hints.count < limit else { break }

            if skipNext {
                skipNext = false
                continue
            }

            if argument.hasPrefix("--") {
                if !argument.contains("=") {
                    skipNext = true
                }
                continue
            }

            if argument.hasPrefix("-") {
                if argument.count == 2 {
                    skipNext = true
                }
                continue
            }

            let value: String
            if let equalsIndex = argument.firstIndex(of: "=") {
                value = String(argument[argument.index(after: equalsIndex)...])
            } else {
                value = argument
            }

            if let hint = slug(value, dropExtension: true) {
                hints.append(hint)
            }
        }

        return hints
    }

    private static func joinedTitle(_ base: String, hints: [String]) -> String {
        ([base] + hints.filter { !$0.isEmpty && $0 != base }).joined(separator: " ")
    }

    private static func cleanedTokens(_ tokens: [String]) -> [String] {
        tokens.map { token in
            token.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        }
        .filter { !$0.isEmpty }
    }

    private static func executableName(_ token: String) -> String {
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        let lastPathComponent = (cleaned as NSString).lastPathComponent
        return lastPathComponent.isEmpty ? cleaned : lastPathComponent
    }

    private static func slug(_ value: String, dropExtension: Bool) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"'()"))
        candidate = (candidate as NSString).lastPathComponent

        if dropExtension {
            let path = candidate as NSString
            if !path.pathExtension.isEmpty {
                candidate = path.deletingPathExtension
            }
        }

        var scalars: [Character] = []
        var lastWasSeparator = false

        for character in candidate {
            if character.isLetter || character.isNumber || character == "_" || character == "-" || (!dropExtension && character == ".") {
                scalars.append(character)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                scalars.append("-")
                lastWasSeparator = true
            }
        }

        let slugged = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slugged.isEmpty ? nil : slugged
    }

    private static func stripOuterGrouping(_ command: String) -> String {
        var value = command.trimmingCharacters(in: .whitespacesAndNewlines)

        while value.first == "(", value.last == ")", wrapsWholeCommand(value) {
            value.removeFirst()
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value
    }

    private static func wrapsWholeCommand(_ value: String) -> Bool {
        var depth = 0
        var quote: Character?
        var index = value.startIndex

        while index < value.endIndex {
            let character = value[index]

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if character == "\\", activeQuote == "\"", value.index(after: index) < value.endIndex {
                    index = value.index(after: index)
                }
                index = value.index(after: index)
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0, value.index(after: index) != value.endIndex {
                    return false
                }
            }

            index = value.index(after: index)
        }

        return depth == 0
    }

    private static func isSetupCommand(_ name: String) -> Bool {
        name == "source" || name == "." || name == "export" || name == "set"
    }

    private static func isShell(_ name: String) -> Bool {
        name == "sh" || name == "bash" || name == "zsh"
    }

    private static func isInterpreter(_ name: String) -> Bool {
        if name.hasPrefix("python") { return true }
        return ["ruby", "node", "deno", "bun", "perl", "php", "swift"].contains(name)
    }

    private static func isEnvironmentAssignment(_ token: String) -> Bool {
        guard let equalsIndex = token.firstIndex(of: "=") else { return false }
        let name = token[..<equalsIndex]
        guard let first = name.first, first == "_" || first.isLetter else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }
}
