import SwiftUI

// Semantic system surfaces keep contrast and Dark Mode consistent.
enum AppStyle {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.84, blue: 0.73, alpha: 1)
            : UIColor(red: 0.02, green: 0.43, blue: 0.38, alpha: 1)
    })
    static let hero = Color(red: 0.02, green: 0.43, blue: 0.38)
    static let income = Color.blue
    static let expense = Color.primary
    static let canvas = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let radius: CGFloat = 24
}

struct LedgerCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: AppStyle.radius))
    }
}

struct CategoryBadge: View {
    let category: String
    var body: some View {
        let item = ExpenseCategory(rawValue: category) ?? .other
        Image(systemName: item.icon)
            .font(.body.weight(.semibold))
            .foregroundStyle(item.kind == .income ? AppStyle.income : AppStyle.accent)
            .frame(width: 42, height: 42)
            .background((item.kind == .income ? AppStyle.income : AppStyle.accent).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

func currencyText(_ amount: Int) -> String {
    amount.formatted(.currency(code: "KRW").precision(.fractionLength(0)))
}

struct LedgerRow: View {
    let expense: Expense
    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: expense.category)
            VStack(alignment: .leading, spacing: 5) {
                Text(expense.memo).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("\(expense.category) · \(expense.date.formatted(.dateTime.month().day()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text((expense.kind == .income ? "+" : "−") + currencyText(expense.amount))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(expense.kind == .income ? AppStyle.income : AppStyle.expense)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(expense.kind.title).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}
