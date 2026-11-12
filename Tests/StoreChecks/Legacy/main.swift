import Foundation
import SwiftData

// Frozen schema from the first shipped-to-device development build.
@Model final class Expense {
    var amount: Int
    var category: String
    var memo: String
    var date: Date
    var createdAt: Date
    var isAiClassified: Bool
    init() {
        amount = 6500; category = "카페"; memo = "이전 버전 기록"
        date = Date(timeIntervalSince1970: 1_790_000_000)
        createdAt = Date(timeIntervalSince1970: 1_790_000_000); isAiClassified = true
    }
}
@MainActor func createFixture() throws {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let container = try ModelContainer(for: Expense.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
    let context = ModelContext(container)
    context.insert(Expense())
    try context.save()
    print("Legacy store created with one original-schema record")
}
try MainActor.assumeIsolated { try createFixture() }
