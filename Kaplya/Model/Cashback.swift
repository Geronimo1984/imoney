import Foundation

/// Кэшбэк по факту: поступления из выписок с категорией «Кэшбэк и проценты».
/// Условия банков часто меняются, поэтому ничего не планируем — только считаем, сколько пришло.
enum CashbackKind: String, CaseIterable, Identifiable {
    case cashback, interest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cashback: return "Кэшбэк и бонусы"
        case .interest: return "Проценты на остаток"
        }
    }

    var symbol: String {
        switch self {
        case .cashback: return "arrow.uturn.backward.circle.fill"
        case .interest: return "percent"
        }
    }

    /// Проценты по вкладу или накопительному счёту узнаём по названию, остальное — кэшбэк.
    static func of(_ t: Transaction) -> CashbackKind {
        let text = (t.title + " " + t.bankCategory).lowercased()
        return ["процент", "капитализац", "вклад", "накопит"].contains(where: text.contains) ? .interest : .cashback
    }
}

struct CashbackMonth: Identifiable {
    var month: Date
    var byKind: [CashbackKind: Decimal]
    var total: Decimal { byKind.values.reduce(0, +) }
    var id: Date { month }
}

struct CashbackReport {
    var month: CashbackMonth
    var byBank: [(bank: Bank, amount: Decimal)]
    /// Последние 12 месяцев, новые сверху; пустые месяцы в начале истории пропущены.
    var history: [CashbackMonth]
    var yearTotal: Decimal
    var transactions: [Transaction]
}

extension Store {
    private func cashbackMonth(_ month: Date) -> (CashbackMonth, [Transaction]) {
        let items = transactions.filter {
            ($0.category == .cashback) && ($0.amount > 0) && (Store.startOfMonth($0.date) == month)
        }
        var byKind: [CashbackKind: Decimal] = [:]
        for t in items { byKind[CashbackKind.of(t), default: 0] += t.amount }
        return (CashbackMonth(month: month, byKind: byKind), items.sorted { $0.date > $1.date })
    }

    func cashbackReport() -> CashbackReport {
        let (current, items) = cashbackMonth(month)
        var byBank: [Bank: Decimal] = [:]
        for t in items { byBank[t.bank, default: 0] += t.amount }

        var history = (0..<12).compactMap { Store.calendar.date(byAdding: .month, value: -$0, to: month) }
            .map { cashbackMonth($0).0 }
        while let last = history.last, last.total == 0 { history.removeLast() }

        return CashbackReport(month: current,
                              byBank: byBank.sorted { $0.value > $1.value }.map { ($0.key, $0.value) },
                              history: history,
                              yearTotal: history.reduce(0) { $0 + $1.total },
                              transactions: items)
    }
}
