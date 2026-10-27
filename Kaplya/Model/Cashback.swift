import Foundation

/// Карта с кэшбэком: базовый процент и повышенные категории (у Т-Банка они меняются каждый месяц).
struct CashbackCard: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var bank: Bank
    var base: Double = 1
    var rates: [Category: Double] = [:]

    func rate(for category: Category) -> Double { rates[category] ?? base }
}

/// Какой картой платить в категории и сколько это даёт.
struct CashbackTip: Identifiable {
    var category: Category
    var spent: Decimal
    var card: CashbackCard
    var rate: Double
    var id: Category { category }
}

struct CashbackReport {
    var earned: Decimal
    var missed: Decimal
    var tips: [CashbackTip]
}

extension Store {
    /// Категории, где кэшбэк обычно не начисляется.
    private static let noCashback: Set<Category> = [.transfersOut, .internalTransfer, .loans, .savings, .cash, .taxes, .housing]

    func saveCashbackCard(_ card: CashbackCard) {
        if let i = cashbackCards.firstIndex(where: { $0.id == card.id }) {
            cashbackCards[i] = card
        } else {
            cashbackCards.append(card)
        }
        save()
    }

    func deleteCashbackCard(_ id: CashbackCard.ID) {
        cashbackCards.removeAll { $0.id == id }
        save()
    }

    func bestCard(for category: Category) -> CashbackCard? {
        cashbackCards.max { $0.rate(for: category) < $1.rate(for: category) }
    }

    /// Кэшбэк за месяц: сколько получено по картам, которыми платили, и сколько недополучено.
    func cashbackReport() -> CashbackReport {
        guard !cashbackCards.isEmpty else { return CashbackReport(earned: 0, missed: 0, tips: []) }
        var earned = Decimal(0), best = Decimal(0)
        for t in monthTransactions where t.amount < 0 && t.category.isExpense && !Store.noCashback.contains(t.category) {
            let actual = cashbackCards.first { $0.bank == t.bank }?.rate(for: t.category) ?? 0
            let top = bestCard(for: t.category)?.rate(for: t.category) ?? 0
            earned += t.absAmount * Decimal(actual / 100)
            best += t.absAmount * Decimal(top / 100)
        }
        let stats = Analytics.stats(transactions, month: month)
        let tips = stats.byCategory
            .filter { !Store.noCashback.contains($0.category) }
            .prefix(8)
            .compactMap { item -> CashbackTip? in
                guard let card = bestCard(for: item.category) else { return nil }
                return CashbackTip(category: item.category, spent: item.amount, card: card, rate: card.rate(for: item.category))
            }
        return CashbackReport(earned: earned, missed: max(best - earned, 0), tips: tips)
    }
}
