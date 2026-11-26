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
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Date.now, format: .dateTime.year().month()).font(.subheadline).foregroundStyle(.secondary)
                            Text("나의 가계부").font(.title2.bold())
                        }
                        Spacer()
                        Image(systemName: "text.book.closed.fill").font(.title3)
                            .foregroundStyle(AppStyle.accent).padding(12)
                            .background(AppStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityHidden(true)
                    }
                    summary
                    Button(action: openEntry) {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform").font(.title3)
                            Text("한 줄로 기록하기").font(.headline)
                            Spacer()
                            Image(systemName: "plus").font(.headline)
                        }.padding(18).foregroundStyle(.white)
                            .background(AppStyle.primaryFill, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                    HStack {
                        Text("최근 거래").font(.headline)
                        Spacer()
                        Button("전체 보기", action: openHistory).font(.subheadline)
                    }.padding(.top, 4)
                    LedgerCard {
                        if records.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: "text.book.closed").font(.title).foregroundStyle(AppStyle.accent)
                                Text("첫 기록부터 시작해 볼까요?").font(.headline)
                                Text("“점심 9000원”처럼 적으면\n금액과 분류를 정리해 드려요.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button("첫 기록 남기기", action: openEntry).buttonStyle(.bordered)
                            }
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(records.prefix(6))) { record in
                                    Button { editing = record } label: { LedgerRow(expense: record) }.buttonStyle(.plain)
                                    if record.persistentModelID != records.prefix(6).last?.persistentModelID { Divider() }
                                }
                            }
                        }
                    }
                    Label("AI 분석은 기기 안에서, 저장은 확인한 뒤에", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 6)
                }.padding(20)
            }
            .background(AppStyle.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { ExpenseEditor(expense: $0) }
            .sheet(isPresented: $showWelcome, onDismiss: { hasSeenWelcome = true }) { WelcomeView(onStart: openEntry) }
            .onAppear { if !hasSeenWelcome { showWelcome = true } }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("이번 달 지출", systemImage: "arrow.up.right").font(.subheadline)
                Spacer()
                Button(action: openCalendar) { Image(systemName: "calendar").padding(8) }
                    .accessibilityLabel("소비 달력 보기")
            }.foregroundStyle(.white.opacity(0.8))
            Text(currencyText(spent))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Divider().overlay(.white.opacity(0.15))
            ViewThatFits(in: .horizontal) {
                HStack {
                    amountLabel("수입", amount: earned, color: .white)
                    Spacer()
                    amountLabel("수입 − 지출", amount: earned - spent, color: .white)
                }
                VStack(alignment: .leading, spacing: 16) {
                    amountLabel("수입", amount: earned, color: .white)
                    amountLabel("수입 − 지출", amount: earned - spent, color: .white)
                }
            }
            if budget > 0 {
                HStack {
                    Text("월 예산").font(.caption)
                    Spacer()
                    Text(spent > budget ? "\(currencyText(spent - budget)) 초과" : "\(currencyText(budget - spent)) 남음")
                        .font(.caption.weight(.medium))
                }.foregroundStyle(.white.opacity(0.85))
                ProgressView(value: min(Double(spent) / Double(budget), 1))
                    .tint(spent > budget ? Color.orange : Color.mint)
            }
            HStack(spacing: 6) {
                Circle().fill(Color.mint).frame(width: 6, height: 6).accessibilityHidden(true)
                Text("오늘 지출 \(currencyText(todaySpent))").font(.caption)
            }.foregroundStyle(.white.opacity(0.8))
        }.foregroundStyle(.white).padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppStyle.hero, in: RoundedRectangle(cornerRadius: 24))
    }
    private func amountLabel(_ title: String, amount: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.7))
            Text(currencyText(amount)).font(.headline).foregroundStyle(color).monospacedDigit()
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
                    Image(systemName: "text.book.closed.fill").font(.system(size: 64)).foregroundStyle(AppStyle.accent)
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
            Image(systemName: icon).font(.title2).foregroundStyle(AppStyle.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
