import SwiftUI
import Observation

@Observable
final class Store {
    var transactions: [Transaction] = []
    var rules: [CategoryRule] = []
    var imports: [ImportRecord] = []
    var recurring: [RecurringPayment] = []
    var limits: [BudgetLimit] = []
    var incomePlan = IncomePlan()
    var debts: [Debt] = []
    var goals: [SavingsGoal] = []
    var cashbackCards: [CashbackCard] = []
    var month: Date = Store.startOfMonth(Date())
    /// Растёт при каждом сохранении — по нему обновляются напоминания и виджет.
    var changes: Int = 0

    @ObservationIgnored private let persistent: Bool
    @ObservationIgnored private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("kaplya.json")
    }()

    private struct SavedState: Codable {
        var transactions: [Transaction] = []
        var rules: [CategoryRule] = []
        var imports: [ImportRecord] = []
        var recurring: [RecurringPayment] = []
        var limits: [BudgetLimit] = []
        var incomePlan = IncomePlan()
        var debts: [Debt] = []
        var goals: [SavingsGoal] = []
        var cashbackCards: [CashbackCard] = []

        init(transactions: [Transaction], rules: [CategoryRule], imports: [ImportRecord],
             recurring: [RecurringPayment], limits: [BudgetLimit], incomePlan: IncomePlan, debts: [Debt],
             goals: [SavingsGoal], cashbackCards: [CashbackCard]) {
            self.transactions = transactions
            self.rules = rules
            self.imports = imports
            self.recurring = recurring
            self.limits = limits
            self.incomePlan = incomePlan
            self.debts = debts
            self.goals = goals
            self.cashbackCards = cashbackCards
        }

        // Старые сохранения без плана тоже читаются
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            transactions = try c.decodeIfPresent([Transaction].self, forKey: .transactions) ?? []
            rules = try c.decodeIfPresent([CategoryRule].self, forKey: .rules) ?? []
            imports = try c.decodeIfPresent([ImportRecord].self, forKey: .imports) ?? []
            recurring = try c.decodeIfPresent([RecurringPayment].self, forKey: .recurring) ?? []
            limits = try c.decodeIfPresent([BudgetLimit].self, forKey: .limits) ?? []
            incomePlan = try c.decodeIfPresent(IncomePlan.self, forKey: .incomePlan) ?? IncomePlan()
            debts = try c.decodeIfPresent([Debt].self, forKey: .debts) ?? []
            goals = try c.decodeIfPresent([SavingsGoal].self, forKey: .goals) ?? []
            cashbackCards = try c.decodeIfPresent([CashbackCard].self, forKey: .cashbackCards) ?? []
        }
    }

    init(demo: Bool = false) {
        persistent = !demo
        if demo {
            transactions = DemoData.transactions()
            linkInternalTransfers()
            imports = DemoData.imports(for: transactions)
            seedDemoPlan()
        } else {
            load()
            rollDebts()
        }
        if let last = transactions.map(\.date).max(), last < month {
            month = Store.startOfMonth(last)
        }
    }

    // MARK: Хранение

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let state = try? JSONDecoder().decode(SavedState.self, from: data) else {
            // Файл не читается — откладываем копию, чтобы следующее сохранение не стёрло данные насовсем
            let backup = fileURL.deletingPathExtension().appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            return
        }
        transactions = state.transactions
        rules = state.rules
        imports = state.imports
        recurring = state.recurring
        limits = state.limits
        incomePlan = state.incomePlan
        debts = state.debts
        goals = state.goals
        cashbackCards = state.cashbackCards
    }

    func save() {
        changes += 1
        guard persistent else { return }
        let state = SavedState(transactions: transactions, rules: rules, imports: imports,
                               recurring: recurring, limits: limits, incomePlan: incomePlan, debts: debts,
                               goals: goals, cashbackCards: cashbackCards)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        }
    }

    // MARK: Импорт

    func importStatement(at url: URL) throws -> ImportRecord {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let parsed = try StatementParser.parse(url: url)
        return add(parsed, fileName: url.lastPathComponent)
    }

    @discardableResult
    func add(_ parsed: ParseResult, fileName: String) -> ImportRecord {
        let importID = UUID()
        var known = Set(transactions.map(\.fingerprint))
        var occurrences: [String: Int] = [:]
        var added = 0
        var duplicates = 0

        for row in parsed.rows {
            // Одинаковые покупки в одну минуту различаем порядковым номером в файле.
            let base = Store.fingerprint(bank: parsed.bank, row: row)
            let n = occurrences[base, default: 0]
            occurrences[base] = n + 1
            let fingerprint = base + "#\(n)"
            if known.contains(fingerprint) {
                duplicates += 1
                continue
            }
            known.insert(fingerprint)
            var category = Categorizer.category(title: row.title, bankCategory: row.bankCategory,
                                                mcc: row.mcc, amount: row.amount, rules: rules)
            if Categorizer.isOwnTransfer(row.title, owner: parsed.owner) {
                category = .internalTransfer
            }
            transactions.append(Transaction(
                date: row.date, amount: row.amount, currency: row.currency, bank: parsed.bank,
                card: row.card, title: row.title, bankCategory: row.bankCategory, mcc: row.mcc,
                category: category, fingerprint: fingerprint, importID: importID))
            added += 1
        }

        let internalFound = linkInternalTransfers()
        transactions.sort { $0.date > $1.date }
        let record = ImportRecord(id: importID, date: Date(), fileName: fileName, bank: parsed.bank,
                                  added: added, duplicates: duplicates, internalFound: internalFound)
        imports.insert(record, at: 0)
        if added > 0, let newest = parsed.rows.map(\.date).max() {
            month = Store.startOfMonth(newest)
        }
        save()
        return record
    }

    static func fingerprint(bank: Bank, row: ParsedRow) -> String {
        let minute = Int(row.date.timeIntervalSince1970 / 60)
        return "\(bank.rawValue)|\(minute)|\(row.amount)|\(Transaction.normalize(row.title))"
    }

    /// Ищет пары «ушло из одного банка — пришло в другой» на ту же сумму в пределах трёх дней.
    @discardableResult
    func linkInternalTransfers() -> Int {
        func transferLike(_ t: Transaction) -> Bool {
            guard !t.isManual else { return false }
            if t.category.isInternal { return false }
            let allowed: [Category] = [.transfersOut, .transfersIn, .otherIncome, .otherExpense]
            return allowed.contains(t.category)
                && (Categorizer.isTransfer(Transaction.normalize(t.title))
                    || Categorizer.isTransfer(t.bankCategory.lowercased()))
        }

        let outgoing = transactions.indices.filter { transactions[$0].amount < 0 && transferLike(transactions[$0]) }
        var incoming = transactions.indices.filter { transactions[$0].amount > 0 && transferLike(transactions[$0]) }
        var pairs = 0

        for o in outgoing {
            let out = transactions[o]
            guard let match = incoming.firstIndex(where: { i in
                let inc = transactions[i]
                // Мелкие суммы без упоминания второго банка — скорее совпадение с переводом другу.
                let mentionsOtherBank = Store.mentions(inc.bank, in: out) || Store.mentions(out.bank, in: inc)
                return (inc.amount == -out.amount)
                    && ((inc.bank != out.bank) || (inc.card != out.card))
                    && (abs(inc.date.timeIntervalSince(out.date)) <= 3 * 86_400)
                    && (mentionsOtherBank || (out.absAmount >= 5_000))
            }) else { continue }
            transactions[o].category = .internalTransfer
            transactions[incoming[match]].category = .internalTransfer
            incoming.remove(at: match)
            pairs += 1
        }
        return pairs
    }

    static func mentions(_ bank: Bank, in t: Transaction) -> Bool {
        let names: [String]
        switch bank {
        case .tbank: names = ["тбанк", "т банк", "т-банк", "тинькофф", "tinkoff", "tbank"]
        case .sber:  names = ["сбер", "sber"]
        case .other: names = []
        }
        let text = (t.title + " " + t.bankCategory).lowercased()
        return names.contains { text.contains($0) }
    }

    // MARK: Правка операций

    func setCategory(_ category: Category, for id: Transaction.ID, remember: Bool) {
        guard let index = transactions.firstIndex(where: { $0.id == id }) else { return }
        transactions[index].category = category
        transactions[index].isManual = true

        if remember {
            let match = transactions[index].counterparty
            rules.removeAll { $0.match == match }
            rules.append(CategoryRule(match: match, category: category))
            for i in transactions.indices
            where (!transactions[i].isManual) && (transactions[i].counterparty == match) {
                transactions[i].category = category
            }
        }
        save()
    }

    func deleteRule(_ rule: CategoryRule) {
        rules.removeAll { $0.id == rule.id }
        save()
    }

    func deleteImport(_ record: ImportRecord) {
        transactions.removeAll { $0.importID == record.id }
        imports.removeAll { $0.id == record.id }
        save()
    }

    func deleteAll() {
        transactions = []
        rules = []
        imports = []
        recurring = []
        limits = []
        incomePlan = IncomePlan()
        debts = []
        goals = []
        cashbackCards = []
        month = Store.startOfMonth(Date())
        save()
    }

    func loadDemo() {
        let demo = DemoData.transactions()
        transactions = demo
        linkInternalTransfers()
        imports = DemoData.imports(for: transactions)
        month = Store.startOfMonth(Date())
        seedDemoPlan()
        save()
    }

    /// Демо-план: регулярные платежи из выписок (кроме двух — их предложит подсказка) и план по средним тратам.
    private func seedDemoPlan() {
        recurring = []
        limits = []
        incomePlan = IncomePlan()
        for payment in suggestedRecurring().dropLast(2) {
            var p = payment
            if p.match.contains("ивана") {
                p.title = "Аренда квартиры"
                p.category = .housing
            } else if p.match.contains("репетитор") {
                p.title = "Репетитор"
                p.category = .education
            }
            recurring.append(p)
        }
        recurring.sort { $0.nextDate() < $1.nextDate() }
        // Демо-долги: кредит из выписок и рассрочка, которой в выписках ещё нет
        let cal = Store.calendar
        debts = suggestedDebts().map { found in
            var d = found
            d.title = "Кредит наличными"
            d.lender = "Сбер"
            d.principal = 150_000
            d.balance = 86_400
            d.rate = 19.9
            return d
        }
        debts.append(Debt(kind: .installment, title: "iPhone 16 Pro долями", lender: "Т-Банк",
                          principal: 119_880, balance: 59_940, monthlyPayment: 9_990, rate: 0,
                          nextPayment: cal.date(byAdding: .day, value: 9, to: Date()) ?? Date()))
        debts.append(Debt(kind: .carLoan, title: "Автокредит", lender: "Т-Банк",
                          principal: 1_100_000, balance: 640_000, monthlyPayment: 24_500, rate: 14.5,
                          nextPayment: cal.date(byAdding: .day, value: 15, to: Date()) ?? Date()))
        debts.append(Debt(kind: .creditCard, title: "Кредитная карта", lender: "Т-Банк",
                          principal: 150_000, balance: 42_300, monthlyPayment: 2_100, rate: 29.9,
                          nextPayment: cal.date(byAdding: .day, value: 12, to: Date()) ?? Date(),
                          graceEnds: cal.date(byAdding: .day, value: 18, to: Date())))
        debts.sort { $0.upcomingPayment() < $1.upcomingPayment() }
        let plan = suggestedPlan()
        limits = plan.limits
        incomePlan.savings = plan.savings

        goals = [
            SavingsGoal(title: "Подушка безопасности", symbol: "lifepreserver.fill", target: 300_000, saved: 85_000,
                        deadline: cal.date(byAdding: .month, value: 12, to: Date()), colorIndex: 1),
            SavingsGoal(title: "Отпуск летом", symbol: "airplane", target: 120_000, saved: 45_000,
                        deadline: cal.date(byAdding: .month, value: 8, to: Date()), colorIndex: 0)
        ]
        cashbackCards = [
            CashbackCard(title: "Т-Банк Black", bank: .tbank, base: 1, rates: [.cafe: 5, .taxi: 5, .delivery: 3]),
            CashbackCard(title: "СберКарта", bank: .sber, base: 0.5, rates: [.groceries: 5, .health: 3, .marketplace: 2])
        ]
    }

    // MARK: Месяцы

    var monthTransactions: [Transaction] {
        transactions.filter { Store.calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    var hasPreviousMonth: Bool {
        guard let first = transactions.map(\.date).min() else { return false }
        return first < month
    }

    var hasNextMonth: Bool {
        guard let next = Store.calendar.date(byAdding: .month, value: 1, to: month) else { return false }
        return next <= Date()
    }

    func shiftMonth(_ delta: Int) {
        if let m = Store.calendar.date(byAdding: .month, value: delta, to: month) {
            month = m
        }
    }

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = 2
        return c
    }()

    static func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
