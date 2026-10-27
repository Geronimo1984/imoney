import Foundation

/// Стратегия досрочного погашения: куда направлять свободные деньги.
enum PayoffStrategy: String, CaseIterable, Identifiable {
    case avalanche, snowball

    var id: String { rawValue }

    var title: String {
        switch self {
        case .avalanche: return "Лавина"
        case .snowball:  return "Снежный ком"
        }
    }

    var explanation: String {
        switch self {
        case .avalanche: return "Сначала долг с самой высокой ставкой. Меньше всего переплата по процентам."
        case .snowball:  return "Сначала самый маленький долг. Долги закрываются быстрее по одному — проще не бросить."
        }
    }
}

struct PayoffPlan {
    var months: Int
    var interest: Decimal
    /// Когда закроется каждый долг, в месяцах от сегодня.
    var closedAfter: [Debt.ID: Int]
    /// false — платежи не покрывают проценты, долг не уменьшается.
    var feasible: Bool

    var debtFreeDate: Date? {
        guard feasible else { return nil }
        return Store.calendar.date(byAdding: .month, value: months, to: Date())
    }
}

enum Payoff {
    /// Помесячная модель: проценты, обязательные платежи, а доплата и платежи закрытых долгов идут в выбранный долг.
    static func simulate(_ debts: [Debt], extra: Decimal, strategy: PayoffStrategy) -> PayoffPlan {
        struct Item { var id: Debt.ID; var balance: Double; var rate: Double; var payment: Double }
        var items = debts.filter { $0.balance > 0 }.map {
            Item(id: $0.id, balance: $0.balance.double, rate: $0.rate / 1200, payment: $0.monthlyPayment.double)
        }
        let budget = items.reduce(0) { $0 + $1.payment } + extra.double
        var closed: [Debt.ID: Int] = [:]
        var interest = 0.0
        var month = 0
        while items.contains(where: { $0.balance > 0.5 }) && month < 600 {
            month += 1
            var pool = budget
            for i in items.indices where items[i].balance > 0.5 {
                let charge = items[i].balance * items[i].rate
                interest += charge
                items[i].balance += charge
                let pay = min(items[i].payment, items[i].balance)
                items[i].balance -= pay
                pool -= pay
            }
            // Остаток бюджета — в долг по стратегии, пока есть деньги
            while pool > 0.5 {
                let open = items.indices.filter { items[$0].balance > 0.5 }
                guard let target = (strategy == .avalanche
                    ? open.max { items[$0].rate < items[$1].rate }
                    : open.min { items[$0].balance < items[$1].balance }) else { break }
                let pay = min(pool, items[target].balance)
                items[target].balance -= pay
                pool -= pay
            }
            for i in items.indices where items[i].balance <= 0.5 && closed[items[i].id] == nil {
                closed[items[i].id] = month
            }
        }
        let feasible = !items.contains { $0.balance > 0.5 }
        return PayoffPlan(months: month, interest: Decimal(interest.rounded()), closedAfter: closed, feasible: feasible)
    }
}
