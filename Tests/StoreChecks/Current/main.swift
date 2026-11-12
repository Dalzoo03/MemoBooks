import Foundation
import SwiftData

@MainActor func verifyStore() throws {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let container = try ModelContainer(for: Expense.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
    let context = ModelContext(container)
    var checks = 0
    func check(_ value: Bool, _ title: String) { precondition(value, title); checks += 1 }
    let records = try context.fetch(FetchDescriptor<Expense>())
    check(records.count == 1, "migration preserves row count")
    let old = records[0]
    check(old.amount == 6500 && old.memo == "이전 버전 기록" && old.isAiClassified, "migration preserves original fields")
    check(old.kind == .expense, "missing kind defaults to expense")
    let first = try BackupService.snapshot(records, context: context)
    let second = try BackupService.snapshot(records, context: context)
    check(first[0].id == second[0].id, "legacy ID assignment persists")
    let income = Expense(amount: 100000, category: "용돈", memo: "복원 검증용 수입", date: .now, isAiClassified: false, kind: .income)
    context.insert(income); try context.save()
    let all = try context.fetch(FetchDescriptor<Expense>())
    let backup = try BackupCodec.decode(BackupCodec.encode(BackupService.snapshot(all, context: context)))
    context.delete(income); try context.save()
    let count = try BackupService.restore(backup, context: context)
    check(count == 1, "restore adds missing record")
    let again = try BackupService.restore(backup, context: context)
    check(again == 0, "second restore is idempotent")
    let restored = try context.fetch(FetchDescriptor<Expense>())
    check(restored.count == 2, "restore keeps existing record")
    check(restored.filter { $0.kind == .income }.first?.amount == 100000, "income survives restore")
    old.memo = "복원 후 기기에서 수정"; try context.save()
    _ = try BackupService.restore(backup, context: context)
    check(old.memo == "복원 후 기기에서 수정", "restore does not overwrite local edits")
    let bad = BackupRecord(id: UUID(), amount: -1, category: "기타", memo: "invalid", date: .now, createdAt: .now, isAiClassified: false, kind: .expense)
    do {
        _ = try BackupService.restore(LedgerBackup(version: 1, exportedAt: .now, records: [bad]), context: context)
        preconditionFailure("invalid backup should fail")
    } catch { checks += 1 }
    check(try context.fetchCount(FetchDescriptor<Expense>()) == 2, "invalid restore leaves store untouched")
    let reopened = ModelContext(container)
    let persisted = try reopened.fetch(FetchDescriptor<Expense>())
    check(persisted.count == 2 && persisted.contains { $0.memo == "복원 후 기기에서 수정" }, "changes persist into a fresh context")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let start = DraftValidation.date(from: "2026-11-01", timeZone: calendar.timeZone)!
    let next = DraftValidation.date(from: "2026-12-01", timeZone: calendar.timeZone)!
    let rows = [
        Expense(amount: 100, category: "기타", memo: "month start", date: start, isAiClassified: false),
        Expense(amount: 200, category: "기타", memo: "same day", date: start.addingTimeInterval(60), isAiClassified: false),
        Expense(amount: 999, category: "용돈", memo: "exclude income", date: start, isAiClassified: false, kind: .income),
        Expense(amount: 888, category: "기타", memo: "exclude previous", date: start.addingTimeInterval(-1), isAiClassified: false),
        Expense(amount: 777, category: "기타", memo: "exclude next", date: next, isAiClassified: false)
    ]
    let totals = ExpenseCalendar.expenseTotals(rows, month: start, calendar: calendar)
    check(totals == [start: 300], "day totals exclude income and records outside month")
    print("Passed \(checks) real SwiftData migration and restore checks")
}
try MainActor.assumeIsolated { try verifyStore() }
