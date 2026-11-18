import SwiftData

@MainActor enum LedgerStore {
    private static var container: ModelContainer?
    static func open() throws -> ModelContainer {
        if let container { return container }
        let opened = try ModelContainer(for: Expense.self, configurations: ModelConfiguration(cloudKitDatabase: .none))
        container = opened
        return opened
    }
}
