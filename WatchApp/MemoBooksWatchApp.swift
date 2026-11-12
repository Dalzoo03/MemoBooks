import SwiftUI
import WatchConnectivity
import Combine

@main
struct MemoBooksWatchApp: App {
    @StateObject private var sender = WatchSender()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchEntryView().environmentObject(sender)
            }
        }
    }
}

struct WatchEntryView: View {
    @EnvironmentObject private var sender: WatchSender
    @AppStorage("unsentExpenseText") private var text = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "leaf.fill").font(.title2).foregroundStyle(.mint).accessibilityHidden(true)
                Text("지금, 한 줄 기록").font(.title3.bold())
                TextField("예: 커피 4500원", text: $text)
                if text.count > 500 { Text("500자 이내로 입력해 주세요").font(.caption2).foregroundStyle(.orange) }
                Button { if sender.send(text) { text = "" } } label: {
                    Label("iPhone으로 보내기", systemImage: "paperplane.fill")
                }.buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 500 || !sender.ready)
                Label(sender.message, systemImage: "iphone")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(sender.pending) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.text).font(.caption)
                        if note.failed {
                            Button("다시 보내기") { sender.retry(note.id) }.disabled(!sender.ready)
                        } else { Text("전송 대기 중").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                NavigationLink("사용 방법") {
                    Text("입력창 마이크로 받아쓰거나 직접 입력하세요. iPhone 기록 탭에서 분석하고 확인하면 저장돼요. 시스템 받아쓰기에는 네트워크가 필요할 수 있어요.")
                        .font(.caption2).foregroundStyle(.secondary).padding()
                }.font(.caption)
            }
        }.navigationTitle("메모가계부")
    }
}

@MainActor
final class WatchSender: NSObject, ObservableObject, WCSessionDelegate {
    @Published var ready = false
    @Published var message = "iPhone 연결 준비 중"
    @Published private(set) var pending: [OutgoingWatchNote] = []
    private var outbox: WatchOutbox?
    override init() {
        super.init()
        do {
            let url = URL.applicationSupportDirectory.appendingPathComponent("watch-outbox.json")
            outbox = try WatchOutbox(url: url)
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
    func send(_ text: String) -> Bool {
        guard ready, WCSession.default.activationState == .activated else { return false }
        do {
            guard let note = try outbox?.enqueue(text) else { return false }
            pending = outbox?.notes ?? []
            transfer(note)
            return true
        } catch {
            message = "메모를 보관하지 못했어요. 입력 내용을 유지했으니 다시 시도해 주세요"
            return false
        }
    }
    func retry(_ id: String) {
        guard ready, WCSession.default.activationState == .activated else { return }
        do {
            guard let note = try outbox?.retry(id: id) else { return }
            pending = outbox?.notes ?? []
            transfer(note)
        } catch { message = "다시 보내지 못했어요. 메모는 보관 중이에요" }
    }
    private func transfer(_ note: OutgoingWatchNote) {
        WCSession.default.transferUserInfo(["id": note.id, "text": note.text, "timestamp": note.date.timeIntervalSince1970])
        message = "메모를 보관했어요. 연결되면 iPhone으로 전달해요"
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let activated = activationState == .activated
        Task { @MainActor in
            guard self.outbox != nil else { return }
            do {
                let active = Set(WCSession.default.outstandingUserInfoTransfers.compactMap { $0.userInfo["id"] as? String })
                try self.outbox?.reconcile(activeIDs: active)
                self.pending = self.outbox?.notes ?? []
            } catch {
                self.message = "전송 상태를 보관하지 못했어요. 앱을 다시 열어 주세요"
                return
            }
            self.ready = activated
            self.message = activated ? "기록을 iPhone으로 보낼 수 있어요" : "연결을 준비하지 못했어요. 앱을 다시 열어 주세요"
        }
    }
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let failed = error != nil
        let id = userInfoTransfer.userInfo["id"] as? String
        Task { @MainActor in
            self.message = failed ? "전송에 실패했어요. iPhone 연결 후 다시 보내 주세요" : "iPhone으로 전달했어요. 기록 탭에서 확인해 주세요"
            guard let id else { return }
            do {
                try self.outbox?.complete(id: id, succeeded: !failed)
                self.pending = self.outbox?.notes ?? []
            } catch {
                self.ready = false
                self.message = "전송 상태를 보관하지 못했어요. 메모는 남아 있으니 앱을 다시 열어 주세요"
            }
        }
    }
}
