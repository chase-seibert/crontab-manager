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

        if let wrappedTokens = wrappedCommandTokens(tokens, commandName: commandName),
           let title = titleForExecutable(wrappedTokens, workingDirectory: workingDirectory) {
            return title
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
            if token.text == "&&" || token.text == ";" || token.text == "||" || token.text == "|" {
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

            if isShellSyntaxArgument(argument) {
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

            if isShellSyntaxArgument(argument) {
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

    private static func wrappedCommandTokens(_ tokens: [String], commandName: String) -> [String]? {
        switch commandName {
        case "flock":
            return flockCommandTokens(tokens)
        case "timeout", "gtimeout":
            return timeoutCommandTokens(tokens)
        case "nice", "ionice":
            return optionWrapperCommandTokens(tokens, valueOptions: ["-n", "--adjustment", "-c", "--class"])
        case "sudo", "doas":
            return sudoCommandTokens(tokens)
        case "run-one", "chronic", "cronic":
            return Array(tokens.dropFirst()).nilIfEmpty
        case "lockrun":
            return optionWrapperCommandTokens(tokens, valueOptions: ["--lockfile", "-l", "--retries", "-r", "--wait", "-w"])
        case "daemonize":
            return optionWrapperCommandTokens(tokens, valueOptions: ["-c", "-p", "-u", "-e", "-o", "-l"])
        case "envdir":
            guard tokens.count >= 3 else { return nil }
            return Array(tokens.dropFirst(2))
        case "s6-setuidgid":
            guard tokens.count >= 3 else { return nil }
            return Array(tokens.dropFirst(2))
        case "docker":
            return dockerCommandTokens(tokens)
        case "kubectl":
            return kubectlCommandTokens(tokens)
        default:
            return nil
        }
    }

    private static func flockCommandTokens(_ tokens: [String]) -> [String]? {
        var index = skipOptions(in: tokens, startingAt: 1, valueOptions: [
            "-E", "--conflict-exit-code",
            "-w", "-W", "--wait", "--timeout"
        ])
        guard tokens.indices.contains(index) else { return nil }

        index += 1
        guard tokens.indices.contains(index) else { return nil }
        return Array(tokens.dropFirst(index))
    }

    private static func timeoutCommandTokens(_ tokens: [String]) -> [String]? {
        var index = skipOptions(in: tokens, startingAt: 1, valueOptions: [
            "-k", "--kill-after",
            "-s", "--signal"
        ])
        guard tokens.indices.contains(index) else { return nil }

        index += 1
        guard tokens.indices.contains(index) else { return nil }
        return Array(tokens.dropFirst(index))
    }

    private static func sudoCommandTokens(_ tokens: [String]) -> [String]? {
        let index = skipOptions(in: tokens, startingAt: 1, valueOptions: [
            "-u", "--user",
            "-g", "--group",
            "-h", "--host",
            "-p", "--prompt",
            "-C", "--close-from",
            "-T", "--command-timeout",
            "-D", "--chdir",
            "-R", "--chroot",
            "-t", "--type",
            "-r", "--role"
        ])
        return stripEnvironmentPrefix(Array(tokens.dropFirst(index))).nilIfEmpty
    }

    private static func optionWrapperCommandTokens(_ tokens: [String], valueOptions: Set<String>) -> [String]? {
        let index = skipOptions(in: tokens, startingAt: 1, valueOptions: valueOptions)
        return Array(tokens.dropFirst(index)).nilIfEmpty
    }

    private static func dockerCommandTokens(_ tokens: [String]) -> [String]? {
        guard tokens.indices.contains(1) else { return nil }

        if tokens[1] == "exec" {
            var index = skipOptions(in: tokens, startingAt: 2, valueOptions: [
                "-e", "--env",
                "--env-file",
                "-u", "--user",
                "-w", "--workdir"
            ])
            guard tokens.indices.contains(index) else { return nil }

            index += 1
            return Array(tokens.dropFirst(index)).nilIfEmpty
        }

        if tokens[1] == "compose", let runIndex = tokens.firstIndex(of: "run") {
            var index = skipOptions(in: tokens, startingAt: runIndex + 1, valueOptions: [
                "-e", "--env",
                "--env-file",
                "-u", "--user",
                "-w", "--workdir",
                "--entrypoint",
                "--name",
                "-v", "--volume",
                "-l", "--label"
            ])
            guard tokens.indices.contains(index) else { return nil }

            index += 1
            return Array(tokens.dropFirst(index)).nilIfEmpty
        }

        return nil
    }

    private static func kubectlCommandTokens(_ tokens: [String]) -> [String]? {
        guard let execIndex = tokens.firstIndex(of: "exec") else { return nil }

        if let separatorIndex = tokens[execIndex...].firstIndex(of: "--") {
            return Array(tokens.dropFirst(separatorIndex + 1)).nilIfEmpty
        }

        var index = skipOptions(in: tokens, startingAt: execIndex + 1, valueOptions: [
            "-c", "--container",
            "-n", "--namespace",
            "--context",
            "--as"
        ])
        guard tokens.indices.contains(index) else { return nil }

        index += 1
        return Array(tokens.dropFirst(index)).nilIfEmpty
    }

    private static func skipOptions(in tokens: [String], startingAt startIndex: Int, valueOptions: Set<String>) -> Int {
        var index = startIndex

        while tokens.indices.contains(index) {
            let token = tokens[index]

            if token == "--" {
                index += 1
                break
            }

            guard token.hasPrefix("-"), token != "-" else {
                break
            }

            index += optionConsumesFollowingValue(token, valueOptions: valueOptions) ? 2 : 1
        }

        return index
    }

    private static func optionConsumesFollowingValue(_ token: String, valueOptions: Set<String>) -> Bool {
        let optionName = token.split(separator: "=", maxSplits: 1).first.map(String.init) ?? token
        guard valueOptions.contains(optionName) else { return false }
        if token.contains("=") { return false }
        if optionName.count == 2, token.count > 2 { return false }
        return true
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

    private static func isShellSyntaxArgument(_ token: String) -> Bool {
        token == "|" ||
            token == "&" ||
            token == "2>&1" ||
            token == "1>&2" ||
            token.hasPrefix(">") ||
            token.hasPrefix("1>") ||
            token.hasPrefix("2>")
    }
}

private extension Array {
    var nilIfEmpty: [Element]? {
        isEmpty ? nil : self
    }
}
