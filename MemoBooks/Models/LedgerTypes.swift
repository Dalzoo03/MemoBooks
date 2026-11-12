import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var title: String { self == .expense ? "지출" : "수입" }
}

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case food = "식비", cafe = "카페", transport = "교통", shopping = "쇼핑"
    case culture = "문화", medical = "의료", housing = "주거", other = "기타"
    case salary = "급여", allowance = "용돈", sideJob = "부수입", incomeOther = "기타 수입"
    var id: String { rawValue }
    var kind: TransactionKind {
        switch self {
        case .salary, .allowance, .sideJob, .incomeOther: .income
        default: .expense
        }
    }
    static func categories(for kind: TransactionKind) -> [Self] { allCases.filter { $0.kind == kind } }
    static func fallback(for kind: TransactionKind) -> Self { kind == .income ? .incomeOther : .other }
    var icon: String {
        switch self {
        case .food: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .transport: "bus.fill"
        case .shopping: "bag.fill"
        case .culture: "ticket.fill"
        case .medical: "cross.case.fill"
        case .housing: "house.fill"
        case .other: "ellipsis"
        case .salary: "briefcase.fill"
        case .allowance: "gift.fill"
        case .sideJob: "laptopcomputer"
        case .incomeOther: "arrow.down.left"
        }
    }
}

struct BackupRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let amount: Int
    let category: String
    let memo: String
    let date: Date
    let createdAt: Date
    let isAiClassified: Bool
    let kind: TransactionKind
}

struct LedgerBackup: Codable {
    let version: Int
    let exportedAt: Date
    let records: [BackupRecord]
}

enum BackupFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

enum BackupCodec {
    static let maximumBytes = 20 * 1024 * 1024
    static let maximumRecords = 50_000

    static func encode(_ records: [BackupRecord]) throws -> Data {
        try validate(records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(LedgerBackup(version: 1, exportedAt: .now, records: records))
        guard data.count <= maximumBytes else { throw BackupFailure.invalid("백업 크기가 20MB를 넘어요. CSV 내보내기로도 기록을 보관할 수 있어요") }
        return data
    }

    static func decode(_ data: Data) throws -> LedgerBackup {
        guard data.count <= maximumBytes else { throw BackupFailure.invalid("20MB 이하의 백업을 선택해 주세요") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: LedgerBackup
        do { backup = try decoder.decode(LedgerBackup.self, from: data) }
        catch { throw BackupFailure.invalid("메모가계부 JSON 백업 파일인지 확인해 주세요") }
        guard backup.version == 1 else { throw BackupFailure.invalid("지원하지 않는 백업 버전이에요") }
        try validate(backup.records)
        return backup
    }

    static func validate(_ records: [BackupRecord]) throws {
        guard records.count <= maximumRecords else { throw BackupFailure.invalid("백업은 최대 5만 건까지 지원해요") }
        var ids = Set<UUID>()
        for record in records {
            guard ids.insert(record.id).inserted else { throw BackupFailure.invalid("백업 안에 중복된 기록 ID가 있어요") }
            guard record.amount > 0, record.amount <= DraftValidation.maximumAmount,
                  !record.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.memo.count <= 500,
                  let category = ExpenseCategory(rawValue: record.category), category.kind == record.kind,
                  record.date.timeIntervalSince1970.isFinite,
                  (0...32_503_680_000).contains(record.date.timeIntervalSince1970),
                  (0...32_503_680_000).contains(record.createdAt.timeIntervalSince1970) else {
                throw BackupFailure.invalid("금액·메모·날짜 또는 분류가 올바르지 않은 기록이 있어요")
            }
        }
    }

    // Quoting alone does not prevent spreadsheet formula execution.
    static func csv(_ records: [BackupRecord]) -> String {
        func cell(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = ["=", "+", "-", "@"].contains(String(trimmed.prefix(1))) ? "'" + text : text
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows = records.map { r in
            [DraftValidation.dateText(r.date), r.kind.title, String(r.amount), r.category, r.memo,
             r.isAiClassified ? "AI" : "직접 입력"].map(cell).joined(separator: ",")
        }
        return "\u{FEFF}날짜,유형,금액(원),카테고리,메모,입력 방식\r\n" + rows.joined(separator: "\r\n")
    }
}
