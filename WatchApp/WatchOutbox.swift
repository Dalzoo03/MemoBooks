import Foundation

struct OutgoingWatchNote: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let date: Date
    var failed = false
}

struct WatchOutbox {
    private(set) var notes: [OutgoingWatchNote]
    private let url: URL

    init(url: URL) throws {
        self.url = url
        do { notes = try JSONDecoder().decode([OutgoingWatchNote].self, from: Data(contentsOf: url)) }
        catch CocoaError.fileReadNoSuchFile { notes = [] }
    }

    mutating func enqueue(_ text: String) throws -> OutgoingWatchNote {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 500 else { throw CocoaError(.coderInvalidValue) }
        let note = OutgoingWatchNote(id: UUID().uuidString, text: clean, date: .now)
        try persist(notes + [note])
        return note
    }

    mutating func complete(id: String, succeeded: Bool) throws {
        var updated = notes
        if succeeded { updated.removeAll { $0.id == id } }
        else if let index = updated.firstIndex(where: { $0.id == id }) { updated[index].failed = true }
        try persist(updated)
    }

    mutating func retry(id: String) throws -> OutgoingWatchNote {
        guard let index = notes.firstIndex(where: { $0.id == id && $0.failed }) else { throw CocoaError(.fileNoSuchFile) }
        var updated = notes
        updated[index].failed = false
        try persist(updated)
        return updated[index]
    }

    mutating func reconcile(activeIDs: Set<String>) throws {
        var updated = notes
        for index in updated.indices { updated[index].failed = !activeIDs.contains(updated[index].id) }
        try persist(updated)
    }

    private mutating func persist(_ updated: [OutgoingWatchNote]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: url, options: .atomic)
        notes = updated
    }
}
