import Foundation

// Regression: failed transfers must survive new typing, multiple failures and restart.
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: root) }
let url = root.appendingPathComponent("outbox.json")
var outbox = try WatchOutbox(url: url)
let first = try outbox.enqueue("커피 4500원")
let second = try outbox.enqueue("점심 9000원")
try outbox.complete(id: first.id, succeeded: false)
try outbox.complete(id: second.id, succeeded: false)
precondition(outbox.notes.count == 2 && outbox.notes.allSatisfy(\.failed))
var reopened = try WatchOutbox(url: url)
precondition(reopened.notes == outbox.notes, "failed notes survive restart")
let retried = try reopened.retry(id: first.id)
precondition(retried.id == first.id && retried.text == first.text, "retry keeps deduplication ID")
precondition(reopened.notes.count == 2 && !reopened.notes[0].failed)
try reopened.complete(id: first.id, succeeded: true)
precondition(reopened.notes.map(\.id) == [second.id], "success removes only that transfer")
let third = try reopened.enqueue("교통 1500원")
try reopened.reconcile(activeIDs: [third.id])
precondition(reopened.notes[0].failed && !reopened.notes[1].failed)
try reopened.reconcile(activeIDs: [])
precondition(reopened.notes.allSatisfy(\.failed), "interrupted queue entries remain retryable")
for invalid in ["  ", String(repeating: "가", count: 501)] {
    do { _ = try reopened.enqueue(invalid); preconditionFailure("invalid input accepted") }
    catch { }
}
let blocked = root.appendingPathComponent("blocked")
var failing = try WatchOutbox(url: blocked)
try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
do { _ = try failing.enqueue("저장 실패"); preconditionFailure("write must fail") }
catch { precondition(failing.notes.isEmpty, "failed persistence must not clear caller's draft") }
try Data("corrupt".utf8).write(to: url)
do { _ = try WatchOutbox(url: url); preconditionFailure("must preserve corrupt store") }
catch { let retained = try Data(contentsOf: url); precondition(retained == Data("corrupt".utf8)) }
print("Passed Watch outbox regression checks (failure, retry, restart, interrupted transfer, invalid input, disk error)")
let failureURL = root.appendingPathComponent("failure.json")
var durable = try WatchOutbox(url: failureURL)
let durableNote = try durable.enqueue("보존할 메모 5000원")
try durable.complete(id: durableNote.id, succeeded: false)
let before = durable.notes
let originalData = try Data(contentsOf: failureURL)
try FileManager.default.removeItem(at: failureURL)
try FileManager.default.createDirectory(at: failureURL, withIntermediateDirectories: true)
for action: (inout WatchOutbox) throws -> Void in [
    { try $0.complete(id: durableNote.id, succeeded: true) },
    { _ = try $0.retry(id: durableNote.id) },
    { try $0.reconcile(activeIDs: [durableNote.id]) }
] {
    do { try action(&durable); preconditionFailure("write failure expected") }
    catch { precondition(durable.notes == before, "failed mutations must preserve in-memory notes") }
}
try FileManager.default.removeItem(at: failureURL)
try originalData.write(to: failureURL)
let retainedOutbox = try WatchOutbox(url: failureURL)
precondition(retainedOutbox.notes == before)
print("Passed outbox persistence-failure checks for completion, retry and reconciliation")
let previewURL = root.appendingPathComponent("preview.json")
var previewBox = try WatchOutbox(url: previewURL)
let note = try previewBox.enqueue("커피 4500원")
let preview = WatchLedgerDraft(id: UUID(uuidString: note.id)!, amount: 4500, memo: "커피", category: "카페", kind: .expense, date: note.date, createdAt: note.date)
try previewBox.setDraft(preview, for: note.id)
let previewReloaded = try WatchOutbox(url: previewURL)
precondition(previewReloaded.notes.first?.draft == preview, "confirmation preview survives restart")
try previewBox.complete(id: note.id, succeeded: false)
precondition(previewBox.notes.first?.draft == preview, "uncertain save keeps confirmed draft for same-ID retry")
precondition(note.usesWatchConfirmation, "new notes use explicit Watch confirmation")
let legacyURL = root.appendingPathComponent("legacy.json")
try Data("[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"text\":\"커피 4500원\",\"date\":0,\"failed\":true}]".utf8).write(to: legacyURL)
let legacyBox = try WatchOutbox(url: legacyURL)
precondition(!legacyBox.notes[0].usesWatchConfirmation, "legacy notes must keep phone-inbox retry flow")
var editable = try WatchOutbox(url: root.appendingPathComponent("editable.json"))
let typo = try editable.enqueue("커피 사천원")
try editable.updateText("커피 4000원", for: typo.id)
precondition(editable.notes[0].id == typo.id && editable.notes[0].date == typo.date && editable.notes[0].text == "커피 4000원")
