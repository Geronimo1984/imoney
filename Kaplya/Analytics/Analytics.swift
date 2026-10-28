import SwiftUI

struct CategoryTotal: Identifiable, Hashable {
    var category: Category
    var amount: Decimal
    var count: Int
    var id: Category { category }
}

struct MonthStats {
    var income: Decimal = 0
    var expenses: Decimal = 0
    var byCategory: [CategoryTotal] = []
    var byGroup: [SpendGroup: Decimal] = [:]
    var byBank: [Bank: Decimal] = [:]
    /// Переводы между своими счетами, которые банк посчитал бы расходом.
    var internalVolume: Decimal = 0
    var internalCount = 0

    var balance: Decimal { income - expenses }
}

struct Forecast {
    var spent: Decimal
    var projected: Decimal
    var daysLeft: Int
    /// Сколько можно тратить в день до конца месяца, чтобы уложиться в доход.
    var perDayLeft: Decimal
}

struct Subscription: Identifiable, Hashable {
    var name: String
    var amount: Decimal
    var category: Category
    var months: Int
    var last: Date
    var id: String { name }
}

struct Merchant: Identifiable, Hashable {
    var name: String
    var amount: Decimal
    var count: Int
    var category: Category
    var id: String { name }
}

struct MonthTotal: Identifiable, Hashable {
    var month: Date
    var income: Decimal
    var expenses: Decimal
    var id: Date { month }
}

struct Insight: Identifiable {
    enum Tone { case warning, tip, good }
    var id = UUID()
    var tone: Tone
    var symbol: String
    var title: String
    var text: String
}

/// Период сводки: неделя, месяц или год, и такие же прошлые периоды для сравнения.
struct Span {
    enum Kind: String, CaseIterable, Identifiable {
        case week = "Неделя", month = "Месяц", year = "Год"
        var id: String { rawValue }
    }

    var kind: Kind
    var range: Range<Date>
    /// Три прошлые недели, три прошлых месяца или прошлый год — новые первыми.
    var previous: [Range<Date>]

    /// «за неделю», «за месяц», «за год».
    var forTitle: String {
        switch kind {
        case .week:  return "за неделю"
        case .month: return "за месяц"
        case .year:  return "за год"
        }
    }

    var days: Int { max(Store.calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 1, 1) }
}

enum Analytics {
    static var cal: Calendar { Store.calendar }

    /// Неделя — последние 7 дней с операциями в выбранном месяце, год — 12 месяцев, заканчивая выбранным.
    static func span(_ kind: Span.Kind, month: Date, all: [Transaction]) -> Span {
        let nextMonth = cal.date(byAdding: .month, value: 1, to: month)!
        switch kind {
        case .week:
            let last = all.lazy.map(\.date).filter { ($0 >= month) && ($0 < nextMonth) }.max() ?? month
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last))!
            let start = cal.date(byAdding: .day, value: -7, to: end)!
            let previous = (1...3).map { n in
                cal.date(byAdding: .day, value: -7 * n, to: start)! ..< cal.date(byAdding: .day, value: -7 * (n - 1), to: start)!
            }
            return Span(kind: kind, range: start..<end, previous: previous)
        case .month:
            let previous = (1...3).map { n in
                cal.date(byAdding: .month, value: -n, to: month)! ..< cal.date(byAdding: .month, value: 1 - n, to: month)!
            }
            return Span(kind: kind, range: month..<nextMonth, previous: previous)
        case .year:
            let start = cal.date(byAdding: .month, value: -11, to: month)!
            return Span(kind: kind, range: start..<nextMonth,
                        previous: [cal.date(byAdding: .month, value: -12, to: start)! ..< start])
        }
    }

    static func inMonth(_ txns: [Transaction], _ month: Date, upToDay day: Int? = nil) -> [Transaction] {
        txns.filter {
            guard cal.isDate($0.date, equalTo: month, toGranularity: .month) else { return false }
            guard let day else { return true }
            return cal.component(.day, from: $0.date) <= day
        }
    }

    static func stats(_ all: [Transaction], month: Date, upToDay: Int? = nil) -> MonthStats {
        stats(of: inMonth(all, month, upToDay: upToDay))
    }

    static func stats(_ all: [Transaction], range: Range<Date>) -> MonthStats {
        stats(of: all.filter { range.contains($0.date) })
    }

    private static func stats(of items: [Transaction]) -> MonthStats {
        var s = MonthStats()
        var cats: [Category: (Decimal, Int)] = [:]
        for t in items {
            if t.category.isInternal {
                if t.amount < 0 {
                    s.internalVolume += -t.amount
                    s.internalCount += 1
                }
                continue
            }
            if t.category.isIncome {
                s.income += t.amount
                continue
            }
            let value = t.expenseValue
            s.expenses += value
            cats[t.category, default: (0, 0)].0 += value
            cats[t.category, default: (0, 0)].1 += 1
            s.byGroup[t.category.group, default: 0] += value
            s.byBank[t.bank, default: 0] += value
        }
        s.byCategory = cats
            .map { CategoryTotal(category: $0.key, amount: $0.value.0, count: $0.value.1) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
        return s
    }

    static func isCurrent(_ month: Date, now: Date = Date()) -> Bool {
        cal.isDate(month, equalTo: now, toGranularity: .month)
    }

    /// reserved — разовые расходы, которые ещё впереди в этом месяце: их откладываем из остатка.
    static func forecast(_ all: [Transaction], month: Date, now: Date = Date(), reserved: Decimal = 0) -> Forecast? {
        guard isCurrent(month, now: now) else { return nil }
        let days = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let today = cal.component(.day, from: now)
        let s = stats(all, month: month)
        // Крупные регулярные платежи (аренда, ЖКХ) уже прошли — экстраполируем только ежедневные траты.
        let fixed: Set<Category> = [.housing, .loans, .savings, .telecom, .subscriptions, .taxes]
        let fixedSum = s.byCategory.filter { fixed.contains($0.category) || $0.amount > s.income * 0.2 }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let daily = (s.expenses - fixedSum) / Decimal(max(today, 1))
        let daysLeft = max(days - today, 0)
        let projected = s.expenses + daily * Decimal(daysLeft) + reserved
        let left = s.income - s.expenses - reserved
        // Сегодня тоже можно тратить — иначе в последний день месяца выходило 0
        let perDay = max(left, 0) / Decimal(daysLeft + 1)
        return Forecast(spent: s.expenses, projected: projected, daysLeft: daysLeft, perDayLeft: perDay)
    }

    static func monthlyTotals(_ all: [Transaction], endingAt month: Date, count: Int = 6) -> [MonthTotal] {
        (0..<count).reversed().compactMap { offset in
            guard let m = cal.date(byAdding: .month, value: -offset, to: month) else { return nil }
            let s = stats(all, month: m)
            return MonthTotal(month: m, income: s.income, expenses: s.expenses)
        }
        .drop(while: { ($0.income == 0) && ($0.expenses == 0) })
        .map { $0 }
    }

    /// Повторяющиеся списания у одного получателя с похожей суммой в разные месяцы.
    static func subscriptions(_ all: [Transaction]) -> [Subscription] {
        let candidates = all.filter { $0.amount < 0 && $0.category.isExpense && $0.category != .transfersOut && $0.category != .groceries }
        let groups = Dictionary(grouping: candidates, by: \.counterparty)
        var result: [Subscription] = []
        for (name, items) in groups where !name.isEmpty {
            let months = Set(items.map { cal.dateComponents([.year, .month], from: $0.date) })
            guard months.count >= 2 else { continue }
            let perMonth = Dictionary(grouping: items) { cal.dateComponents([.year, .month], from: $0.date) }
            guard perMonth.values.allSatisfy({ $0.count == 1 }) else { continue }
            let amounts = items.map(\.absAmount.double)
            guard let lo = amounts.min(), let hi = amounts.max(), hi <= lo * 1.15, hi < 5_000 else { continue }
            let latest = items.max { $0.date < $1.date }!
            // Подписка, не продлённая за последние 45 дней, уже не активна.
            guard Date().timeIntervalSince(latest.date) < 45 * 86_400 else { continue }
            result.append(Subscription(name: latest.title, amount: latest.absAmount,
                                       category: latest.category, months: months.count, last: latest.date))
        }
        return result.sorted { $0.amount > $1.amount }
    }

    static func topMerchants(_ all: [Transaction], month: Date, limit: Int = 5) -> [Merchant] {
        let items = inMonth(all, month).filter { $0.category.isExpense && $0.amount < 0 }
        return Dictionary(grouping: items, by: \.counterparty)
            .map { _, list in
                Merchant(name: list[0].title, amount: list.reduce(0) { $0 + $1.absAmount },
                         count: list.count, category: list[0].category)
            }
            .sorted { $0.amount > $1.amount }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Подсказки

    static func insights(_ all: [Transaction], month: Date, now: Date = Date()) -> [Insight] {
        insights(all, span: span(.month, month: month, all: all), now: now)
    }

    static func insights(_ all: [Transaction], span: Span, now: Date = Date(), reserved: Decimal = 0) -> [Insight] {
        var result: [Insight] = []
        let month = span.range.lowerBound
        // Период ещё идёт: прошлые сравниваем за тот же отрезок от начала
        let current = span.range.contains(now)
        let elapsed = now.timeIntervalSince(span.range.lowerBound)
        let s = stats(all, range: span.range)
        guard s.expenses > 0 || s.income > 0 else { return [] }

        // 1. Прогноз до конца месяца
        if span.kind == .month, let f = forecast(all, month: month, now: now, reserved: reserved), s.income > 0 {
            if s.expenses >= s.income {
                result.append(Insight(
                    tone: .warning, symbol: "exclamationmark.triangle.fill",
                    title: "Доход месяца уже потрачен",
                    text: "Расходы — \(Fmt.money(s.expenses)) при доходе \(Fmt.money(s.income)). До конца месяца \(f.daysLeft) \(Fmt.plural(f.daysLeft, "день", "дня", "дней")): дальше траты идут из накоплений или в долг."))
            } else if f.projected > s.income {
                result.append(Insight(
                    tone: .warning, symbol: "exclamationmark.triangle.fill",
                    title: "К концу месяца не хватит ~\(Fmt.money(f.projected - s.income))",
                    text: "При нынешнем темпе расходы составят около \(Fmt.money(f.projected)) при доходе \(Fmt.money(s.income)). Чтобы уложиться, тратьте не больше \(Fmt.money(f.perDayLeft)) в день."))
            } else {
                result.append(Insight(
                    tone: .good, symbol: "checkmark.seal.fill",
                    title: "В бюджет укладываетесь",
                    text: "Прогноз расходов — \(Fmt.money(f.projected)). Свободно \(Fmt.money(f.perDayLeft)) в день до конца месяца."))
            }
        }

        // 2. Рост категорий к среднему за прошлые месяцы (за тот же отрезок дней)
        let previous = span.previous
            .map { r in stats(all, range: current ? r.lowerBound ..< min(r.upperBound, r.lowerBound.addingTimeInterval(elapsed)) : r) }
            .filter { $0.expenses > 0 }
        // Заметная разница в рублях: за неделю меньше, за год больше
        let minGrowth: Decimal = span.kind == .week ? 1_000 : (span.kind == .month ? 2_000 : 10_000)
        if !previous.isEmpty {
            var growth: [(CategoryTotal, Decimal)] = []
            for item in s.byCategory where item.category != .transfersOut {
                let avg = previous.reduce(Decimal(0)) { sum, p in
                    sum + (p.byCategory.first { $0.category == item.category }?.amount ?? 0)
                } / Decimal(previous.count)
                guard avg > 0, item.amount - avg >= minGrowth, item.amount >= avg * 1.3 else { continue }
                growth.append((item, avg))
            }
            for (item, avg) in growth.sorted(by: { $0.0.amount - $0.1 > $1.0.amount - $1.1 }).prefix(2) {
                let percent = Int(((item.amount / avg - 1) * 100).double.rounded())
                result.append(Insight(
                    tone: .warning, symbol: item.category.symbol,
                    title: "\(item.category.title): +\(percent)% к обычному",
                    text: "\(Fmt.money(item.amount)) против \(Fmt.money(avg)) \(comparison(span, partial: current)). Разница — \(Fmt.money(item.amount - avg))."))
            }
        }

        // 3. Переводы людям без категории
        if let transfers = s.byCategory.first(where: { $0.category == .transfersOut }), s.expenses > 0 {
            let share = (transfers.amount / s.expenses).double
            if share >= 0.1 {
                result.append(Insight(
                    tone: .tip, symbol: "questionmark.circle.fill",
                    title: "\(Int(share * 100))% расходов — «переводы людям»",
                    text: "Это \(Fmt.money(transfers.amount)), и банк не знает, на что они. Откройте операцию и выберите категорию — например, «Жильё» для аренды. Приложение запомнит получателя."))
            }
        }

        // 4. Правило 50/30/20
        if s.income > 0 {
            let wants = (s.byGroup[.wants] ?? 0) / s.income
            let savings = ((s.byGroup[.savings] ?? 0) + max(s.balance, 0)) / s.income
            if wants.double > 0.35 {
                result.append(Insight(
                    tone: .tip, symbol: "chart.pie.fill",
                    title: "На желания уходит \(Int(wants.double * 100))% дохода",
                    text: "По правилу 50/30/20 на кафе, покупки и развлечения стоит тратить до 30%, а 20% — откладывать или гасить долги."))
            } else if savings.double >= 0.2 {
                result.append(Insight(
                    tone: .good, symbol: "leaf.fill",
                    title: "Откладываете \(Int(savings.double * 100))% дохода",
                    text: "Это выше рекомендуемых 20%. Если подушки безопасности на 3–6 месяцев ещё нет — направляйте свободные деньги туда."))
            }
        }

        // 5. Подписки
        let subs = subscriptions(all)
        if subs.count >= 2 {
            let monthly = subs.reduce(Decimal(0)) { $0 + $1.amount }
            result.append(Insight(
                tone: .tip, symbol: "repeat.circle.fill",
                title: "\(subs.count) \(Fmt.plural(subs.count, "регулярный платёж", "регулярных платежа", "регулярных платежей")) — \(Fmt.money(monthly)) в месяц",
                text: "За год это \(Fmt.money(monthly * 12)). Проверьте, всеми ли вы пользуетесь."))
        }

        // 6. Мелкие покупки
        let small = all.filter { span.range.contains($0.date) && $0.category.isExpense && $0.amount < 0 && $0.absAmount <= 500 }
        let smallSum = small.reduce(Decimal(0)) { $0 + $1.absAmount }
        // 15 мелких покупок в месяц — порог, для недели и года пропорционально
        if small.count >= max(15 * span.days / 30, 4) {
            let yearly = span.kind == .year
                ? "но за год набежало \(Fmt.money(smallSum))"
                : "но за год это около \(Fmt.money(smallSum * 365 / Decimal(span.days)))"
            result.append(Insight(
                tone: .tip, symbol: "cup.and.saucer.fill",
                title: "\(small.count) \(Fmt.plural(small.count, "мелкая покупка", "мелкие покупки", "мелких покупок")) на \(Fmt.money(smallSum))",
                text: "Покупки до 500 ₽ незаметны по отдельности, \(yearly)."))
        }

        // 7. Что исключено по сравнению с банковской статистикой
        if s.internalVolume > 0 {
            result.append(Insight(
                tone: .good, symbol: "arrow.left.arrow.right.circle.fill",
                title: "Не учтено \(Fmt.money(s.internalVolume)) переводов себе",
                text: "\(s.internalCount) \(Fmt.plural(s.internalCount, "перевод", "перевода", "переводов")) между вашими счетами. В статистике банка они выглядят как расходы и доходы и искажают картину."))
        }
        return result
    }

    /// С чем сравниваем рост категории.
    private static func comparison(_ span: Span, partial: Bool) -> String {
        let same = partial ? "тот же период " : ""
        switch span.kind {
        case .week:  return "в среднем за \(same)прошлых недель"
        case .month: return "в среднем за \(same)прошлых месяцев"
        case .year:  return "за \(same)предыдущие 12 месяцев"
        }
    }
}

// MARK: Форматирование

enum Fmt {
    private static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        // Обычный неразрывный пробел: узкого (U+202F) нет в Helvetica Neue Bold
        f.groupingSeparator = "\u{00A0}"
        return f
    }()

    private static let exactFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        // Обычный неразрывный пробел: узкого (U+202F) нет в Helvetica Neue Bold
        f.groupingSeparator = "\u{00A0}"
        return f
    }()

    static func money(_ value: Decimal) -> String {
        (moneyFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "0") + "\u{00A0}₽"
    }

    static func exact(_ value: Decimal, sign: Bool = false) -> String {
        let text = (exactFormatter.string(from: NSDecimalNumber(decimal: value < 0 ? -value : value)) ?? "0") + "\u{00A0}₽"
        guard sign else { return text }
        return (value < 0 ? "−" : "+") + text
    }

    static func compact(_ value: Decimal) -> String {
        let v = value.double
        if abs(v) >= 1_000_000 { return String(format: "%.1f млн", v / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if abs(v) >= 10_000 { return "\(Int((v / 1000).rounded())) тыс" }
        return money(value)
    }

    static func percent(_ part: Decimal, of total: Decimal) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int(((part / total).double * 100).rounded()))%"
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10, n100 = n % 100
        if (n10 == 1) && (n100 != 11) { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private static let shortMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLL"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM, EEEE"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy, HH:mm"
        return f
    }()

    static func month(_ d: Date) -> String { monthFormatter.string(from: d).capitalized }

    private static let genitiveFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let genitiveOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "MMMM"
        return f
    }()

    /// «октября» — для «Итоги октября».
    static func monthGenitiveOnly(_ d: Date) -> String { genitiveOnlyFormatter.string(from: d) }

    /// «июня 2028» — для «до июня 2028».
    static func monthGenitive(_ d: Date) -> String { genitiveFormatter.string(from: d) }
    static func shortMonth(_ d: Date) -> String { shortMonthFormatter.string(from: d).replacingOccurrences(of: ".", with: "") }
    static func day(_ d: Date) -> String { dayFormatter.string(from: d) }
    static func dateTime(_ d: Date) -> String { dateTimeFormatter.string(from: d) }
}
