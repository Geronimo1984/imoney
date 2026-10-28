import Foundation

/// Как часто повторяется платёж.
enum Period: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, quarterly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly:    return "Каждую неделю"
        case .monthly:   return "Каждый месяц"
        case .quarterly: return "Раз в квартал"
        case .yearly:    return "Раз в год"
        }
    }

    /// Во сколько платёж обходится в месяц.
    func perMonth(_ amount: Decimal) -> Decimal {
        switch self {
        case .weekly:    return amount * 52 / 12
        case .monthly:   return amount
        case .quarterly: return amount / 3
        case .yearly:    return amount / 12
        }
    }

    func step(_ date: Date) -> Date {
        let cal = Store.calendar
        switch self {
        case .weekly:    return cal.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly:   return cal.date(byAdding: .month, value: 1, to: date) ?? date
        case .quarterly: return cal.date(byAdding: .month, value: 3, to: date) ?? date
        case .yearly:    return cal.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
}

/// Регулярный платёж: аренда, связь, подписки, кредит.
struct RecurringPayment: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var amount: Decimal
    var category: Category
    var period: Period = .monthly
    /// Дата, с которой отсчитывается график платежей.
    var startDate: Date
    /// Получатель в выписках — по нему видно, что платёж уже прошёл.
    var match: String = ""

    var monthly: Decimal { period.perMonth(amount) }

    /// Ближайший платёж начиная с сегодняшнего дня.
    func nextDate(from today: Date = Date()) -> Date {
        let day = Store.calendar.startOfDay(for: today)
        var d = startDate
        var guardSteps = 0
        while d < day && guardSteps < 1000 {
            d = period.step(d)
            guardSteps += 1
        }
        return d
    }

    /// Был ли платёж в этом месяце — ищем операцию этого получателя на похожую сумму.
    func isPaid(in month: Date, transactions: [Transaction]) -> Bool {
        guard !match.isEmpty else { return false }
        return transactions.contains { t in
            Store.calendar.isDate(t.date, equalTo: month, toGranularity: .month)
                && (t.amount < 0)
                && t.counterparty.contains(match)
                && (abs((t.absAmount - amount).double) <= amount.double * 0.15)
        }
    }
}

/// Лимит трат на месяц по категории.
struct BudgetLimit: Codable, Identifiable, Hashable {
    var category: Category
    var amount: Decimal
    var id: Category { category }
}

/// План распределения дохода.
struct IncomePlan: Codable, Hashable {
    /// Ожидаемый доход; если не задан — берём фактический доход месяца.
    var expectedIncome: Decimal?
    /// Сколько откладывать в месяц.
    var savings: Decimal = 0
}

/// Сводка плана на месяц: куда распределён доход и сколько осталось.
struct PlanSummary {
    var income: Decimal
    var incomeIsExpected: Bool
    var recurring: Decimal
    var debts: Decimal
    var limits: Decimal
    var savings: Decimal
    /// Разовые расходы этого месяца.
    var planned: Decimal = 0

    var allocated: Decimal { recurring + debts + limits + savings + planned }
    /// Долговая нагрузка: доля дохода, которая уходит на платежи по кредитам.
    var debtLoad: Double { income > 0 ? (debts / income).double : 0 }
    var free: Decimal { income - allocated }
}

extension Store {
    func planSummary() -> PlanSummary {
        let actual = Analytics.stats(transactions, month: month).income
        let income = incomePlan.expectedIncome ?? (actual > 0 ? actual : averageIncome())
        return PlanSummary(income: income,
                           incomeIsExpected: incomePlan.expectedIncome != nil,
                           recurring: recurring.reduce(0) { $0 + $1.monthly },
                           debts: debtsMonthly,
                           limits: limits.reduce(0) { $0 + $1.amount },
                           savings: incomePlan.savings,
                           planned: planned(in: month).reduce(0) { $0 + $1.amount })
    }

    /// Средний доход за последние три месяца с данными.
    func averageIncome() -> Decimal {
        let incomes = (1...3).compactMap { Store.calendar.date(byAdding: .month, value: -$0, to: month) }
            .map { Analytics.stats(transactions, month: $0).income }
            .filter { $0 > 0 }
        guard !incomes.isEmpty else { return 0 }
        return incomes.reduce(0, +) / Decimal(incomes.count)
    }

    // MARK: Правка плана

    func saveRecurring(_ payment: RecurringPayment) {
        if let i = recurring.firstIndex(where: { $0.id == payment.id }) {
            recurring[i] = payment
        } else {
            recurring.append(payment)
        }
        recurring.sort { $0.nextDate() < $1.nextDate() }
        save()
    }

    func deleteRecurring(_ id: RecurringPayment.ID) {
        recurring.removeAll { $0.id == id }
        save()
    }

    func setLimit(_ category: Category, _ amount: Decimal?) {
        limits.removeAll { $0.category == category }
        if let amount, amount > 0 { limits.append(BudgetLimit(category: category, amount: amount)) }
        limits.sort { $0.amount > $1.amount }
        save()
    }

    func setSavings(_ amount: Decimal) {
        incomePlan.savings = max(amount, 0)
        save()
    }

    func setExpectedIncome(_ amount: Decimal?) {
        incomePlan.expectedIncome = amount
        save()
    }

    // MARK: Подсказки

    /// Похожие на регулярные платежи из выписок, которых ещё нет в списке:
    /// один получатель, раз в месяц минимум два месяца подряд, сумма почти не меняется.
    func suggestedRecurring() -> [RecurringPayment] {
        let cal = Store.calendar
        let known = Set(recurring.map(\.match))
        // Накопления — в своём разделе плана, а не в регулярных платежах
        let candidates = transactions.filter { ($0.amount < 0) && $0.category.isExpense && ($0.category != .groceries) && ($0.category != .savings) && ($0.category != .loans) }
        var result: [RecurringPayment] = []
        for (name, items) in Dictionary(grouping: candidates, by: \.counterparty) where !name.isEmpty && !known.contains(name) {
            let byMonth = Dictionary(grouping: items) { cal.dateComponents([.year, .month], from: $0.date) }
            guard byMonth.count >= 2, byMonth.values.allSatisfy({ $0.count == 1 }) else { continue }
            let amounts = items.map(\.absAmount.double)
            guard let lo = amounts.min(), let hi = amounts.max(), hi <= lo * 1.15 else { continue }
            let latest = items.max { $0.date < $1.date }!
            guard Date().timeIntervalSince(latest.date) < 45 * 86_400 else { continue }
            result.append(RecurringPayment(title: latest.title, amount: latest.absAmount, category: latest.category,
                                           period: .monthly, startDate: latest.date, match: name))
        }
        return result.sorted { $0.amount > $1.amount }
    }

    /// Предлагаемый план: 20% дохода в накопления, лимиты — по средним тратам за три месяца,
    /// без категорий, которые уже покрыты регулярными платежами. Если не влезает в доход — лимиты ужимаются.
    func suggestedPlan() -> (limits: [BudgetLimit], savings: Decimal) {
        let summary = planSummary()
        let savings = roundUp((summary.income * Decimal(0.2)), to: 1000)
        // Регулярные платежи и кредиты уже в плане — их категории лимитами не дублируем
        let covered = Set(recurring.map(\.category)).union([.loans])
        let months = (1...3).compactMap { Store.calendar.date(byAdding: .month, value: -$0, to: month) }
            .map { Analytics.stats(transactions, month: $0) }
            .filter { $0.expenses > 0 }
        guard !months.isEmpty else { return ([], savings) }

        var averages: [Category: Decimal] = [:]
        for s in months {
            // Переводы людям и накопления в лимиты не идут: у накоплений свой раздел плана
            for item in s.byCategory where !covered.contains(item.category) && (item.category != .transfersOut) && (item.category != .savings) {
                averages[item.category, default: 0] += item.amount / Decimal(months.count)
            }
        }
        var limits = averages
            .filter { $0.value >= 1000 }
            .map { BudgetLimit(category: $0.key, amount: roundUp($0.value, to: 500)) }
            .sorted { $0.amount > $1.amount }
        let room = summary.income - summary.recurring - summary.debts - savings
        let total = limits.reduce(Decimal(0)) { $0 + $1.amount }
        if total > room, room > 0 {
            let k = room / total
            limits = limits.map { BudgetLimit(category: $0.category, amount: roundDown($0.amount * k, to: 500)) }
                .filter { $0.amount > 0 }
        }
        return (Array(limits.prefix(8)), savings)
    }

    func applySuggestedPlan() {
        let plan = suggestedPlan()
        limits = plan.limits
        incomePlan.savings = plan.savings
        save()
    }

    private func roundUp(_ value: Decimal, to step: Decimal) -> Decimal {
        let v = (value / step).double.rounded(.up)
        return Decimal(v) * step
    }

    private func roundDown(_ value: Decimal, to step: Decimal) -> Decimal {
        let v = (value / step).double.rounded(.down)
        return Decimal(v) * step
    }
}
