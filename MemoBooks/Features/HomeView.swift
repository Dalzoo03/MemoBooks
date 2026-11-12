import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Expense.date, order: .reverse) private var records: [Expense]
    @AppStorage("monthlyExpenseBudget") private var budget = 0
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @State private var editing: Expense?
    let openEntry: () -> Void
    let openCalendar: () -> Void
    let openHistory: () -> Void
    private let calendar = Calendar.current
    private var month: [Expense] {
        guard let range = calendar.dateInterval(of: .month, for: .now) else { return [] }
        return records.filter { $0.date >= range.start && $0.date < range.end }
    }
    private var spent: Int { month.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }
    private var earned: Int { month.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount } }
    private var todaySpent: Int {
        month.filter { $0.kind == .expense && calendar.isDateInToday($0.date) }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Date.now, format: .dateTime.year().month()).font(.subheadline).foregroundStyle(.secondary)
                            Text("작은 기록,\n가벼워지는 하루").font(.largeTitle.bold())
                        }
                        Spacer()
                        Image(systemName: "leaf.fill").font(.system(size: 34)).foregroundStyle(.teal)
                            .padding(18).background(.teal.opacity(0.09), in: Circle()).accessibilityHidden(true)
                    }.padding(.vertical, 8)
                    summary
                    Button(action: openEntry) {
                        HStack(spacing: 16) {
                            Image(systemName: "mic.fill").font(.title2)
                                .frame(width: 48, height: 48).background(.white.opacity(0.16), in: Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text("오늘의 기록 남기기").font(.headline)
                                Text("말하거나 한 줄만 적어 주세요").font(.subheadline)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }.padding(20).foregroundStyle(.white)
                            .background(AppStyle.hero.gradient, in: RoundedRectangle(cornerRadius: 24))
                    }.buttonStyle(.plain)
                    if budget > 0 { budgetCard }
                    HStack {
                        Text("최근 기록").font(.title3.bold())
                        Spacer()
                        Button("전체 보기", action: openHistory).font(.subheadline)
                    }.padding(.top, 8)
                    LedgerCard {
                        if records.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: "text.book.closed").font(.title).foregroundStyle(.teal)
                                Text("첫 기록부터 시작해 볼까요?").font(.headline)
                                Text("“점심 9000원”처럼 적으면\n금액과 분류를 정리해 드려요.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button("첫 기록 남기기", action: openEntry).buttonStyle(.bordered)
                            }
                        } else {
                            VStack(spacing: 12) {
                                ForEach(Array(records.prefix(4))) { record in
                                    Button { editing = record } label: { LedgerRow(expense: record) }.buttonStyle(.plain)
                                    if record.persistentModelID != records.prefix(4).last?.persistentModelID { Divider() }
                                }
                            }
                        }
                    }
                    Label("AI 분석은 기기 안에서, 저장은 확인한 뒤에", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 6)
                }.padding(20)
            }
            .background(AppStyle.canvas)
            .navigationTitle("메모가계부").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { ExpenseEditor(expense: $0) }
            .sheet(isPresented: $showWelcome, onDismiss: { hasSeenWelcome = true }) { WelcomeView(onStart: openEntry) }
            .onAppear { if !hasSeenWelcome { showWelcome = true } }
        }
    }

    private var summary: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("이번 달 지출").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: openCalendar) { Image(systemName: "calendar") }.accessibilityLabel("소비 달력 보기")
                }
                Text(currencyText(spent)).font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack {
                        amountLabel("수입", amount: earned, color: .blue)
                        Spacer()
                        amountLabel("수입 − 지출", amount: earned - spent, color: .primary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        amountLabel("수입", amount: earned, color: .blue)
                        amountLabel("수입 − 지출", amount: earned - spent, color: .primary)
                    }
                }
                Text("오늘은 \(currencyText(todaySpent)) 기록했어요").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func amountLabel(_ title: String, amount: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(currencyText(amount)).font(.headline).foregroundStyle(color).monospacedDigit()
        }
    }
    private var budgetCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("이번 달 예산").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(spent > budget ? "예산 초과" : "\(currencyText(budget - spent)) 남음")
                        .font(.caption.weight(.semibold)).foregroundStyle(spent > budget ? .orange : .teal)
                }
                ProgressView(value: min(Double(spent) / Double(budget), 1)).tint(spent > budget ? .orange : .teal)
                Button("달력에서 자세히 보기", action: openCalendar).font(.caption)
            }
        }
    }
}

struct WelcomeView: View {
    var onStart: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "leaf.circle.fill").font(.system(size: 64)).foregroundStyle(.teal)
                    Text("기록은 가볍게,\n내 정보는 내 기기에").font(.largeTitle.bold())
                    feature("한 줄이면 충분해요", detail: "“어제 점심 9000원”, “용돈 10만원 받음”처럼 입력하세요", icon: "square.and.pencil")
                    feature("말로도 남길 수 있어요", detail: "기기 내 한국어 음성인식이 준비되면 마이크로 입력할 수 있어요", icon: "mic")
                    feature("확인하고 저장해요", detail: "AI는 틀릴 수 있어요. 금액·분류·날짜를 확인한 뒤 저장하세요", icon: "checkmark.shield")
                    Button("기록 시작하기") { dismiss(); onStart() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }.padding(28)
            }.background(AppStyle.canvas)
            .toolbar { Button("닫기") { dismiss() } }
        }
    }
    private func feature(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundStyle(.teal).frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
