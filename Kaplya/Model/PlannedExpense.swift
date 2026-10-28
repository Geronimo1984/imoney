import Foundation

/// Разовый плановый расход на определённую дату: отпуск, подарок, страховка, ремонт.
struct PlannedExpense: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var amount: Decimal
    var category: Category
    var date: Date
    /// Отмечен оплаченным вручную — если в выписке его не узнать.
    var done = false

    /// Оплачен: отмечен вручную или в выписке рядом с датой есть трата этой категории на похожую сумму
    /// либо получателю с таким же названием.
    func isPaid(transactions: [Transaction]) -> Bool {
        if done { return true }
        let cal = Store.calendar
        guard let from = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: date)),
              let to = cal.date(byAdding: .day, value: 8, to: cal.startOfDay(for: date)) else { return false }
        let name = Transaction.normalize(title)
        return transactions.contains { t in
            (t.amount < 0) && (t.date >= from) && (t.date < to)
                && (((t.category == category) && (abs((t.absAmount - amount).double) <= amount.double * 0.1))
                    || (!name.isEmpty && t.counterparty.contains(name)))
        }
    }
}

extension Store {
    /// Разовые расходы выбранного месяца и позже — прошедшие месяцы в плане не показываем.
    var upcomingPlanned: [PlannedExpense] {
        planned.filter { $0.date >= month }.sorted { $0.date < $1.date }
    }

    func planned(in month: Date) -> [PlannedExpense] {
        planned.filter { Store.startOfMonth($0.date) == month }
    }

    /// Сколько ещё отложить до конца текущего месяца на неоплаченные разовые расходы.
    /// Дата прошла, а оплаты в выписке нет — деньги всё равно держим: как и обещает подпись в плане,
    /// сумма откладывается, пока расход не оплачен или не отмечен оплаченным.
    func plannedReserve(now: Date = Date()) -> Decimal {
        planned(in: Store.startOfMonth(now))
            .filter { !$0.isPaid(transactions: transactions) }
            .reduce(0) { $0 + $1.amount }
    }

    /// Прогноз месяца с учётом разовых расходов, которые ещё впереди.
    func forecast(now: Date = Date()) -> Forecast? {
        Analytics.forecast(transactions, month: month, now: now, reserved: plannedReserve(now: now))
    }

    func savePlanned(_ expense: PlannedExpense) {
        if let i = planned.firstIndex(where: { $0.id == expense.id }) {
            planned[i] = expense
        } else {
            planned.append(expense)
        }
        planned.sort { $0.date < $1.date }
        save()
    }

    func deletePlanned(_ id: PlannedExpense.ID) {
        planned.removeAll { $0.id == id }
        save()
    }

    func togglePlannedDone(_ id: PlannedExpense.ID) {
        guard let i = planned.firstIndex(where: { $0.id == id }) else { return }
        planned[i].done.toggle()
        save()
    }
}
