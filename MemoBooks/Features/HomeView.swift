import SwiftUI
import SwiftData

// Financial totals stay deterministic; this screen does not present generated advice.
struct HomeView: View {
    @Query(sort: \Expense.date, order: .reverse) private var records: [Expense]
    @AppStorage("monthlyExpenseBudget") private var budget = 0
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
    private var categories: [(name: String, amount: Int)] {
        Dictionary(grouping: month.filter { $0.kind == .expense }, by: \Expense.category)
            .map { (name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        OwlMark(); Text("소비 요약").font(.title2.bold())
                        Spacer()
                        Text(Date.now, format: .dateTime.month()).font(.caption.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 6).background(AppStyle.mintSurface, in: Capsule())
                    }
                    LedgerCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("이번 달 지출").font(.subheadline).foregroundStyle(.secondary)
                            Text(currencyText(spent)).font(.largeTitle.bold()).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Divider()
                            ViewThatFits(in: .horizontal) {
                                HStack { totals }
                                VStack(alignment: .leading, spacing: 16) { totals }
                            }
                            if budget > 0 {
                                Divider()
                                LabeledContent("월 예산", value: currencyText(budget)).font(.caption)
                                Text(spent > budget ? "\(currencyText(spent - budget)) 초과" : "\(currencyText(budget - spent)) 남음")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(spent > budget ? AppStyle.apricot : AppStyle.accent)
                                ProgressView(value: min(Double(spent) / Double(budget), 1)).tint(AppStyle.accent)
                            }
                        }
                    }
                    LedgerCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("카테고리별 소비 패턴", systemImage: "chart.bar.xaxis").font(.headline)
                            if categories.isEmpty { Text("기록을 남기면 소비 패턴을 볼 수 있어요").font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(categories, id: \.name) { item in
                                VStack(spacing: 8) {
                                    HStack {
                                        Text(item.name).font(.subheadline.weight(.medium))
                                        Spacer()
                                        Text("\(currencyText(item.amount)) · \(spent > 0 ? Int(Double(item.amount) / Double(spent) * 100) : 0)%")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    ProgressView(value: spent > 0 ? Double(item.amount) / Double(spent) : 0)
                                        .tint(AppStyle.categoryColor(item.name))
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        OwlMark(size: 40)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("이번 달 기록 돌아보기").font(.headline)
                            Text(categories.first.map { "지출 금액이 가장 큰 분류는 \($0.name)이에요. 이번 달 수입과 지출 \(month.count)건을 남겼어요." } ?? "작은 기록부터 차근차근 모아 보세요.")
                                .font(.subheadline)
                            Text("저장한 기록을 바탕으로 앱에서 계산한 요약이에요")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppStyle.lavenderSurface, in: RoundedRectangle(cornerRadius: 24))
                    Button("달력에서 기록하기", action: openEntry).buttonStyle(OwlPillStyle())
                    Button("전체 내역 보기", action: openHistory).frame(maxWidth: .infinity, minHeight: 44)
                }.padding(16)
            }.background(AppStyle.canvas).toolbar(.hidden, for: .navigationBar)
        }
    }
    @ViewBuilder private var totals: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("이번 달 수입").font(.caption).foregroundStyle(.secondary)
            Text(currencyText(earned)).font(.headline).foregroundStyle(AppStyle.income)
        }.frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .leading, spacing: 6) {
            Text("수입 − 지출 차액").font(.caption).foregroundStyle(.secondary)
            Text(currencyText(earned - spent)).font(.headline)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
