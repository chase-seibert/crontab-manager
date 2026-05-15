import Foundation

struct CronSchedule {
    static let nicknameDescriptions: [String: String] = [
        "@reboot": "At reboot",
        "@hourly": "Hourly",
        "@daily": "Daily",
        "@midnight": "Daily",
        "@weekly": "Weekly",
        "@monthly": "Monthly",
        "@yearly": "Yearly",
        "@annually": "Yearly"
    ]

    static func splitScheduleAndCommand(_ line: String) -> (schedule: String, command: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("@") {
            let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { return nil }
            let nickname = parts[0].lowercased()
            guard nicknameDescriptions[nickname] != nil else { return nil }
            return (nickname, String(parts[1]).trimmingCharacters(in: .whitespaces))
        }

        let parts = trimmed.split(maxSplits: 5, whereSeparator: \.isWhitespace)
        guard parts.count == 6 else { return nil }

        let fields = parts.prefix(5).map(String.init)
        guard fields.allSatisfy(isCronField) else { return nil }

        return (
            fields.joined(separator: " "),
            String(parts[5]).trimmingCharacters(in: .whitespaces)
        )
    }

    static func normalizedExpression(from text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CronScheduleError.empty }

        if let schedule = splitScheduleAndCommand("\(trimmed) /usr/bin/true")?.schedule {
            return schedule
        }

        if let friendly = friendlyExpression(from: trimmed) {
            return friendly
        }

        throw CronScheduleError.invalid(trimmed)
    }

    static func humanWritableText(for expression: String) -> String {
        switch expression {
        case "@hourly": return "hourly"
        case "@daily", "@midnight": return "daily"
        case "@weekly": return "weekly"
        case "@monthly": return "monthly"
        case "@yearly", "@annually": return "yearly"
        case "@reboot": return "at reboot"
        default:
            let description = humanDescription(for: expression)
            if (try? normalizedExpression(from: description)) != nil {
                return description
            }
            return expression
        }
    }

    static func humanDescription(for expression: String) -> String {
        let normalized = expression.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let description = nicknameDescriptions[normalized] {
            return description
        }

        let fields = normalized.split(separator: " ").map(String.init)
        guard fields.count == 5 else { return expression }

        let minute = fields[0]
        let hour = fields[1]
        let dayOfMonth = fields[2]
        let month = fields[3]
        let dayOfWeek = fields[4]
        let minuteValues = cronNumberList(minute, range: 0...59)
        let hourValues = cronNumberList(hour, range: 0...23)

        if month == "*", dayOfMonth == "*", dayOfWeek == "*" {
            if minute.hasPrefix("*/"), hour == "*", let interval = Int(minute.dropFirst(2)) {
                return "Every \(interval) minutes"
            }

            if minute == "0", hour == "*" {
                return "Hourly"
            }

            if let interval = hourInterval(hour), let minuteValue = Int(minute) {
                return "Every \(interval) hours at :\(twoDigits(minuteValue))"
            }

            if let minuteValues, hour == "*", minuteValues.count > 1 {
                return "Every hour at \(formatMinuteMarks(minuteValues))"
            }

            if let minuteValues, let hourValues {
                return "Daily at \(formatTimes(hours: hourValues, minutes: minuteValues))"
            }
        }

        if month == "*", dayOfMonth == "*", let minuteValues, let hourValues {
            let times = formatTimes(hours: hourValues, minutes: minuteValues)

            switch dayOfWeek {
            case "1-5":
                return "Weekdays at \(times)"
            case "0,6", "6,0":
                return "Weekends at \(times)"
            default:
                if let dayName = weekdayName(dayOfWeek) {
                    return "\(dayName)s at \(times)"
                }
            }
        }

        if month == "*", dayOfWeek == "*", let minuteValues, let hourValues, let day = Int(dayOfMonth) {
            return "Monthly on day \(day) at \(formatTimes(hours: hourValues, minutes: minuteValues))"
        }

        return expression
    }

    private static func friendlyExpression(from text: String) -> String? {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch lower {
        case "hourly", "every hour":
            return "0 * * * *"
        case "daily", "every day":
            return "@daily"
        case "weekly":
            return "@weekly"
        case "monthly":
            return "@monthly"
        case "yearly", "annually":
            return "@yearly"
        case "at reboot", "reboot":
            return "@reboot"
        default:
            break
        }

        if let match = firstMatch(in: lower, pattern: #"^every\s+(\d+)\s+(minute|minutes|min|mins)$"#),
           let interval = Int(match[1]),
           (1...59).contains(interval) {
            return "*/\(interval) * * * *"
        }

        if let match = firstMatch(in: lower, pattern: #"^every\s+(\d+)\s+(hour|hours)$"#),
           let interval = Int(match[1]),
           (1...23).contains(interval) {
            return "0 */\(interval) * * *"
        }

        if let match = firstMatch(in: lower, pattern: #"^(daily|every day)\s+at\s+(.+)$"#),
           let time = parseTime(match[2]) {
            return "\(time.minute) \(time.hour) * * *"
        }

        if let match = firstMatch(in: lower, pattern: #"^weekdays\s+at\s+(.+)$"#),
           let time = parseTime(match[1]) {
            return "\(time.minute) \(time.hour) * * 1-5"
        }

        if let match = firstMatch(in: lower, pattern: #"^weekends\s+at\s+(.+)$"#),
           let time = parseTime(match[1]) {
            return "\(time.minute) \(time.hour) * * 0,6"
        }

        if let match = firstMatch(in: lower, pattern: #"^(every\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)s?\s+at\s+(.+)$"#),
           let day = weekdayNumber(match[2]),
           let time = parseTime(match[3]) {
            return "\(time.minute) \(time.hour) * * \(day)"
        }

        if let match = firstMatch(in: lower, pattern: #"^monthly\s+on\s+day\s+(\d{1,2})\s+at\s+(.+)$"#),
           let day = Int(match[1]),
           (1...31).contains(day),
           let time = parseTime(match[2]) {
            return "\(time.minute) \(time.hour) \(day) * *"
        }

        return nil
    }

    private static func isCronField(_ field: String) -> Bool {
        guard !field.isEmpty, !field.hasPrefix("#") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "*/,-?"))
        return field.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func hourInterval(_ field: String) -> Int? {
        guard field.hasPrefix("*/") else { return nil }
        return Int(field.dropFirst(2))
    }

    private static func cronNumberList(_ field: String, range: ClosedRange<Int>) -> [Int]? {
        let pieces = field.split(separator: ",", omittingEmptySubsequences: false)
        guard !pieces.isEmpty else { return nil }

        var values: Set<Int> = []
        for piece in pieces {
            guard let value = Int(piece), range.contains(value) else { return nil }
            values.insert(value)
        }

        return values.sorted()
    }

    private static func parseTime(_ rawValue: String) -> (hour: Int, minute: Int)? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = firstMatch(in: value, pattern: #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#) else {
            return nil
        }

        guard var hour = Int(match[1]) else { return nil }
        let minute = Int(match[2].isEmpty ? "0" : match[2]) ?? 0
        guard (0...59).contains(minute) else { return nil }

        let meridian = match[3]
        if meridian == "am" {
            if hour == 12 { hour = 0 }
        } else if meridian == "pm" {
            if hour < 12 { hour += 12 }
        }

        guard (0...23).contains(hour) else { return nil }
        return (hour, minute)
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }

        return (0..<match.numberOfRanges).map { index in
            let matchRange = match.range(at: index)
            guard let range = Range(matchRange, in: text) else { return "" }
            return String(text[range])
        }
    }

    private static func weekdayNumber(_ name: String) -> Int? {
        switch name {
        case "sunday": return 0
        case "monday": return 1
        case "tuesday": return 2
        case "wednesday": return 3
        case "thursday": return 4
        case "friday": return 5
        case "saturday": return 6
        default: return nil
        }
    }

    private static func weekdayName(_ field: String) -> String? {
        switch field.lowercased() {
        case "0", "7", "sun", "sunday": return "Sunday"
        case "1", "mon", "monday": return "Monday"
        case "2", "tue", "tuesday": return "Tuesday"
        case "3", "wed", "wednesday": return "Wednesday"
        case "4", "thu", "thursday": return "Thursday"
        case "5", "fri", "friday": return "Friday"
        case "6", "sat", "saturday": return "Saturday"
        default: return nil
        }
    }

    private static func formatTime(hour: Int, minute: Int) -> String {
        "\(twoDigits(hour)):\(twoDigits(minute))"
    }

    private static func formatTimes(hours: [Int], minutes: [Int]) -> String {
        let times = hours.flatMap { hour in
            minutes.map { minute in
                formatTime(hour: hour, minute: minute)
            }
        }

        return joinedList(times)
    }

    private static func formatMinuteMarks(_ minutes: [Int]) -> String {
        joinedList(minutes.map { ":\(twoDigits($0))" })
    }

    private static func joinedList(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return ""
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            return "\(values.dropLast().joined(separator: ", ")), and \(values.last ?? "")"
        }
    }

    private static func twoDigits(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

enum CronScheduleError: LocalizedError {
    case empty
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            "The schedule cannot be empty."
        case let .invalid(value):
            "“\(value)” is not a valid cron or supported human-readable schedule."
        }
    }
}
