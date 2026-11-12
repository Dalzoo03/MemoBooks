import Foundation
import Darwin

private struct EvaluationCase: Decodable {
    let id: String
    let input: String
    let amount: Int?
    let kind: String?
    let date: String?
    let category: String?
    let requiresReview: Bool?
}
private struct CaseResult: Encodable {
    let id: String
    let input: String
    let seconds: Double
    let passed: Bool
    let amount: Int?
    let kind: String?
    let date: String?
    let category: String?
    let error: String?
}
private struct EvaluationReport: Encodable {
    let generatedAt: Date
    let operatingSystem: String
    let modelStatus: String
    let referenceDate: String
    let timeZone: String
    let passed: Int
    let total: Int
    let results: [CaseResult]
}

@main struct AIEvaluation {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: ai-evaluation cases.json report.json"); exit(64)
        }
        let cases = try JSONDecoder().decode([EvaluationCase].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let service = ExpenseParsingService()
        let status = service.status
        var results: [CaseResult] = []
        // Match the production parser's local date interpretation; record that timezone.
        let reference = DraftValidation.date(from: "2026-11-12")!
        if status.isAvailable {
            for item in cases {
                let start = Date()
                do {
                    let parsed = try await service.parse(item.input, today: reference)
                    let date = DraftValidation.dateText(parsed.date)
                    let passed: Bool
                    if item.requiresReview == true { passed = parsed.draft.amount == nil }
                    else {
                        passed = parsed.draft.amount == item.amount && parsed.kind.rawValue == item.kind
                            && date == item.date && parsed.category.rawValue == item.category
                    }
                    results.append(CaseResult(id: item.id, input: item.input, seconds: Date().timeIntervalSince(start),
                        passed: passed, amount: parsed.draft.amount, kind: parsed.kind.rawValue, date: date,
                        category: parsed.category.rawValue, error: nil))
                    print("\(passed ? "PASS" : "FAIL") \(item.id)")
                } catch {
                    let safeReview: Bool
                    if case ParsingError.needsReview = error { safeReview = item.requiresReview == true }
                    else { safeReview = false }
                    results.append(CaseResult(id: item.id, input: item.input, seconds: Date().timeIntervalSince(start),
                        passed: safeReview, amount: nil, kind: nil, date: nil, category: nil, error: error.localizedDescription))
                    print("\(safeReview ? "PASS (review)" : "FAIL") \(item.id): \(error.localizedDescription)")
                }
            }
        }
        let passed = results.filter(\.passed).count
        let report = EvaluationReport(generatedAt: .now, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            modelStatus: status.message, referenceDate: "2026-11-12", timeZone: TimeZone.current.identifier,
            passed: passed, total: cases.count, results: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        print("\(passed)/\(cases.count) passed. Model: \(status.message)")
        if !status.isAvailable { exit(2) }
        if passed != cases.count { exit(1) }
    }
}
