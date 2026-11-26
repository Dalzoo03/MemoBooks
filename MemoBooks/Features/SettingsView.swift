import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LedgerDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var records: [Expense]
    @AppStorage("lastBackupExport") private var lastBackup = 0.0
    @State private var exportDocument = LedgerDocument(data: Data())
    @State private var exportType = UTType.json
    @State private var showExport = false
    @State private var showImport = false
    @State private var pendingBackup: LedgerBackup?
    @State private var showImportPreview = false
    @State private var message: String?
    @State private var showWelcome = false
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "text.book.closed.fill").font(.largeTitle).foregroundStyle(AppStyle.accent)
                            .frame(width: 60, height: 60).background(AppStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("메모가계부").font(.title3.bold())
                            Text("나의 기록이 머무는 곳").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 10)
                }
                Section {
                    if isWorking { ProgressView("백업을 처리하고 있어요") }
                    LabeledContent("저장한 기록", value: "\(records.count)건")
                    Button { Task { await prepareExport(csv: false) } } label: { Label("백업 저장하기", systemImage: "arrow.up.document") }
                    Button { showImport = true } label: { Label("백업에서 복원하기", systemImage: "arrow.down.document") }
                    Button { Task { await prepareExport(csv: true) } } label: { Label("CSV로 내보내기", systemImage: "tablecells") }
                    if lastBackup > 0 {
                        LabeledContent("최근 JSON 백업", value: Date(timeIntervalSince1970: lastBackup).formatted(.dateTime.year().month().day()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("데이터 관리")
                } footer: {
                    Text("JSON 백업으로 기록을 복원할 수 있어요. CSV는 다른 앱에서 확인하는 용도예요. 내보낸 파일에는 거래 내용이 포함되니 보관 위치를 확인해 주세요.")
                }
                Section("도움말") {
                    Button { showWelcome = true } label: { Label("사용 방법", systemImage: "hand.wave") }
                    NavigationLink { privacy } label: { Label("개인정보와 온디바이스 AI", systemImage: "lock.shield") }
                    NavigationLink { troubleshooting } label: { Label("AI·음성·워치가 안 될 때", systemImage: "questionmark.circle") }
                }
                Section {
                    LabeledContent("버전", value: "0.2 · 개발 중")
                    Text("계좌 연결 없이 직접 남기는 가계부예요. 수입 − 지출은 기록 기준 차액이며 실제 계좌 잔액과 다를 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(isWorking)
            .navigationTitle("설정")
            .fileExporter(isPresented: $showExport, document: exportDocument, contentType: exportType,
                          defaultFilename: "MemoBooks-\(DraftValidation.dateText(.now))") { result in
                switch result {
                case .success:
                    if exportType == .json { lastBackup = Date.now.timeIntervalSince1970 }
                    message = "파일을 저장했어요"
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { message = "파일을 저장하지 못했어요. 다시 시도해 주세요" }
                }
            }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { Task { await prepareImport(url) } }
                else if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError {
                    message = "백업을 열지 못했어요. 파일이 기기에 다운로드됐는지 확인해 주세요"
                }
            }
            .sheet(isPresented: $showImportPreview, onDismiss: { pendingBackup = nil }) { importPreview }
            .sheet(isPresented: $showWelcome) { WelcomeView() }
            .alert("안내", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("확인") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private var importPreview: some View {
        NavigationStack {
            Form {
                if let backup = pendingBackup {
                    let ids = Set(records.compactMap(\.recordID))
                    let duplicates = backup.records.filter { ids.contains($0.id) }.count
                    Section("복원할 기록") {
                        LabeledContent("백업 기록", value: "\(backup.records.count)건")
                        LabeledContent("새로 추가", value: "\(backup.records.count - duplicates)건")
                        LabeledContent("이미 있는 기록", value: "\(duplicates)건")
                    }
                    Section {
                        Text("새 기록만 추가해요. 같은 ID의 기록은 건너뛰며, 기존 기록이나 수정한 내용을 덮어쓰지 않아요. 예산·워치 대기 메모·작성 중인 입력은 복원 대상에 포함되지 않아요.")
                            .font(.subheadline)
                        Button("확인하고 복원") { restore(backup) }.disabled(isWorking)
                    }
                }
            }
            .navigationTitle("백업 확인")
            .toolbar { Button("취소") { showImportPreview = false } }
        }.presentationDetents([.medium, .large])
    }

    private func prepareExport(csv: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let snapshot = try BackupService.snapshot(records, context: context)
            exportDocument = LedgerDocument(data: try await BackupFiles.export(snapshot, csv: csv))
            exportType = csv ? .commaSeparatedText : .json
            showExport = true
        } catch { message = "백업을 만들지 못했어요. \(error.localizedDescription)" }
    }
    private func prepareImport(_ url: URL) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            pendingBackup = try await BackupFiles.read(url)
            showImportPreview = true
        } catch { message = "복원할 수 없어요. \(error.localizedDescription)" }
    }
    private func restore(_ backup: LedgerBackup) {
        isWorking = true
        do {
            let count = try BackupService.restore(backup, context: context)
            showImportPreview = false
            message = "\(count)건을 추가했어요. 기존 기록은 유지했어요"
        } catch { message = "복원하지 못했어요. 다시 시도해 주세요" }
        isWorking = false
    }

    private var privacy: some View {
        List {
            Section("AI와 음성") {
                Text("거래 분석에는 Apple의 기기 내 모델을 사용해요. 모델 준비 후에는 인터넷 없이 분석할 수 있어요.")
                Text("앱의 마이크 버튼은 기기 내 한국어 음성인식을 지원할 때만 작동해요. 녹음 파일을 별도로 저장하지 않아요.")
                Text("키보드 마이크나 Apple Watch의 시스템 받아쓰기는 운영체제 설정을 따르며 네트워크가 필요할 수 있어요.")
            }
            Section("저장과 이동") {
                Text("거래는 이 기기의 앱 저장소에 보관해요. 자체 서버, 광고·분석 SDK, 계정이나 앱 자체 클라우드 동기화는 사용하지 않아요.")
                Text("워치 메모는 페어링된 iPhone으로 전달해요. 작성 중인 문장과 수신 대기 메모도 기기에 임시 보관해요.")
                Text("JSON·CSV를 내보내면 사용자가 선택한 위치에 파일이 저장돼요. 기기를 바꾸거나 앱을 지우기 전 백업을 저장해 주세요. OS 기기 백업 여부는 기기 설정을 따라요.")
            }
        }.navigationTitle("개인정보 안내").navigationBarTitleDisplayMode(.inline)
    }
    private var troubleshooting: some View {
        List {
            Section("AI가 준비되지 않았어요") {
                Text("Apple Intelligence를 지원하는 기기에서 기능을 켜고 모델 준비를 기다려 주세요. Xcode의 모델 가용성 테스트 설정도 확인해 주세요. 직접 입력은 계속 사용할 수 있어요.")
            }
            Section("음성 입력이 안 돼요") {
                Text("iPhone 설정에서 마이크·음성인식 권한을 확인해 주세요. 기기 내 한국어 인식이 준비되지 않았거나 마이크를 다른 앱이 사용하는 경우 입력이 제한될 수 있어요.")
                Button("앱 권한 설정 열기") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Section("워치 기록이 아직 안 보여요") {
                Text("iPhone과 Watch에 앱을 설치하고 각각 한 번 열어 주세요. 연결이 끊기면 전송이 지연될 수 있어요. ‘대기열에 추가’는 가계부 저장 완료를 뜻하지 않아요.")
            }
            Section("금액이나 날짜가 달라요") {
                Text("AI는 잘못 해석할 수 있어요. 저장 전 미리보기에서 수정하거나 내역을 눌러 고칠 수 있어요. 합계와 예산은 앱이 직접 계산해요.")
            }
        }.navigationTitle("도움말").navigationBarTitleDisplayMode(.inline)
    }
}
