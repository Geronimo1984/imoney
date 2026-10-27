import SwiftUI

/// Интерфейс по правилам Apple (HIG): системные вкладки, списки, листы и цвета.
struct RootView: View {
    @State private var tab: String

    init(startTab: String? = nil) {
        let arg = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-tab=") }
        _tab = State(initialValue: startTab ?? arg.map { String($0.dropFirst(5)) } ?? "summary")
    }

    var body: some View {
        TabView(selection: $tab) {
            SummaryView()
                .tabItem { Label("Сводка", systemImage: "chart.bar.xaxis") }
                .tag("summary")
            OperationsView()
                .tabItem { Label("Операции", systemImage: "list.bullet.rectangle") }
                .tag("operations")
            PlanView()
                .tabItem { Label("План", systemImage: "list.bullet.clipboard") }
                .tag("plan")
            AccountsView()
                .tabItem { Label("Счета", systemImage: "creditcard") }
                .tag("accounts")
        }
    }
}

extension Category {
    /// Системные цвета iOS — как у категорий в Экранном времени и Wallet.
    var systemColor: Color {
        switch self {
        case .groceries:        return .green
        case .cafe:             return .orange
        case .delivery:         return .red
        case .transport:        return .blue
        case .taxi:             return .yellow
        case .car:              return .indigo
        case .housing:          return .teal
        case .telecom:          return .cyan
        case .health:           return .pink
        case .beauty:           return .pink
        case .clothes:          return .purple
        case .home:             return .brown
        case .marketplace:      return .purple
        case .entertainment:    return .mint
        case .subscriptions:    return .red
        case .travel:           return .cyan
        case .education:        return .indigo
        case .kids:             return .orange
        case .pets:             return .brown
        case .gifts:            return .pink
        case .transfersOut:     return .gray
        case .cash:             return .green
        case .loans:            return .red
        case .savings:          return .mint
        case .taxes:            return .gray
        case .otherExpense:     return .gray
        case .salary:           return .green
        case .transfersIn:      return .blue
        case .cashback:         return .yellow
        case .otherIncome:      return .teal
        case .internalTransfer: return .gray
        }
    }
}

/// Значок категории как в Настройках: белый символ на цветном скруглённом квадрате.
struct CategoryBadge: View {
    var category: Category
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.systemColor.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

/// Строка операции — как в списке транзакций Wallet.
struct TransactionRow: View {
    var t: Transaction

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: t.category, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(t.category.title) · \(t.bank.title)")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.exact(t.amount, sign: t.amount > 0))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(t.category.isInternal ? .secondary : (t.amount > 0 ? Color.green : .primary))
                Text(t.date, format: .dateTime.hour().minute())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
