import Foundation
@preconcurrency import WatchConnectivity
import Combine
import SwiftData
import UIKit

struct WatchNote: Codable, Identifiable {
    let id: String
    let text: String
    let date: Date
}

@MainActor
final class WatchInbox: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchInbox()
    @Published private(set) var notes: [WatchNote] = []
    private let key = "watchNotesInbox"
    private var seen: Set<String>

    override init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: "watchNoteIDs") ?? [])
        super.init()
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([WatchNote].self, from: data) { notes = saved }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func remove(_ note: WatchNote) {
        notes.removeAll { $0.id == note.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(notes) { UserDefaults.standard.set(data, forKey: key) }
        UserDefaults.standard.set(Array(seen), forKey: "watchNoteIDs")
    }

    private func process(_ request: WatchLedgerRequest) async -> WatchLedgerReply {
        do {
            try Task.checkCancellation()
            if request.action == .analyze {
                let parsed = try await ExpenseParsingService().parse(request.text, today: request.referenceDate)
                guard let amount = parsed.draft.amount else { throw ParsingError.needsReview }
                let draft = WatchLedgerDraft(id: request.id, amount: amount, memo: parsed.draft.memo,
                    category: parsed.category.rawValue, kind: parsed.kind, date: parsed.date, createdAt: request.referenceDate)
                try draft.validate()
                return WatchLedgerReply(status: .preview, id: request.id, draft: draft, message: "금액·분류·날짜를 확인해 주세요")
            }
            guard let draft = request.draft else { throw CocoaError(.coderInvalidValue) }
            let saved = try WatchLedgerService.save(draft, context: ModelContext(try LedgerStore.open()))
            seen.insert(request.id.uuidString)
            notes.removeAll { $0.id == request.id.uuidString }
            persist()
            return WatchLedgerReply(status: .saved, id: request.id, draft: saved, message: "가계부에 저장했어요")
        } catch {
            return WatchLedgerReply(status: .failure, id: request.id, draft: nil,
                message: "처리하지 못했어요. \(error.localizedDescription) iPhone의 잠금을 풀고 다시 시도해 주세요.")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping @Sendable ([String: Any]) -> Void) {
        guard let data = message["ledgerRequest"] as? Data else { replyHandler(["error": "요청을 읽지 못했어요"]); return }
        Task { @MainActor in
            do {
                let request = try WatchLedgerRequest.decode(data)
                let work = Task { @MainActor in await self.process(request) }
                let lifetime = WatchRequestCompletion()
                let background = UIApplication.shared.beginBackgroundTask(withName: "Watch ledger") {
                    work.cancel()
                    lifetime.finish()
                }
                lifetime.install { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
                defer { lifetime.finish() }
                let result = await work.value
                replyHandler(["ledgerReply": try JSONEncoder().encode(result)])
            } catch { replyHandler(["error": "요청 형식이 올바르지 않아요"] ) }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let id = userInfo["id"] as? String,
              let text = userInfo["text"] as? String,
              let timestamp = userInfo["timestamp"] as? Double,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 500 else { return }
        Task { @MainActor in
            guard !self.seen.contains(id) else { return }
            self.seen.insert(id)
            self.notes.append(WatchNote(id: id, text: text, date: Date(timeIntervalSince1970: timestamp)))
            self.persist()
        }
    }
}
