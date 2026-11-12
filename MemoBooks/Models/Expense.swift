import Foundation
import SwiftData

// The original entity name and fields stay unchanged. New optional fields allow
// existing pre-release stores to migrate without discarding a user's entries.
@Model
final class Expense {
    var amount: Int
    var category: String
    var memo: String
    var date: Date
    var createdAt: Date
    var isAiClassified: Bool
    var kindCode: String? = nil
    var recordID: UUID? = nil

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindCode ?? "expense") ?? .expense }
        set { kindCode = newValue.rawValue }
    }

    init(amount: Int, category: String, memo: String, date: Date, isAiClassified: Bool,
         kind: TransactionKind = .expense, recordID: UUID = UUID(), createdAt: Date = .now) {
        self.amount = amount
        self.category = category
        self.memo = memo
        self.date = date
        self.createdAt = createdAt
        self.isAiClassified = isAiClassified
        self.kindCode = kind.rawValue
        self.recordID = recordID
    }
}

extension ExpenseCalendar {
    static func expenseTotals(_ records: [Expense], month: Date, calendar: Calendar = .current) -> [Date: Int] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [:] }
        return records.reduce(into: [:]) { totals, record in
            guard record.kind == .expense, record.date >= interval.start, record.date < interval.end else { return }
            totals[calendar.startOfDay(for: record.date), default: 0] += record.amount
        }
    }
}
