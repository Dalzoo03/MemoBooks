import Foundation
let timestamp = Date(timeIntervalSince1970: 1_790_000_000)
let id = UUID()
let draft = WatchLedgerDraft(id: id, amount: 4500, memo: "커피", category: "카페", kind: .expense, date: timestamp, createdAt: timestamp)
try draft.validate()
let request = WatchLedgerRequest(action: .save, id: id, text: "커피 4500원", referenceDate: timestamp, draft: draft)
let decoded = try WatchLedgerRequest.decode(JSONEncoder().encode(request))
precondition(decoded.id == id && decoded.draft == draft)
let invalidID = WatchLedgerRequest(action: .save, id: UUID(), text: "커피 4500원", referenceDate: timestamp, draft: draft)
for invalid in [invalidID, WatchLedgerRequest(action: .save, id: id, text: "커피 4500원", referenceDate: timestamp, draft: nil), WatchLedgerRequest(action: .analyze, id: id, text: " ", referenceDate: timestamp, draft: nil)] {
    do { _ = try WatchLedgerRequest.decode(JSONEncoder().encode(invalid)); preconditionFailure("invalid request accepted") } catch { }
}
do { _ = try WatchLedgerRequest.decode(Data(repeating: 0, count: 20_001)); preconditionFailure("oversized request accepted") } catch { }
print("Passed Watch request validation and round-trip checks")
MainActor.assumeIsolated {
    var ends = 0
    let lifetime = WatchRequestCompletion()
    lifetime.install { ends += 1 }
    lifetime.finish() // OS expiration ends assertion before delayed work finishes.
    precondition(ends == 1)
    lifetime.finish()
    precondition(ends == 1, "delayed completion must not end an expired assertion twice")
    let early = WatchRequestCompletion()
    early.finish()
    early.install { ends += 1 }
    precondition(ends == 2, "expiry before registration must still release assertion")
}
