import SwiftUI

/// Подсказка по кредитной карте: можно ли сейчас ею пользоваться и на какую сумму.
struct CardAdvice {
    enum Level { case ok, caution, no }

    var level: Level
    var title: String
    var text: String
    /// Сколько можно потратить по карте и успеть вернуть до конца льготного периода.
    var safeAmount: Decimal
    /// Свободные деньги в месяц: доход минус средние траты.
    var monthlySurplus: Decimal
    /// Сколько процентов набежит в месяц, если долг вместе с покупкой не вернуть вовремя.
    var interestPerMonth: Decimal

    var symbol: String {
        switch level {
        case .ok:      return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .no:      return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch level {
        case .ok:      return .green
        case .caution: return .orange
        case .no:      return .red
        }
    }
}

extension Store {
    /// Средние траты в месяц за три прошлых месяца, без отложенного в накопления.
    func averageSpending() -> Decimal {
        let months = (1...3).compactMap { Store.calendar.date(byAdding: .month, value: -$0, to: month) }
            .map { Analytics.stats(transactions, month: $0) }
            .filter { $0.expenses > 0 }
        if months.isEmpty {
            let s = Analytics.stats(transactions, month: month)
            return s.expenses - (s.byGroup[.savings] ?? 0)
        }
        let total = months.reduce(Decimal(0)) { $0 + $1.expenses - ($1.byGroup[.savings] ?? 0) }
        return total / Decimal(months.count)
    }

    /// Можно ли пользоваться картой с учётом доходов, трат, льготного периода и долговой нагрузки.
    /// purchase — сумма планируемой покупки; 0 — общий совет.
    func cardAdvice(for card: Debt, purchase: Decimal = 0) -> CardAdvice {
        let plan = planSummary()
        let avgIncome = averageIncome()
        let income = incomePlan.expectedIncome ?? (avgIncome > 0 ? avgIncome : plan.income)
        let surplus = income - averageSpending()
        let today = Store.calendar.startOfDay(for: Date())
        let days = card.graceEnds.map { max(Store.calendar.dateComponents([.day], from: today, to: $0).day ?? 0, 0) } ?? 0
        // Сколько свободных денег накопится до конца льготного периода
        let capacity = max(surplus, 0) * Decimal(days) / 30
        let need = card.balance + purchase
        let interest = need * Decimal(card.rate / 100 / 12)
        let safe = roundDown(min(card.available, max(capacity - card.balance, 0)), to: 500)
        let graceText = card.graceEnds.map { $0.formatted(.dateTime.day().month(.wide)) } ?? ""

        func advice(_ level: CardAdvice.Level, _ title: String, _ text: String) -> CardAdvice {
            CardAdvice(level: level, title: title, text: text, safeAmount: card.graceActive ? safe : 0,
                       monthlySurplus: surplus, interestPerMonth: interest)
        }

        if need <= 0 {
            return advice(.ok, "Долга по карте нет",
                          "Пользоваться можно. Чтобы не платить проценты, гасите всю сумму покупок до конца льготного периода.")
        }
        if purchase > card.available {
            return advice(.no, "Не хватит лимита",
                          "Доступно \(Fmt.money(card.available)) из \(Fmt.money(card.creditLimit)).")
        }
        if surplus <= 0 {
            return advice(.no, "Сейчас не стоит",
                          "В среднем траты больше дохода на \(Fmt.money(-surplus)) в месяц — вернуть долг по карте будет не из чего. Начнутся проценты, около \(Fmt.money(interest)) в месяц.")
        }
        if !card.graceActive {
            return advice(.no, "Проценты начисляются сразу",
                          "Льготного периода сейчас нет: на долг \(Fmt.money(need)) набежит около \(Fmt.money(interest)) в месяц. Сначала погасите карту, а потом пользуйтесь ей заново.")
        }
        if need > capacity {
            return advice(.no, "Не успеете вернуть без процентов",
                          "До \(graceText) свободных денег будет около \(Fmt.money(capacity)), а вернуть нужно \(Fmt.money(need)). Иначе проценты — около \(Fmt.money(interest)) в месяц.")
        }
        if (need > capacity * Decimal(0.6)) || (plan.debtLoad > 0.5) {
            let reason = plan.debtLoad > 0.5
                ? "Долговая нагрузка уже \(Int((plan.debtLoad * 100).rounded()))% дохода."
                : "На погашение до \(graceText) уйдёт почти весь свободный остаток — на непредвиденные траты почти ничего не останется."
            return advice(.caution, "Можно, но впритык",
                          "Вернуть \(Fmt.money(need)) до \(graceText) получится. \(reason)")
        }
        return advice(.ok, "Можно пользоваться",
                      "Погасите \(Fmt.money(need)) до \(graceText) — и проценты не начислятся. Свободных денег до этой даты хватает с запасом.")
    }

    private func roundDown(_ value: Decimal, to step: Decimal) -> Decimal {
        Decimal((value / step).double.rounded(.down)) * step
    }
}
