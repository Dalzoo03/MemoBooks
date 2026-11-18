import Foundation

struct WatchLedgerDraft: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var amount: Int
    var memo: String
    var category: String
    var kind: TransactionKind
    var date: Date
    let createdAt: Date

    func validate() throws {
        try BackupCodec.validate([BackupRecord(id: id, amount: amount, category: category, memo: memo,
            date: date, createdAt: createdAt, isAiClassified: true, kind: kind)])
    }
}

struct WatchLedgerRequest: Codable, Sendable {
    enum Action: String, Codable, Sendable { case analyze, save }
    let action: Action
    let id: UUID
    let text: String
    let referenceDate: Date
    let draft: WatchLedgerDraft?

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 20_000 else { throw CocoaError(.coderInvalidValue) }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.text.count <= 500,
              (0...32_503_680_000).contains(value.referenceDate.timeIntervalSince1970) else { throw CocoaError(.coderInvalidValue) }
        if value.action == .save {
            guard let draft = value.draft, draft.id == value.id else { throw CocoaError(.coderInvalidValue) }
            try draft.validate()
        }
        return value
    }
}

struct WatchLedgerReply: Codable, Sendable {
    enum Status: String, Codable, Sendable { case preview, saved, failure }
    let status: Status
    let id: UUID
    let draft: WatchLedgerDraft?
    let message: String
}


@MainActor final class WatchRequestCompletion {
    private var finished = false
    private var completion: (() -> Void)?
    func install(_ completion: @escaping () -> Void) {
        if finished { completion() }
        else { self.completion = completion }
    }
    func finish() {
        guard !finished else { return }
        finished = true
        let action = completion
        completion = nil
        action?()
    }
}
