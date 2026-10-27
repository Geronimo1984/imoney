import SwiftUI

/// Вид долга.
enum DebtKind: String, Codable, CaseIterable, Identifiable {
    case loan, mortgage, carLoan, installment, creditCard, personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loan:        return "Кредит"
        case .mortgage:    return "Ипотека"
        case .carLoan:     return "Автокредит"
        case .installment: return "Рассрочка"
        case .creditCard:  return "Кредитная карта"
        case .personal:    return "Долг человеку"
        }
    }

    var symbol: String {
        switch self {
        case .loan:        return "banknote.fill"
        case .mortgage:    return "house.fill"
        case .carLoan:     return "car.fill"
        case .installment: return "calendar.badge.clock"
        case .creditCard:  return "creditcard.fill"
        case .personal:    return "person.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .loan:        return .red
        case .mortgage:    return .teal
        case .carLoan:     return .indigo
        case .installment: return .purple
        case .creditCard:  return .orange
        case .personal:    return .gray
        }
    }
}

/// Действующий долг: кредит, ипотека, рассрочка, кредитная карта.
struct Debt: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: DebtKind
    var title: String
    var lender: String = ""
    /// Сколько взято изначально.
    var principal: Decimal
    /// Сколько осталось выплатить по телу долга.
    var balance: Decimal
    var monthlyPayment: Decimal
    /// Ставка, % годовых. У рассрочки — 0.
    var rate: Double = 0
    var nextPayment: Date
    /// Получатель платежа в выписках — по нему видно, что платёж уже прошёл.
    var match: String = ""
    /// Кредитная карта: до какого дня длится льготный период (без процентов).
    var graceEnds: Date? = nil

    var isCard: Bool { kind == .creditCard }

    /// У кредитной карты `principal` — это кредитный лимит.
    var creditLimit: Decimal { principal }
    var available: Decimal { max(creditLimit - balance, 0) }

    /// Доля кольца: у кредита — сколько выплачено, у карты — сколько лимита использовано.
    var ringShare: Double {
        guard principal > 0 else { return 0 }
        let used = min(max((balance / principal).double, 0), 1)
        return isCard ? used : 1 - used
    }

    /// Льготный период ещё идёт: если погасить весь долг до этой даты, проценты не начислятся.
    var graceActive: Bool {
        guard isCard, let graceEnds, balance > 0 else { return false }
        return graceEnds >= Store.calendar.startOfDay(for: Date())
    }

    /// Сколько процентов набежит за месяц, если платить только минимальный платёж.
    var monthlyInterest: Decimal {
        guard rate > 0 else { return 0 }
        return balance * Decimal(rate / 100 / 12)
    }

    /// Сколько ещё ежемесячных платежей. nil — при такой ставке платёж не покрывает проценты.
    var paymentsLeft: Int? {
        let b = balance.double, p = monthlyPayment.double
        guard b > 0 else { return 0 }
        guard p > 0 else { return nil }
        let r = rate / 12 / 100
        if r <= 0 { return Int((b / p).rounded(.up)) }
        let x = 1 - r * b / p
        guard x > 0 else { return nil }
        return Int((-log(x) / log(1 + r)).rounded(.up))
    }

    /// Ближайший платёж начиная с сегодняшнего дня.
    func upcomingPayment(from today: Date = Date()) -> Date {
        let day = Store.calendar.startOfDay(for: today)
        var d = nextPayment
        var steps = 0
        while d < day && steps < 600 {
            d = Store.calendar.date(byAdding: .month, value: 1, to: d) ?? d
            steps += 1
        }
        return d
    }

    /// Когда долг закроется при нынешнем платеже.
    var payoffDate: Date? {
        guard let n = paymentsLeft, n > 0 else { return nil }
        return Store.calendar.date(byAdding: .month, value: n - 1, to: upcomingPayment())
    }

    /// Сколько ещё уйдёт на проценты сверх остатка долга.
    var interestLeft: Decimal {
        guard let n = paymentsLeft else { return 0 }
        return max(monthlyPayment * Decimal(n) - balance, 0)
    }

    /// Платежи по этому долгу в выписках.
    func payments(in transactions: [Transaction]) -> [Transaction] {
        guard !match.isEmpty else { return [] }
        return transactions.filter { ($0.amount < 0) && $0.counterparty.contains(match) }
    }

    /// Подпись строки: что осталось и когда закроется; у карты — долг, лимит и льготный период.
    var summary: String {
        if isCard {
            var s = "Долг \(Fmt.money(balance)) из \(Fmt.money(creditLimit))"
            if graceActive, let graceEnds { s += " · без процентов до \(graceEnds.formatted(.dateTime.day().month(.wide)))" }
            return s
        }
        var s = "Осталось \(Fmt.money(balance))"
        if let date = payoffDate { s += " · до \(Fmt.monthGenitive(date))" }
        return s
    }

    func isPaid(in month: Date, transactions: [Transaction]) -> Bool {
        payments(in: transactions).contains { Store.calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
}

extension Store {
    /// Платежи, срок которых прошёл, уменьшают остаток: начисляем проценты месяца и вычитаем платёж.
    /// У кредитной карты долг меняется от покупок, поэтому её не трогаем — только переносим дату платежа.
    func rollDebts(today: Date = Date()) {
        let day = Store.calendar.startOfDay(for: today)
        var changed = false
        for i in debts.indices {
            var steps = 0
            while debts[i].nextPayment < day && steps < 600 {
                if !debts[i].isCard && debts[i].balance > 0 {
                    let interest = debts[i].balance * Decimal(debts[i].rate / 1200)
                    debts[i].balance = max(debts[i].balance + interest - debts[i].monthlyPayment, 0)
                }
                debts[i].nextPayment = Store.calendar.date(byAdding: .month, value: 1, to: debts[i].nextPayment) ?? day
                steps += 1
                changed = true
            }
        }
        if changed { save() }
    }

    var debtsMonthly: Decimal { debts.reduce(0) { $0 + $1.monthlyPayment } }
    var debtsTotal: Decimal { debts.reduce(0) { $0 + $1.balance } }

    func saveDebt(_ debt: Debt) {
        if let i = debts.firstIndex(where: { $0.id == debt.id }) {
            debts[i] = debt
        } else {
            debts.append(debt)
        }
        debts.sort { $0.upcomingPayment() < $1.upcomingPayment() }
        save()
    }

    func deleteDebt(_ id: Debt.ID) {
        debts.removeAll { $0.id == id }
        save()
    }

    /// Похожие на платежи по кредитам операции из выписок, которых ещё нет в списке долгов.
    func suggestedDebts() -> [Debt] {
        let cal = Store.calendar
        let known = Set(debts.map(\.match))
        let candidates = transactions.filter { ($0.amount < 0) && ($0.category == .loans) }
        var result: [Debt] = []
        for (name, items) in Dictionary(grouping: candidates, by: \.counterparty) where !name.isEmpty && !known.contains(name) {
            let months = Set(items.map { cal.dateComponents([.year, .month], from: $0.date) })
            guard months.count >= 2, let latest = items.max(by: { $0.date < $1.date }) else { continue }
            let kind: DebtKind = ["рассрочк", "долями", "сплит", "split"].contains(where: name.contains) ? .installment : .loan
            result.append(Debt(kind: kind, title: latest.title, lender: latest.bank.title,
                               principal: 0, balance: 0, monthlyPayment: latest.absAmount,
                               nextPayment: cal.date(byAdding: .month, value: 1, to: latest.date) ?? latest.date,
                               match: name))
        }
        return result.sorted { $0.monthlyPayment > $1.monthlyPayment }
    }
}
