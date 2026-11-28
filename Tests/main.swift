import Foundation

// Run on the Mac without a simulator or Apple Intelligence model.
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    checks += 1
}

check(DraftValidation.amount(from: "6,500") == 6500, "comma-separated KRW")
for invalid in ["", "0", "-1", "1.5", "6500원", "999999999999999999999999999", "１２３"] {
    check(DraftValidation.amount(from: invalid) == nil, "reject unsafe amount: \(invalid)")
}
let seoul = TimeZone(identifier: "Asia/Seoul")!
check(DraftValidation.date(from: "2026-02-30", timeZone: seoul) == nil, "invalid day")
check(DraftValidation.date(from: "2026-2-3", timeZone: seoul) == nil, "require exact format")
check(DraftValidation.date(from: "2026-10-15 extra", timeZone: seoul) == nil, "reject suffix")
let midnight = DraftValidation.date(from: "2026-10-15", timeZone: seoul)!
check(DraftValidation.dateText(midnight, timeZone: seoul) == "2026-10-15", "local day round trip")
check(DraftValidation.dateText(midnight, timeZone: TimeZone(secondsFromGMT: 0)!) == "2026-10-14", "time zone boundary")
check(DraftValidation.date(from: "2028-02-29", timeZone: seoul) != nil, "leap day")
print("Passed \(checks) validation checks")

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = seoul
calendar.firstWeekday = 1
let february = ExpenseCalendar.days(in: DraftValidation.date(from: "2028-02-15", timeZone: seoul)!, calendar: calendar)
check(february.compactMap { $0 }.count == 29, "calendar includes leap day")
check(february.count % 7 == 0, "calendar has whole weeks")
check(february.prefix(while: { $0 == nil }).count == 2, "Tuesday offset for Sunday-first week")
calendar.firstWeekday = 2
let mondayFirst = ExpenseCalendar.days(in: DraftValidation.date(from: "2028-02-15", timeZone: seoul)!, calendar: calendar)
check(mondayFirst.prefix(while: { $0 == nil }).count == 1, "Monday-first locale offset")
calendar.timeZone = TimeZone(identifier: "America/New_York")!
let march = ExpenseCalendar.days(in: DraftValidation.date(from: "2026-03-15", timeZone: calendar.timeZone)!, calendar: calendar).compactMap { $0 }
check(march.count == 31, "DST month day count")
check(march.allSatisfy { calendar.component(.hour, from: $0) == 0 }, "DST preserves local midnight")
let december = ExpenseCalendar.days(in: DraftValidation.date(from: "2026-12-01", timeZone: calendar.timeZone)!, calendar: calendar).compactMap { $0 }
check(december.count == 31 && calendar.component(.month, from: december.last!) == 12, "year-end stays within month")
print("Passed \(checks) total validation and calendar checks")

func rejects(_ label: String, _ action: () throws -> Void) {
    do { try action(); preconditionFailure("Expected rejection: \(label)") }
    catch { checks += 1 }
}
check(DraftValidation.amount(from: "1000000000000") == DraftValidation.maximumAmount, "upper amount boundary")
check(DraftValidation.amount(from: "1000000000001") == nil, "reject oversized amount")
check(ExpenseCategory.categories(for: .income).allSatisfy { $0.kind == .income }, "income categories separated")
check(ExpenseCategory.categories(for: .expense).count == 8, "original expense categories retained")
let sample = BackupRecord(id: UUID(), amount: 6500, category: "카페", memo: "커피, \"아이스\"\n두 잔",
                          date: midnight, createdAt: midnight, isAiClassified: true, kind: .expense)
let incomeRecord = BackupRecord(id: UUID(), amount: 100000, category: "용돈", memo: "용돈 받음",
                               date: midnight, createdAt: midnight, isAiClassified: false, kind: .income)
let encoded = try BackupCodec.encode([sample, incomeRecord])
let decoded = try BackupCodec.decode(encoded)
check(decoded.records == [sample, incomeRecord], "backup round trip preserves IDs, types and Korean text")
let emptyBackup = try BackupCodec.decode(BackupCodec.encode([]))
check(emptyBackup.records.isEmpty, "empty backup round trip")
rejects("duplicate UUID") { _ = try BackupCodec.encode([sample, sample]) }
rejects("unsupported version") {
    let invalid = String(data: encoded, encoding: .utf8)!.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
    _ = try BackupCodec.decode(Data(invalid.utf8))
}
rejects("oversized input") { _ = try BackupCodec.decode(Data(repeating: 0, count: BackupCodec.maximumBytes + 1)) }
rejects("malformed JSON") { _ = try BackupCodec.decode(Data("{}".utf8)) }
func record(amount: Int = 1, category: String = "기타", memo: String = "메모", date: Date = midnight,
            kind: TransactionKind = .expense) -> BackupRecord {
    BackupRecord(id: UUID(), amount: amount, category: category, memo: memo, date: date,
                 createdAt: midnight, isAiClassified: false, kind: kind)
}
rejects("negative amount") { _ = try BackupCodec.encode([record(amount: -1)]) }
rejects("zero amount") { _ = try BackupCodec.encode([record(amount: 0)]) }
rejects("huge amount") { _ = try BackupCodec.encode([record(amount: Int.max)]) }
rejects("blank memo") { _ = try BackupCodec.encode([record(memo: " \n ")]) }
rejects("long memo") { _ = try BackupCodec.encode([record(memo: String(repeating: "가", count: 501))]) }
rejects("unknown category") { _ = try BackupCodec.encode([record(category: "미정")]) }
rejects("income with expense category") { _ = try BackupCodec.encode([record(kind: .income)]) }
rejects("date out of range") { _ = try BackupCodec.encode([record(date: Date(timeIntervalSince1970: -1))]) }
rejects("too many records") { try BackupCodec.validate(Array(repeating: sample, count: 50_001)) }
let csv = BackupCodec.csv([sample, incomeRecord])
check(csv.hasPrefix("\u{FEFF}"), "CSV BOM for Korean spreadsheet compatibility")
check(csv.contains("\"커피, \"\"아이스\"\"\n두 잔\""), "CSV quotes, commas and embedded newlines")
for dangerous in ["=1+1", "+SUM(A1)", "-10", "@SUM(A1)", "  =1+1", "\t=1+1"] {
    check(BackupCodec.csv([record(memo: dangerous)]).contains("\"'" + dangerous), "CSV formula injection protection")
}
print("Passed \(checks) total validation, calendar and backup checks")
let largeBackup = (0..<14_000).map { _ in record(memo: String(repeating: "가", count: 500)) }
rejects("export refuses a backup that its importer cannot read") { _ = try BackupCodec.encode(largeBackup) }
print("Passed \(checks) total checks including backup size symmetry")

let watchSentAt = Date(timeIntervalSince1970: 1_790_000_000)
let voiceEditedAt = watchSentAt.addingTimeInterval(86400 * 2)
let watchReference = DraftValidation.entryReferenceDate(watchNoteID: "watch-note", timestamp: watchSentAt.timeIntervalSince1970, now: voiceEditedAt)
check(watchReference == watchSentAt, "voice edits preserve Watch note date reference")
check(DraftValidation.entryReferenceDate(watchNoteID: "", timestamp: watchSentAt.timeIntervalSince1970, now: voiceEditedAt) == voiceEditedAt, "new phone entries use current date")

let selectedCalendarDay = watchSentAt.addingTimeInterval(-86400)
check(DraftValidation.entryReferenceDate(watchNoteID: "", timestamp: watchSentAt.timeIntervalSince1970, selectedDate: selectedCalendarDay, now: voiceEditedAt) == selectedCalendarDay, "calendar entry uses selected day")
check(DraftValidation.entryReferenceDate(watchNoteID: "watch-note", timestamp: watchSentAt.timeIntervalSince1970, selectedDate: selectedCalendarDay, now: voiceEditedAt) == watchSentAt, "Watch origin takes priority over calendar selection")

print("Passed \(checks) checks including calendar and Watch draft reference preservation")
