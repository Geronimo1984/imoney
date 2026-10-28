import Foundation

/// Итоги месяца — как ежемесячные награды в Фитнесе.
struct MonthRecap {
    var month: Date
    var income: Decimal
    var expenses: Decimal
    var saved: Decimal
    var debtPaid: Decimal
    var topCategory: CategoryTotal?
    /// Категория, где траты сильнее всего снизились к прошлому месяцу.
    var bestCut: (Category, Decimal)?
    var daysWithoutSpending: Int
    var operations: Int

    /// Доход минус траты; отложенное в накопления тратой не считается.
    var balance: Decimal { income - (expenses - saved) }
}

extension Store {
    func recap(for m: Date) -> MonthRecap {
        let cal = Store.calendar
        let s = Analytics.stats(transactions, month: m)
        // Месяц ещё идёт — сравниваем с тем же числом дней прошлого месяца, а не со всем месяцем
        let today = Analytics.isCurrent(m) ? cal.component(.day, from: Date()) : nil
        let prev = Analytics.stats(transactions, month: cal.date(byAdding: .month, value: -1, to: m) ?? m, upToDay: today)
        var best: (Category, Decimal)?
        for item in prev.byCategory where item.category != .transfersOut {
            let now = s.byCategory.first { $0.category == item.category }?.amount ?? 0
            let cut = item.amount - now
            if cut > 500, cut > (best?.1 ?? 0) { best = (item.category, cut) }
        }
        let items = Analytics.inMonth(transactions, m)
        let spendDays = Set(items.filter { $0.category.isExpense && $0.amount < 0 }.map { cal.component(.day, from: $0.date) })
        let days = Analytics.isCurrent(m) ? cal.component(.day, from: Date()) : (cal.range(of: .day, in: .month, for: m)?.count ?? 30)
        return MonthRecap(month: m, income: s.income, expenses: s.expenses,
                          saved: s.byCategory.first { $0.category == .savings }?.amount ?? 0,
                          debtPaid: s.byCategory.first { $0.category == .loans }?.amount ?? 0,
                          topCategory: s.byCategory.first { $0.category != .transfersOut },
                          bestCut: best,
                          daysWithoutSpending: max(days - spendDays.count, 0),
                          operations: items.count)
    }
}
