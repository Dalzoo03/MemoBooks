import SwiftUI
import SwiftData

enum AppTab: Hashable { case home, calendar, history, settings }

@main
struct MemoBooksApp: App {
    @State private var selectedTab = AppTab.calendar
    @State private var container: ModelContainer?
    @State private var storageFailed = false
    init() {
        _ = WatchInbox.shared
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            UserDefaults.standard.set(800000, forKey: "monthlyExpenseBudget")
            let tabs: [String: AppTab] = ["home": .home, "entry": .calendar, "calendar": .calendar, "history": .history, "settings": .settings]
            let tab = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--tab=") }?.replacingOccurrences(of: "--tab=", with: "") ?? "calendar"
            _selectedTab = State(initialValue: tabs[tab] ?? .calendar)
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    TabView(selection: $selectedTab) {
                        Tab("홈", systemImage: "house", value: .calendar) { CalendarView() }
                        Tab("내역", systemImage: "list.bullet.rectangle", value: .history) { HistoryView() }
                        Tab("요약", systemImage: "chart.bar.xaxis", value: .home) {
                            HomeView(openEntry: { selectedTab = .calendar }, openCalendar: { selectedTab = .calendar },
                                     openHistory: { selectedTab = .history })
                        }
                        Tab("설정", systemImage: "gearshape", value: .settings) { SettingsView() }
                    }
                    .tint(AppStyle.accent)
                    .modelContainer(container)
                } else if storageFailed {
                    ContentUnavailableView {
                        Label("기록을 열지 못했어요", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("앱을 삭제하지 말고 기기의 저장 공간을 확인한 뒤 다시 시도해 주세요. 기존 데이터를 자동으로 지우지 않아요.")
                    } actions: {
                        Button("다시 시도") { openStorage() }.buttonStyle(.borderedProminent)
                    }
                } else { ProgressView("기록을 불러오는 중") }
            }
            .task { if container == nil && !storageFailed { openStorage() } }

        }
    }
    private func openStorage() {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo") {
                let demo = try ModelContainer(for: Expense.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
                let calendar = Calendar.current
                for (offset, amount, category, memo, kind) in [
                    (0, 9000, "식비", "점심 김치찌개", TransactionKind.expense),
                    (0, 4500, "카페", "오후 아이스라테", .expense),
                    (-1, 1500, "교통", "퇴근 버스", .expense),
                    (-2, 32000, "쇼핑", "주말 장보기", .expense),
                    (-3, 15000, "문화", "영화 한 편", .expense),
                    (-4, 3000000, "급여", "11월 급여", .income)
                ] {
                    let date = calendar.date(byAdding: .day, value: offset, to: .now)!
                    demo.mainContext.insert(Expense(amount: amount, category: category, memo: memo, date: date, isAiClassified: false, kind: kind))
                }
                try demo.mainContext.save()
                container = demo
                storageFailed = false
                return
            }
            #endif
            container = try LedgerStore.open()
            storageFailed = false
        } catch { storageFailed = true }
    }
}
