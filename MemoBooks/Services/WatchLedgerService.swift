import Foundation
import SwiftData

@MainActor enum WatchLedgerService {
    static func save(_ draft: WatchLedgerDraft, context: ModelContext) throws -> WatchLedgerDraft {
        try draft.validate()
        let id = draft.id
        var fetch = FetchDescriptor<Expense>(predicate: #Predicate { $0.recordID == id })
        fetch.fetchLimit = 1
        if let existing = try context.fetch(fetch).first {
            return WatchLedgerDraft(id: id, amount: existing.amount, memo: existing.memo, category: existing.category,
                kind: existing.kind, date: existing.date, createdAt: existing.createdAt)
        }
        let record = Expense(amount: draft.amount, category: draft.category, memo: draft.memo.trimmingCharacters(in: .whitespacesAndNewlines),
            date: draft.date, isAiClassified: true, kind: draft.kind, recordID: id, createdAt: draft.createdAt)
        context.insert(record)
        do { try context.save() }
        catch { context.delete(record); throw error }
        return draft
    }
}
