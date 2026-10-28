import Foundation
import WidgetKit

/// Готовит снимок для виджета из данных приложения.
enum WidgetBridge {
    static func update(_ store: Store) {
        let cal = Store.calendar
        let now = Date()
        let current = Store.startOfMonth(now)
        let stats = Analytics.stats(store.transactions, month: current)
        let forecast = Analytics.forecast(store.transactions, month: current, reserved: store.plannedReserve(now: now))
        let income = max(stats.income, 1)
        let rings = [
            ((stats.byGroup[.needs] ?? 0) / income).double / 0.5,
            ((stats.byGroup[.wants] ?? 0) / income).double / 0.3,
            (((stats.byGroup[.savings] ?? 0) + max(stats.balance, 0)) / income).double / 0.2
        ]
        let next = store.debts.filter { $0.balance > 0 }.min { $0.upcomingPayment() < $1.upcomingPayment() }
        let days = (cal.range(of: .day, in: .month, for: now)?.count ?? 30) - cal.component(.day, from: now)
        WidgetSnapshot(perDay: forecast?.perDayLeft.double ?? 0,
                       daysLeft: forecast?.daysLeft ?? days,
                       spent: stats.expenses.double, income: stats.income.double, rings: rings,
                       nextPaymentTitle: next?.title, nextPaymentAmount: next?.monthlyPayment.double,
                       nextPaymentDate: next?.upcomingPayment(), updated: now).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
