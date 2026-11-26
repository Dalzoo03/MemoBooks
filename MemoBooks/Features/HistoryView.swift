import SwiftUI
import SwiftData

private func won(_ amount: Int) -> String {
    amount.formatted(.currency(code: "KRW").precision(.fractionLength(0)))
}

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var search = ""
    @State private var category = "전체"
    @State private var kindFilter = "전체"
    @State private var editing: Expense?
    @State private var deleting: Expense?
    @State private var error: String?

    private var filtered: [Expense] {
        expenses.filter {
            (kindFilter == "전체" || $0.kind.rawValue == kindFilter) &&
            (category == "전체" || $0.category == category) &&
            (search.isEmpty || $0.memo.localizedCaseInsensitiveContains(search) || $0.category.contains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("유형", selection: $kindFilter) {
                        Text("전체").tag("전체")
                        ForEach(TransactionKind.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented)
                    Picker("카테고리", selection: $category) {
                        Text("전체").tag("전체")
                        ForEach(ExpenseCategory.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    LabeledContent("검색 결과 지출", value: won(filtered.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }))
                    LabeledContent("검색 결과 수입", value: won(filtered.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }))
                }
                if filtered.isEmpty {
                    ContentUnavailableView("내역이 없어요", systemImage: "text.book.closed",
                        description: Text("기록을 추가하거나 검색 조건을 바꿔 보세요"))
                }
                ForEach(filtered) { expense in
                    Button { editing = expense } label: { ExpenseRow(expense: expense) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("삭제", role: .destructive) { deleting = expense }
                            Button("수정") { editing = expense }.tint(AppStyle.accent)
                        }
                }
            }
            .searchable(text: $search, prompt: "메모 또는 카테고리 검색")
            .navigationTitle("내역")
            .sheet(item: $editing) { ExpenseEditor(expense: $0) }
            .confirmationDialog("이 지출을 삭제할까요?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    guard let expense = deleting else { return }
                    context.delete(expense)
                    do { try context.save() } catch {
                        context.rollback()
                        self.error = "삭제하지 못했어요. 다시 시도해 주세요."
                    }
                    deleting = nil
                }
            }
            .alert("저장 오류", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("확인") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}

private struct ExpenseRow: View {
    let expense: Expense
    var body: some View { LedgerRow(expense: expense) }
}

struct ExpenseEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let expense: Expense
    @State private var amount: String
    @State private var memo: String
    @State private var kind: TransactionKind
    @State private var category: String
    @State private var date: Date
    @State private var error: String?

    init(expense: Expense) {
        self.expense = expense
        _amount = State(initialValue: String(expense.amount))
        _memo = State(initialValue: expense.memo)
        _category = State(initialValue: expense.category)
        _kind = State(initialValue: expense.kind)
        _date = State(initialValue: expense.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("유형", selection: $kind) {
                    ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                    .onChange(of: kind) { _, value in
                        if ExpenseCategory(rawValue: category)?.kind != value { category = ExpenseCategory.fallback(for: value).rawValue }
                    }
                TextField("금액 (원)", text: $amount).keyboardType(.numberPad)
                TextField("메모", text: $memo)
                Picker("카테고리", selection: $category) {
                    ForEach(ExpenseCategory.categories(for: kind)) { Text($0.rawValue).tag($0.rawValue) }
                }
                DatePicker("날짜", selection: $date, in: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 32_503_680_000), displayedComponents: .date)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("기록 수정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(DraftValidation.amount(from: amount) == nil || memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || memo.count > 500)
                }
            }
        }
    }

    private func save() {
        guard let value = DraftValidation.amount(from: amount) else { return }
        let old = (expense.amount, expense.memo, expense.category, expense.date, expense.kind)
        expense.kind = kind
        expense.amount = value
        expense.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.category = category
        expense.date = date
        do { try context.save(); dismiss() } catch {
            expense.amount = old.0; expense.memo = old.1
            expense.category = old.2; expense.date = old.3; expense.kind = old.4
            self.error = "저장하지 못했어요. 다시 시도해 주세요."
        }
    }
}

struct CalendarView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var editing: Expense?
    @State private var showBudget = false
    @State private var budgetInput = ""
    @AppStorage("monthlyExpenseBudget") private var budget = 0
    private let calendar = Calendar.current

    private var monthly: [Expense] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        return expenses.filter { $0.date >= interval.start && $0.date < interval.end }
    }
    private var total: Int { monthly.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }
    private var income: Int { monthly.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount } }
    private var daily: [Date: Int] {
        ExpenseCalendar.expenseTotals(expenses, month: month, calendar: calendar)
    }
    private var selectedExpenses: [Expense] {
        monthly.filter { calendar.isDate($0.date, inSameDayAs: selected) }
    }
    private var categories: [(name: String, amount: Int)] {
        Dictionary(grouping: monthly.filter { $0.kind == .expense }, by: \.category)
            .map { (name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount }
    }

    var body: some View {
        let dayTotals = daily
        return NavigationStack {
            List {
                Section {
                    HStack {
                        Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("이전 달")
                        Spacer()
                        Text(month, format: .dateTime.year().month()).font(.title3.bold())
                        Spacer()
                        Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("다음 달")
                    }.buttonStyle(.borderless)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("월 지출").font(.subheadline).foregroundStyle(.secondary)
                        Text(won(total)).font(.largeTitle.bold()).foregroundStyle(AppStyle.accent)
                        Text("수입 \(won(income)) · \(monthly.count)건 기록").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                    calendarGrid(dayTotals: dayTotals)
                }
                Section("선택한 날 · \(selected.formatted(.dateTime.month().day()))") {
                    LabeledContent("하루 지출", value: won(dayTotals[calendar.startOfDay(for: selected), default: 0]))
                    if selectedExpenses.isEmpty {
                        Text("이 날짜에 기록된 지출이 없어요").foregroundStyle(.secondary)
                    }
                    ForEach(selectedExpenses) { expense in
                        Button { editing = expense } label: { ExpenseRow(expense: expense) }
                            .buttonStyle(.plain)
                    }
                }
                Section("월 예산") {
                    if budget > 0 {
                        LabeledContent("매월 기본 예산", value: won(budget))
                        ProgressView(value: min(Double(total) / Double(budget), 1))
                            .tint(total > budget ? .orange : AppStyle.accent)
                        Text(total > budget ? "\(won(total - budget)) 초과했어요" : "\(won(budget - total)) 남았어요")
                            .foregroundStyle(total > budget ? .orange : .secondary)
                    } else { Text("예산을 정하고 남은 금액을 확인해 보세요").foregroundStyle(.secondary) }
                    Button(budget > 0 ? "예산 변경" : "예산 설정") {
                        budgetInput = budget > 0 ? String(budget) : ""
                        showBudget = true
                    }
                }
                Section("카테고리별 지출") {
                    if categories.isEmpty { Text("기록하면 자동으로 집계돼요").foregroundStyle(.secondary) }
                    ForEach(categories, id: \.name) { item in
                        VStack(spacing: 6) {
                            LabeledContent(item.name, value: won(item.amount))
                            ProgressView(value: total > 0 ? Double(item.amount) / Double(total) : 0).tint(AppStyle.accent)
                        }.padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("달력")
            .toolbar {
                Button("오늘") {
                    month = calendar.dateInterval(of: .month, for: .now)!.start
                    selected = calendar.startOfDay(for: .now)
                }
            }
            .sheet(item: $editing) { ExpenseEditor(expense: $0) }
            .sheet(isPresented: $showBudget) {
                NavigationStack {
                    Form {
                        TextField("매월 기본 예산 (원)", text: $budgetInput).keyboardType(.numberPad)
                        Text("모든 달에 같은 예산을 적용해요. 지출 합계는 AI가 아닌 앱에서 계산해요.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("예산 사용 안 함", role: .destructive) { budget = 0; showBudget = false }
                    }
                    .navigationTitle("월 예산")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("취소") { showBudget = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("저장") {
                                if let value = DraftValidation.amount(from: budgetInput) { budget = value; showBudget = false }
                            }.disabled(DraftValidation.amount(from: budgetInput) == nil)
                        }
                    }
                }.presentationDetents([.medium])
            }
        }
    }

    private func calendarGrid(dayTotals: [Date: Int]) -> some View {
        let cells = ExpenseCalendar.days(in: month, calendar: calendar)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 8) {
                ForEach(0..<7, id: \.self) { offset in
                    Text(symbols[(calendar.firstWeekday - 1 + offset) % 7])
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(cells.indices, id: \.self) { index in
                    if let day = cells[index] {
                        let value = dayTotals[calendar.startOfDay(for: day), default: 0]
                        let isSelected = calendar.isDate(day, inSameDayAs: selected)
                        Button { selected = day } label: {
                            VStack(spacing: 4) {
                                Text("\(calendar.component(.day, from: day))").font(.subheadline.bold())
                                Text(value > 0 ? value.formatted(.number.notation(.compactName)) : " ")
                                    .font(.caption2).lineLimit(1).minimumScaleFactor(0.5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(isSelected ? AppStyle.primaryFill : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(calendar.isDateInToday(day) ? AppStyle.accent : .clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(day.formatted(.dateTime.month().day())), 지출 \(won(value))")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    } else { Color.clear.frame(height: 48).accessibilityHidden(true) }
                }
            }
            Text("달력 금액은 지출 기준 · 날짜를 누르면 수입과 지출 내역 표시")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }

    private func moveMonth(_ offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: month) else { return }
        month = next
        selected = next
    }
}
