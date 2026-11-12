import Foundation
import WatchConnectivity
import Combine

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
