import Foundation

enum DraftValidation {
    static let maximumAmount = 1_000_000_000_000
    static func amount(from text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty,
              cleaned.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int(cleaned), value > 0, value <= maximumAmount else { return nil }
        return value
    }

    static func date(from text: String, timeZone: TimeZone = .current) -> Date? {
        let formatter = dateFormatter(timeZone: timeZone)
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else {
            return nil
        }
        return date
    }

    static func dateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        dateFormatter(timeZone: timeZone).string(from: date)
    }

    private static func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}

// Uses calendar-day arithmetic so leap years, time zones and DST remain correct.
enum ExpenseCalendar {
    static func days(in month: Date, calendar: Calendar = .current) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let offset = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        var cells = Array<Date?>(repeating: nil, count: offset)
        cells += range.map { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
        cells += Array<Date?>(repeating: nil, count: (7 - cells.count % 7) % 7)
        return cells
    }
}

// Money arithmetic and common relative dates are deterministic; AI handles the description and category.
enum InputHints {
    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func amount(in text: String) -> Int? {
        guard !["이체", "송금", "기억", "모르", "아마", "대략", "규칙", "프롬프트", "출력해"].contains(where: text.contains) else { return nil }
        let amounts = matches(#"(?<![\d.,])[-+]?(?:[0-9][0-9,]*(?:\.[0-9]+)?\s*(?:억|만|천)?\s*)+원"#, in: text)
        guard amounts.count == 1, let range = Range(amounts[0].range, in: text) else { return nil }
        let source = String(text[range])
        let prefix = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !source.hasPrefix("-"), !prefix.hasSuffix("-"), !prefix.hasSuffix("+") else { return nil }
        var remainder = String(text[..<range.lowerBound]) + String(text[range.upperBound...])
        for pattern in [#"[0-9]{4}[-년]\s*[0-9]{1,2}[-월]\s*[0-9]{1,2}일?"#, #"[0-9]{1,2}월\s*[0-9]{1,2}일"#, #"[0-9]{1,2}일"#] {
            remainder = remainder.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        // shortcut: other bare numbers (including quantities) require manual input until quantity parsing is supported.
        guard remainder.rangeOfCharacter(from: .decimalDigits) == nil else { return nil }
        let parts = matches(#"([0-9][0-9,]*(?:\.[0-9]+)?)\s*(억|만|천)?"#, in: source)
        var total = Decimal.zero
        var previousUnit = Int.max
        for part in parts {
            let token = (source as NSString).substring(with: part.range(at: 1))
            guard token.range(of: #"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
            let number = token.replacingOccurrences(of: ",", with: "")
            let unitText = part.range(at: 2).location == NSNotFound ? "" : (source as NSString).substring(with: part.range(at: 2))
            let unit = ["억": 100000000, "만": 10000, "천": 1000, "": 1][unitText]!
            guard unit < previousUnit, let value = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            previousUnit = unit
            total += value * Decimal(unit)
        }
        guard total > 0, total <= Decimal(DraftValidation.maximumAmount) else { return nil }
        let value = NSDecimalNumber(decimal: total).intValue
        return Decimal(value) == total ? value : nil
    }

    static func date(in text: String, today: Date, calendar: Calendar = .current) throws -> Date? {
        for pattern in [#"([0-9]{4})-([0-9]{2})-([0-9]{2})"#, #"([0-9]{4})년\s*([0-9]{1,2})월\s*([0-9]{1,2})일"#] {
            if let match = matches(pattern, in: text).first {
                let values = (1...3).map { Int((text as NSString).substring(with: match.range(at: $0)))! }
                guard let date = DraftValidation.date(from: String(format: "%04d-%02d-%02d", values[0], values[1], values[2]), timeZone: calendar.timeZone) else { throw CocoaError(.coderInvalidValue) }
                return date
            }
        }
        if let match = matches(#"지난달\s*([0-9]{1,2})일"#, in: text).first,
           let previous = calendar.date(byAdding: .month, value: -1, to: today) {
            let day = Int((text as NSString).substring(with: match.range(at: 1)))!
            let parts = calendar.dateComponents([.year, .month], from: previous)
            guard let date = DraftValidation.date(from: String(format: "%04d-%02d-%02d", parts.year!, parts.month!, day), timeZone: calendar.timeZone) else { throw CocoaError(.coderInvalidValue) }
            return date
        }
        for (word, offset) in [("그저께", -2), ("그제", -2), ("어제", -1), ("오늘", 0)] where text.contains(word) {
            return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))
        }
        return nil
    }
}
