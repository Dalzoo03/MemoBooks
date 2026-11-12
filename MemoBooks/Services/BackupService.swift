import Foundation
import SwiftData

@MainActor
enum BackupService {
    static func snapshot(_ records: [Expense], context: ModelContext) throws -> [BackupRecord] {
        // Older stores did not have a portable ID. Give each row an ID once and
        // persist before export, so importing the same backup remains idempotent.
        for record in records where record.recordID == nil { record.recordID = UUID() }
        try context.save()
        return records.map {
            BackupRecord(id: $0.recordID!, amount: $0.amount, category: $0.category, memo: $0.memo,
                         date: $0.date, createdAt: $0.createdAt, isAiClassified: $0.isAiClassified, kind: $0.kind)
        }
    }

    static func restore(_ backup: LedgerBackup, context: ModelContext) throws -> Int {
        try BackupCodec.validate(backup.records)
        let existing = try context.fetch(FetchDescriptor<Expense>())
        let ids = Set(existing.compactMap(\.recordID))
        let additions = backup.records.filter { !ids.contains($0.id) }
        // Full validation happens before touching the store. Restore appends only;
        // existing records, including locally edited versions, are retained.
        var inserted: [Expense] = []
        do {
            for record in additions {
                let item = Expense(amount: record.amount, category: record.category, memo: record.memo,
                                   date: record.date, isAiClassified: record.isAiClassified, kind: record.kind,
                                   recordID: record.id, createdAt: record.createdAt)
                context.insert(item)
                inserted.append(item)
            }
            try context.save()
            return inserted.count
        } catch {
            for item in inserted { context.delete(item) }
            throw error
        }
    }
}
