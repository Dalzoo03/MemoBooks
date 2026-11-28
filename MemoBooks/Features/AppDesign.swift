import SwiftUI

// Stitch OwlLog palette, with native semantic behavior for contrast and appearance.
enum AppStyle {
    static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let accent = color(0x005644, 0x8AD5BD)
    static let primaryFill = Color(red: 0, green: 0.337, blue: 0.267)
    static let hero = primaryFill
    static let income = accent
    static let expense = Color.primary
    static let apricot = color(0x934A29, 0xFFB598)
    static let lavender = color(0x4E4185, 0xCBBEFF)
    static let mintSurface = color(0xE1F5EE, 0x00382C)
    static let apricotSurface = color(0xFFEDE6, 0x581D01)
    static let lavenderSurface = color(0xF2EFFF, 0x322568)
    static let canvas = color(0xFEFCF8, 0x0E1511)
    static let surface = color(0xFFFFFF, 0x1A211D)
    static let inset = color(0xF2F0ED, 0x252B28)
    static let outline = color(0xBEC9C3, 0x3F4945)
    static let radius: CGFloat = 24
    static func categoryColor(_ category: String) -> Color {
        switch ExpenseCategory(rawValue: category) {
        case .food, .cafe, .shopping: apricot
        case .culture, .medical, .housing: lavender
        default: accent
        }
    }
}

struct LedgerCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: AppStyle.radius))
            .overlay(RoundedRectangle(cornerRadius: AppStyle.radius).stroke(AppStyle.outline.opacity(0.45), lineWidth: 0.75))
    }
}

struct OwlMark: View {
    var size: CGFloat = 32
    var body: some View {
        Image("OwlMascot").resizable().scaledToFill()
            .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.35))
            .accessibilityHidden(true)
    }
}

struct OwlPillStyle: ButtonStyle {
    var foreground: Color = AppStyle.accent
    var background: Color = AppStyle.mintSurface
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(foreground).background(background, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct CategoryBadge: View {
    let category: String
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        let item = ExpenseCategory(rawValue: category) ?? .other
        Image(systemName: item.icon)
            .font(.body.weight(.semibold))
            .foregroundStyle(contrast == .increased ? Color.primary : AppStyle.categoryColor(category))
            .frame(width: 42, height: 42)
            .background((AppStyle.categoryColor(category)).opacity(0.10),
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
                Text(expense.memo).font(.body.weight(.medium)).lineLimit(2)
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
        }.padding(.vertical, 9)
    }
}
