import SwiftUI
import SwiftData

struct EntryView: View {
    var embedded = false
    var entryDate: Date? = nil
    var onPreview: () -> Void = {}

    init(embedded: Bool = false, entryDate: Date? = nil, onPreview: @escaping () -> Void = {}) {
        self.embedded = embedded
        self.entryDate = entryDate
        self.onPreview = onPreview
        var descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\Expense.date, order: .reverse)])
        descriptor.fetchLimit = 3
        _recentRecords = Query(descriptor)
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var recentRecords: [Expense]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var voice = VoiceInput()
    @ObservedObject private var watchInbox = WatchInbox.shared
    @AppStorage("entryDraft") private var input = ""
    @AppStorage("entryDraftReference") private var referenceTimestamp = Date.now.timeIntervalSince1970
    @AppStorage("entryWatchNoteID") private var loadedNoteID = ""
    @State private var service = ExpenseParsingService()
    @State private var status = ModelStatus(isAvailable: false, message: "AI 상태 확인 중")
    @State private var isLoading = false
    @State private var request: Task<Void, Never>?
    @State private var requestID: UUID?
    @State private var showPreview = false
    @State private var amount = ""
    @State private var memo = ""
    @State private var kind = TransactionKind.expense
    @State private var category = ExpenseCategory.other
    @State private var date = Date.now
    @State private var wasAI = false
    @State private var errorMessage: String?
    @State private var saved = false
    @State private var voicePrefix = ""
    @FocusState private var inputFocused: Bool

    private let examples = ["점심 김치찌개 9000원", "어제 커피 4500원", "용돈 10만원 받음"]
    private var busy: Bool { isLoading || voice.isRecording || voice.isStarting }
    private var canSave: Bool {
        DraftValidation.amount(from: amount) != nil && !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && memo.count <= 500
    }

    var body: some View {
        Group {
            if embedded { formContent }
            else {
                NavigationStack {
                    ScrollViewReader { proxy in
                        ScrollView { formContent.padding(20) }
                            .onChange(of: showPreview) { _, visible in
                                if visible { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("preview", anchor: .top) } }
                            }
                    }
                    .background(AppStyle.canvas)
                    .navigationTitle("기록하기").navigationBarTitleDisplayMode(.inline)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("완료") { inputFocused = false } }
        }
        .onAppear { status = service.status }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { status = service.status }
            if phase == .background { voice.stop() }
        }
        .onChange(of: voice.transcript) { _, text in
            input = voicePrefix + text
            referenceTimestamp = DraftValidation.entryReferenceDate(watchNoteID: loadedNoteID, timestamp: referenceTimestamp, selectedDate: entryDate).timeIntervalSince1970
            saved = false
        }
        .onChange(of: entryDate) { _, _ in
            cancel()
            voice.stop()
            // Re-parse relative dates against the newly selected calendar day.
            if loadedNoteID.isEmpty { showPreview = false }
            saved = false
        }
        .onChange(of: showPreview) { _, visible in if visible && !embedded { onPreview() } }
        .sheet(isPresented: Binding(get: { embedded && showPreview }, set: { showPreview = $0 })) {
            NavigationStack {
                ScrollView {
                    preview.padding(16)
                    if let errorMessage {
                        Text(errorMessage).font(.subheadline).foregroundStyle(.red).padding(16)
                    }
                }.background(AppStyle.canvas)
                    .navigationTitle(wasAI ? "AI 정리 결과" : "직접 입력")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showPreview = false } } }
            }.presentationDetents([.large])
        }
        .onDisappear { cancel(); voice.stop() }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: embedded ? 12 : 20) {
            if !embedded { header }
            if !watchInbox.notes.isEmpty { watchNotes }
            if embedded { compactInputCard } else { inputCard }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(.red).padding(14)
                    .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("오류: \(errorMessage)")
            }
            if showPreview && !embedded { preview.id("preview") }
            if saved {
                Label("저장했어요. 달력과 내역에 반영했어요", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(AppStyle.income)
            }
            if !status.isAvailable { availabilityCard }
            if !embedded {
                Label("입력 내용은 서버로 전송하지 않아요", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private var compactInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("예: 어제 커피 4,500원", text: $input, axis: .vertical)
                .font(.body).lineLimit(1...3).focused($inputFocused)
                .disabled(busy || showPreview).accessibilityLabel("선택한 날짜의 수입 또는 지출")
                .padding(12).background(AppStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppStyle.outline.opacity(0.6)))
            if !showPreview {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { compactActions }
                    VStack(alignment: .leading, spacing: 10) { compactActions }
                }.font(.subheadline)
                if !input.isEmpty || !loadedNoteID.isEmpty {
                    Button("비우고 새 기록") {
                        input = ""; loadedNoteID = ""; saved = false; errorMessage = nil
                    }.font(.caption).disabled(busy)
                }
                if isLoading { Button("분석 취소") { cancel() }.font(.caption) }
                if let message = voice.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if input.count > 500 { Text("500자 이내로 입력해 주세요").font(.caption).foregroundStyle(.red) }
                Text(loadedNoteID.isEmpty ? "선택한 날짜를 기준으로 정리해요 · 저장 전 확인" : "워치 메모의 날짜를 기준으로 정리해요")
                    .font(.caption2).foregroundStyle(.secondary)
                if !recentRecords.isEmpty {
                    Divider()
                    Text("최근 기록 다시 쓰기").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(recentRecords.prefix(3))) { record in
                                Button {
                                    input = "\(record.memo) \(record.amount)원" + (record.kind == .income ? " 받음" : "")
                                    loadedNoteID = ""; saved = false; errorMessage = nil
                                } label: {
                                    Text("\(record.memo) \(record.amount.formatted())").font(.caption)
                                        .padding(.horizontal, 12).frame(minHeight: 44)
                                        .background(AppStyle.inset, in: Capsule())
                                }.buttonStyle(.plain).disabled(busy)
                            }
                        }
                    }
                }
            }
        }.padding(16)
            .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppStyle.outline.opacity(0.45), lineWidth: 0.75))
    }

    @ViewBuilder
    private var compactActions: some View {
        Button {
            if voice.isRecording || voice.isStarting { voice.finish() }
            else {
                inputFocused = false
                voicePrefix = input.isEmpty ? "" : input + " "
                Task { await voice.start() }
            }
        } label: {
            Label(voice.isRecording || voice.isStarting ? "종료" : "말하기", systemImage: voice.isRecording ? "stop.fill" : "mic.fill")
                .frame(minHeight: 44)
        }.buttonStyle(OwlPillStyle()).disabled(isLoading)
        Button(action: analyze) {
            if isLoading { ProgressView() } else { Label("AI 정리", systemImage: "sparkles") }
        }.buttonStyle(OwlPillStyle(foreground: .white, background: AppStyle.primaryFill))
            .opacity(busy || !status.isAvailable || input.isEmpty ? 0.5 : 1)
            .disabled(busy || !status.isAvailable || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || input.count > 500)
        Button { openManual() } label: { Text("직접 입력") }
            .buttonStyle(OwlPillStyle(foreground: AppStyle.apricot, background: AppStyle.apricotSurface)).disabled(busy)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("한 줄이면 충분해요").font(.title2.bold())
            Text("말하거나 한 줄 입력하면 정리해 드려요")
                .font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }

    private var inputCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("한 줄 기록", systemImage: "square.and.pencil").font(.headline)
                    Spacer()
                    if status.isAvailable {
                        Label("기기 내 AI", systemImage: "checkmark.shield.fill")
                            .font(.caption2.weight(.medium)).foregroundStyle(AppStyle.accent)
                    }
                }
                TextField("예: 어제 점심 김치찌개 9000원", text: $input, axis: .vertical)
                    .font(.body).lineLimit(2...4).focused($inputFocused)
                    .disabled(busy || showPreview).accessibilityLabel("수입 또는 지출 내용")
                if !showPreview {
                    HStack {
                        Text("\(input.count)/500자").font(.caption2).foregroundStyle(input.count > 500 ? Color.red : Color.secondary)
                        Spacer()
                        if !input.isEmpty && !busy { Button("비우기") { input = ""; loadedNoteID = ""; saved = false }.font(.caption) }
                    }
                    Divider()
                    voiceButton
                    if isLoading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("금액과 분류를 정리하고 있어요").font(.subheadline)
                            Spacer()
                            Button("취소") { cancel() }.font(.subheadline)
                        }.padding(.vertical, 10)
                    } else {
                        Button(action: analyze) {
                            Label("AI로 정리하기", systemImage: "sparkles")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }.buttonStyle(.borderedProminent)
                            .disabled(busy || !status.isAvailable || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || input.count > 500)
                        Button("직접 입력할게요") { openManual() }
                            .font(.subheadline).frame(maxWidth: .infinity).disabled(busy)
                    }
                }
            }
        }
    }

    private var voiceButton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if voice.isRecording || voice.isStarting { voice.finish() }
                else {
                    inputFocused = false
                    voicePrefix = input.isEmpty ? "" : input + " "
                    Task { await voice.start() }
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title2).frame(width: 56, height: 56)
                        .background(AppStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(voice.isRecording ? "다 말했어요" : (voice.isStarting ? "음성 입력 취소" : "말로 남기기"))
                            .font(.subheadline.weight(.semibold))
                        Text(voice.isRecording ? "듣고 있어요 · 누르면 받아쓰기 종료" : "“커피 4500원”처럼 말해 보세요")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(14)
                    .background(AppStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).disabled(isLoading)
            if let message = voice.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if input.isEmpty && !busy {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(examples, id: \.self) { example in
                            Button(example) {
                                input = example; referenceTimestamp = Date.now.timeIntervalSince1970
                                loadedNoteID = ""; saved = false
                            }.font(.caption).buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var preview: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 18) {
                Label("이렇게 기록할까요?", systemImage: "checkmark.circle").font(.title3.bold())
                Text("금액·날짜를 확인해 주세요. 아직 저장되지 않았어요")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("유형", selection: $kind) {
                    ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                    .onChange(of: kind) { _, new in if category.kind != new { category = .fallback(for: new) } }
                LabeledContent("금액 (원)") {
                    TextField("금액", text: $amount).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .font(.title2.bold()).accessibilityLabel("금액 원")
                }
                if DraftValidation.amount(from: amount) == nil {
                    Text("0원 초과, 1조 원 이하로 입력해 주세요").font(.caption).foregroundStyle(.red)
                }
                Divider()
                Picker("분류", selection: $category) {
                    ForEach(ExpenseCategory.categories(for: kind)) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }
                TextField("메모", text: $memo).accessibilityLabel("거래 메모")
                DatePicker("날짜", selection: $date, in: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 32_503_680_000), displayedComponents: .date)
                Button("확인하고 저장", action: save)
                    .font(.headline).frame(maxWidth: .infinity).buttonStyle(.borderedProminent).controlSize(.large).disabled(!canSave)
                Button("다시 입력하기") { showPreview = false; errorMessage = nil }
                    .font(.subheadline).frame(maxWidth: .infinity)
            }
        }
    }

    private var availabilityCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(status.message, systemImage: "info.circle").font(.subheadline)
                Button("AI 상태 다시 확인") { status = service.status }.font(.caption)
            }
        }
    }
    private var watchNotes: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("워치에서 보낸 메모 \(watchInbox.notes.count)개", systemImage: "applewatch").font(.headline)
                ForEach(watchInbox.notes) { note in
                    Button {
                        input = note.text; referenceTimestamp = note.date.timeIntervalSince1970
                        loadedNoteID = note.id; saved = false
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.text).font(.subheadline)
                            Text(note.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    }.buttonStyle(.plain).disabled(busy || showPreview)
                    Divider()
                }
                Text("불러온 메모는 저장을 마치면 목록에서 사라져요").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func analyze() {
        guard !busy, !showPreview, input.count <= 500 else { return }
        inputFocused = false; saved = false; errorMessage = nil; isLoading = true
        let id = UUID(); requestID = id
        let original = input
        let today = DraftValidation.entryReferenceDate(watchNoteID: loadedNoteID, timestamp: referenceTimestamp, selectedDate: entryDate)
        request = Task { @MainActor in
            do {
                let result = try await service.parse(original, today: today)
                guard requestID == id, !Task.isCancelled else { return }
                amount = String(result.amount)
                memo = result.draft.memo
                kind = result.kind; category = result.category; date = result.date
                wasAI = true; showPreview = true
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                errorMessage = "정리하지 못했어요. \(error.localizedDescription) 직접 입력도 가능해요."
            }
            if requestID == id { isLoading = false; request = nil }
        }
    }
    private func cancel() { requestID = nil; request?.cancel(); request = nil; isLoading = false }
    private func openManual() {
        saved = false; errorMessage = nil; amount = ""; memo = input
        kind = .expense; category = .other
        date = DraftValidation.entryReferenceDate(watchNoteID: loadedNoteID, timestamp: referenceTimestamp, selectedDate: entryDate)
        wasAI = false; showPreview = true
    }
    private func save() {
        guard canSave, let value = DraftValidation.amount(from: amount) else { return }
        let record = Expense(amount: value, category: category.rawValue,
                             memo: memo.trimmingCharacters(in: .whitespacesAndNewlines), date: date,
                             isAiClassified: wasAI, kind: kind)
        context.insert(record)
        do {
            try context.save()
            if let note = watchInbox.notes.first(where: { $0.id == loadedNoteID }) { watchInbox.remove(note) }
            showPreview = false; input = ""; loadedNoteID = ""
            referenceTimestamp = Date.now.timeIntervalSince1970; errorMessage = nil; saved = true
        } catch {
            context.delete(record)
            errorMessage = "저장하지 못했어요. 입력 내용을 유지했으니 다시 시도해 주세요."
        }
    }
}
