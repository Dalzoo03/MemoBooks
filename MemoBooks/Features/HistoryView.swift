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
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("메모 또는 분류 검색", text: $search).accessibilityLabel("거래 내역 검색")
                    }.padding(12).background(AppStyle.canvas, in: Capsule())
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
            .scrollContentBackground(.hidden).background(AppStyle.canvas)
            .contentMargins(.top, 8, for: .scrollContent)
            .listSectionSpacing(16)
            .font(.subheadline)
            .listRowBackground(AppStyle.surface)
            .navigationTitle("내역").navigationBarTitleDisplayMode(.inline)
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
            .scrollContentBackground(.hidden).background(AppStyle.canvas)
            .navigationTitle("기록 수정").navigationBarTitleDisplayMode(.inline)
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
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            HStack(spacing: 8) { OwlMark(); Text("OwlLog").font(.title2.bold()) }
                            Spacer()
                            Button("오늘") {
                                month = calendar.dateInterval(of: .month, for: .now)!.start
                                selected = calendar.startOfDay(for: .now)
                            }.font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44)
                                .background(AppStyle.mintSurface, in: Capsule())
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { monthlyTotals }
                            VStack(alignment: .leading, spacing: 8) { monthlyTotals }
                        }.padding(.vertical, 12).padding(.horizontal, 16)
                            .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppStyle.outline.opacity(0.45), lineWidth: 0.75))
                        VStack(spacing: 8) {
                            HStack {
                                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                                    .accessibilityLabel("이전 달")
                                Spacer()
                                Text(month, format: .dateTime.year().month()).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                                Spacer()
                                Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                                    .accessibilityLabel("다음 달")
                            }.buttonStyle(.plain)
                            calendarGrid(dayTotals: dayTotals)
                        }.padding(12)
                            .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppStyle.outline.opacity(0.45), lineWidth: 0.75))
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("선택한 날짜").font(.caption).foregroundStyle(.secondary)
                                Text(selected, format: .dateTime.month().day()).font(.headline)
                            }
                            Spacer()
                            Text(selected, format: .dateTime.weekday(.wide)).font(.caption.weight(.medium))
                                .foregroundStyle(AppStyle.apricot).padding(.horizontal, 12).padding(.vertical, 6)
                                .background(AppStyle.apricotSurface, in: Capsule())
                        }
                        EntryView(embedded: true, entryDate: selected) {
                            withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("preview", anchor: .top) }
                        }
                        HStack {
                            Text("\(selected.formatted(.dateTime.month().day())) 내역").font(.headline)
                            Spacer()
                            Text("지출 \(won(dayTotals[calendar.startOfDay(for: selected), default: 0]))")
                                .font(.caption).foregroundStyle(AppStyle.apricot)
                        }
                        LedgerCard {
                            VStack(spacing: 0) {
                                if selectedExpenses.isEmpty { Text("아직 기록이 없어요. 위에서 첫 기록을 남겨 보세요").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8) }
                                ForEach(selectedExpenses) { expense in
                                    Button { editing = expense } label: { ExpenseRow(expense: expense) }.buttonStyle(.plain)
                                    if expense.id != selectedExpenses.last?.id { Divider() }
                                }
                            }
                        }
                        DisclosureGroup("예산과 카테고리별 지출") {
                            VStack(alignment: .leading, spacing: 16) {
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
                            }.padding(.top, 12)
                        }.font(.subheadline).padding(16)
                            .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
                }.scrollDismissesKeyboard(.interactively)
            }
            .background(AppStyle.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { ExpenseEditor(expense: $0) }
            .sheet(isPresented: $showWelcome, onDismiss: { hasSeenWelcome = true }) { WelcomeView() }
            .onAppear { if !hasSeenWelcome { showWelcome = true } }
            .sheet(isPresented: $showBudget) {
                NavigationStack {
                    Form {
                        TextField("매월 기본 예산 (원)", text: $budgetInput).keyboardType(.numberPad)
                        Text("모든 달에 같은 예산을 적용해요. 지출 합계는 AI가 아닌 앱에서 계산해요.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("예산 사용 안 함", role: .destructive) { budget = 0; showBudget = false }
                    }
                    .scrollContentBackground(.hidden).background(AppStyle.canvas)
                    .navigationTitle("월 예산").navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private var monthlyTotals: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("이번 달 지출").font(.caption).foregroundStyle(.secondary)
            Text(won(total)).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading)
        Divider()
        VStack(alignment: .leading, spacing: 4) {
            Text("이번 달 수입").font(.caption).foregroundStyle(.secondary)
            Text(won(income)).font(.headline).monospacedDigit().foregroundStyle(AppStyle.income)
                .lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calendarGrid(dayTotals: [Date: Int]) -> some View {
        let cells = ExpenseCalendar.days(in: month, calendar: calendar)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 5) {
            ForEach(0..<7, id: \.self) { offset in
                Text(symbols[(calendar.firstWeekday - 1 + offset) % 7]).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(cells.indices, id: \.self) { index in
                if let day = cells[index] {
                    let isSelected = calendar.isDate(day, inSameDayAs: selected)
                    let value = dayTotals[calendar.startOfDay(for: day), default: 0]
                    let dayIncome = monthly.filter { $0.kind == .income && calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.amount }
                    let hasIncome = dayIncome > 0
                    let weekday = calendar.component(.weekday, from: day)
                    Button { selected = day } label: {
                        VStack(spacing: 2) {
                            Text("\(calendar.component(.day, from: day))")
                                .font(.subheadline.weight(isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? Color.white : weekday == 1 ? AppStyle.apricot : weekday == 7 ? AppStyle.accent : Color.primary)
                            Group {
                                if value > 0 { Text("−" + compactAmount(value)).foregroundStyle(isSelected ? Color.white : AppStyle.apricot) }
                                if hasIncome { Text("+" + compactAmount(dayIncome)).foregroundStyle(isSelected ? Color.white : AppStyle.income) }
                                if value == 0 && !hasIncome { Text(" ").accessibilityHidden(true) }
                            }.font(.caption2).lineLimit(1).minimumScaleFactor(0.55)
                        }.frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 2)
                            .background(isSelected ? AppStyle.primaryFill : .clear, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(calendar.isDateInToday(day) && !isSelected ? AppStyle.accent : .clear))
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(day.formatted(.dateTime.month().day())), 지출 \(won(value))\(hasIncome ? ", 수입 있음" : "")")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                } else { Color.clear.frame(height: 44).accessibilityHidden(true) }
            }
        }
    }

    private func compactAmount(_ amount: Int) -> String {
        if amount >= 10_000 { return (Double(amount) / 10_000).formatted(.number.precision(.fractionLength(0...4))) + "만" }
        return amount.formatted()
    }

    private func moveMonth(_ offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: month) else { return }
        month = next
        selected = next
    }
}
