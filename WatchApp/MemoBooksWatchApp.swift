import SwiftUI
import WatchConnectivity
import Combine

@main
struct MemoBooksWatchApp: App {
    @StateObject private var sender = WatchSender()
    var body: some Scene {
        WindowGroup { NavigationStack { WatchEntryView().environmentObject(sender) } }
    }
}

struct WatchEntryView: View {
    @EnvironmentObject private var sender: WatchSender
    @AppStorage("unsentExpenseText") private var text = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("지금, 한 줄 기록", systemImage: "mic.circle.fill").font(.headline)
                    .foregroundStyle(Color(red: 0.54, green: 0.84, blue: 0.74))
                TextField("말하거나 입력하기", text: $text).disabled(sender.busy)
                Text("입력창의 마이크로 “커피 4500원”처럼 말해 보세요").font(.caption2).foregroundStyle(.secondary)
                if text.count > 500 { Text("500자 이내로 입력해 주세요").font(.caption2).foregroundStyle(.orange) }
                Button {
                    if sender.analyzeInput(text) { text = "" }
                } label: { Label("AI로 정리하기", systemImage: "sparkles") }
                    .buttonStyle(.borderedProminent).tint(Color(red: 0.54, green: 0.84, blue: 0.74))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 500 || !sender.ready || sender.busy)
                if sender.busy { ProgressView("iPhone에서 처리 중") }
                Text(sender.message).font(.caption2).foregroundStyle(.secondary)
                if !sender.pending.isEmpty { Text("확인할 기록").font(.headline) }
                ForEach(sender.pending) { note in
                    Button { sender.resume(note) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.text).lineLimit(3)
                            Text(!note.usesWatchConfirmation ? "iPhone으로 다시 보내기" : (note.draft == nil ? "AI 분석 다시 시도" : "결과 확인·저장"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.disabled(!sender.ready || sender.busy)
                    if note.usesWatchConfirmation && note.draft == nil {
                        Button("내용 고치기") { sender.editingNote = note }.font(.caption2).disabled(sender.busy)
                    }
                }
                NavigationLink("사용 방법") {
                    Text("아이폰이 연결되어 있으면 기기 내 AI가 분석해요. 워치에서 결과를 확인하고 저장하세요. 연결이 안 되면 메모를 보관하니 나중에 다시 눌러 주세요. 시스템 받아쓰기는 네트워크가 필요할 수 있어요.")
                        .font(.caption2).padding()
                }.font(.caption)
            }.padding(.horizontal, 4)
        }.navigationTitle("OwlLog")
            .sheet(item: $sender.presentedDraft) { WatchDraftView(draft: $0).environmentObject(sender) }
            .sheet(item: $sender.editingNote) { WatchNoteEditor(note: $0).environmentObject(sender) }
    }
}

struct WatchNoteEditor: View {
    @EnvironmentObject private var sender: WatchSender
    let note: OutgoingWatchNote
    @State private var text: String
    init(note: OutgoingWatchNote) { self.note = note; _text = State(initialValue: note.text) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("내용", text: $text)
                Button("수정 내용 보관") { sender.updateText(text, note: note) }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 500)
                Text(sender.message).font(.caption2)
            }.navigationTitle("내용 수정")
        }
    }
}

struct WatchDraftView: View {
    @EnvironmentObject private var sender: WatchSender
    @State var draft: WatchLedgerDraft
    @State private var amount: String
    init(draft: WatchLedgerDraft) {
        _draft = State(initialValue: draft)
        _amount = State(initialValue: String(draft.amount))
    }
    private var edited: WatchLedgerDraft {
        var value = draft
        value.amount = DraftValidation.amount(from: amount) ?? 0
        value.memo = value.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }
    private var valid: Bool { (try? edited.validate()) != nil }
    var body: some View {
        NavigationStack {
            Form {
                Text("아직 저장되지 않았어요").font(.caption2).foregroundStyle(.secondary)
                Picker("유형", selection: $draft.kind) {
                    ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
                }.onChange(of: draft.kind) { _, value in
                    if ExpenseCategory(rawValue: draft.category)?.kind != value { draft.category = ExpenseCategory.fallback(for: value).rawValue }
                }
                TextField("금액 (원)", text: $amount)
                Picker("분류", selection: $draft.category) {
                    ForEach(ExpenseCategory.categories(for: draft.kind)) { Text($0.rawValue).tag($0.rawValue) }
                }
                TextField("메모", text: $draft.memo)
                DatePicker("날짜", selection: $draft.date,
                    in: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 32_503_680_000), displayedComponents: .date)
                if sender.busy { ProgressView("저장 확인 중") }
                Text(sender.message).font(.caption2).foregroundStyle(.secondary)
                Button("확인하고 저장") { sender.save(edited) }
                    .buttonStyle(.borderedProminent).tint(Color(red: 0.54, green: 0.84, blue: 0.74)).disabled(!valid || sender.busy)
            }.disabled(sender.busy)
                .navigationTitle("기록 확인")
        }.interactiveDismissDisabled(sender.busy)
    }
}

@MainActor
final class WatchSender: NSObject, ObservableObject, WCSessionDelegate {
    @Published var ready = false
    @Published var message = "iPhone 연결 준비 중"
    @Published private(set) var busy = false
    @Published private(set) var pending: [OutgoingWatchNote] = []
    @Published var presentedDraft: WatchLedgerDraft?
    @Published var editingNote: OutgoingWatchNote?
    private var outbox: WatchOutbox?
    private var requestID: UUID?
    private var legacyTransferIDs: Set<String> = []
    override init() {
        super.init()
        do {
            outbox = try WatchOutbox(url: URL.applicationSupportDirectory.appendingPathComponent("watch-outbox.json"))
            pending = outbox?.notes ?? []
        } catch {
            message = "보내던 메모를 열지 못했어요. 앱을 삭제하지 말고 다시 열어 주세요"
            return
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func analyzeInput(_ text: String) -> Bool {
        guard ready, !busy else { return false }
        do {
            guard let note = try outbox?.enqueue(text) else { return false }
            pending = outbox?.notes ?? []
            analyze(note)
            return true
        } catch { message = "메모를 보관하지 못했어요. 입력 내용은 유지했어요"; return false }
    }
    func resume(_ note: OutgoingWatchNote) {
        guard !busy else { return }
        guard !legacyTransferIDs.contains(note.id) else { message = "이전 메모를 iPhone으로 전송 중이에요"; return }
        if !note.usesWatchConfirmation {
            do {
                let legacy = try outbox?.retry(id: note.id)
                if let legacy {
                    WCSession.default.transferUserInfo(["id": legacy.id, "text": legacy.text, "timestamp": legacy.date.timeIntervalSince1970])
                    legacyTransferIDs.insert(legacy.id)
                    pending = outbox?.notes ?? []
                    message = "이전 버전 메모를 iPhone으로 보내요. iPhone 기록 탭에서 확인해 주세요"
                }
            } catch { message = "다시 보내지 못했어요. 메모는 보관 중이에요" }
            return
        }
        if let draft = note.draft { presentedDraft = draft; message = "금액·분류·날짜를 확인해 주세요" }
        else { analyze(note) }
    }
    func updateText(_ text: String, note: OutgoingWatchNote) {
        guard !busy else { return }
        do {
            try outbox?.updateText(text, for: note.id)
            pending = outbox?.notes ?? []
            editingNote = nil
            message = "내용을 고쳤어요. AI 분석을 다시 눌러 주세요"
        } catch { message = "수정 내용을 보관하지 못했어요. 다시 시도해 주세요" }
    }
    private func analyze(_ note: OutgoingWatchNote) {
        guard let id = UUID(uuidString: note.id) else { return }
        request(WatchLedgerRequest(action: .analyze, id: id, text: note.text, referenceDate: note.date, draft: nil))
    }
    func save(_ draft: WatchLedgerDraft) {
        guard !busy, let note = pending.first(where: { $0.id == draft.id.uuidString }) else { return }
        do {
            try outbox?.setDraft(draft, for: note.id)
            pending = outbox?.notes ?? []
            request(WatchLedgerRequest(action: .save, id: draft.id, text: note.text, referenceDate: note.date, draft: draft))
        } catch { message = "수정한 내용을 보관하지 못했어요. 다시 시도해 주세요" }
    }
    private func request(_ value: WatchLedgerRequest) {
        guard ready, !busy else { return }
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            message = "메모는 보관 중이에요. iPhone을 가까이 두고 잠금을 푼 뒤 다시 시도해 주세요"
            return
        }
        do {
            let data = try JSONEncoder().encode(value)
            let token = UUID()
            requestID = token; busy = true
            message = value.action == .save ? "iPhone에 저장하고 있어요" : "iPhone의 AI가 정리하고 있어요"
            WCSession.default.sendMessage(["ledgerRequest": data], replyHandler: { [weak self] reply in
                let data = reply["ledgerReply"] as? Data
                Task { @MainActor in self?.receive(data, for: value, token: token) }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.requestID == token else { return }
                    self.requestID = nil; self.busy = false
                    self.message = "응답을 받지 못했어요. 메모는 남아 있으니 다시 시도해 주세요. iPhone 앱을 열어야 할 수 있어요"
                }
            })
        } catch { message = "요청을 만들지 못했어요. 메모는 보관 중이에요" }
    }
    private func receive(_ data: Data?, for request: WatchLedgerRequest, token: UUID) {
        guard requestID == token else { return }
        requestID = nil; busy = false
        do {
            guard let data, data.count <= 20_000 else { throw CocoaError(.coderInvalidValue) }
            let reply = try JSONDecoder().decode(WatchLedgerReply.self, from: data)
            guard reply.id == request.id else { throw CocoaError(.coderInvalidValue) }
            if reply.status == .failure { message = reply.message; return }
            guard reply.status == (request.action == .save ? .saved : .preview) else { throw CocoaError(.coderInvalidValue) }
            guard let draft = reply.draft, draft.id == request.id else { throw CocoaError(.coderInvalidValue) }
            try draft.validate()
            if reply.status == .saved {
                try outbox?.complete(id: request.id.uuidString, succeeded: true)
                presentedDraft = nil
                message = "\(draft.amount.formatted())원 · \(draft.category) 저장 완료"
            } else {
                try outbox?.setDraft(draft, for: request.id.uuidString)
                presentedDraft = draft
                message = reply.message
            }
            pending = outbox?.notes ?? []
        } catch { message = "결과를 확인하거나 보관하지 못했어요. 같은 기록을 다시 시도하면 중복 저장하지 않아요" }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let activated = activationState == .activated
        Task { @MainActor in
            guard self.outbox != nil else { return }
            do {
                self.legacyTransferIDs = Set(WCSession.default.outstandingUserInfoTransfers.compactMap { $0.userInfo["id"] as? String })
                try self.outbox?.reconcile(activeIDs: self.legacyTransferIDs)
                self.pending = self.outbox?.notes ?? []
                self.ready = activated
                self.message = activated ? "말하거나 입력하면 AI로 정리할 수 있어요" : "연결을 준비하지 못했어요. 앱을 다시 열어 주세요"
            } catch { self.message = "메모 상태를 보관하지 못했어요. 앱을 다시 열어 주세요" }
        }
    }
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let failed = error != nil
        let id = userInfoTransfer.userInfo["id"] as? String
        Task { @MainActor in
            guard let id else { return }
            self.legacyTransferIDs.remove(id)
            do {
                try self.outbox?.complete(id: id, succeeded: !failed)
                self.pending = self.outbox?.notes ?? []
            } catch { self.ready = false; self.message = "메모 상태를 보관하지 못했어요. 앱을 다시 열어 주세요" }
        }
    }
}
