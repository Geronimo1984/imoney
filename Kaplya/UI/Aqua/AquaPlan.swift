import SwiftUI

/// «План» в глянцевом оформлении: те же данные и листы правки, что в системном.
struct AquaPlan: View {
    @Environment(Store.self) private var store
    @State private var editingLimit: Category?
    @State private var addingLimit = false
    @State private var editingPayment: RecurringPayment?
    @State private var showSuggestions = false
    @State private var showAutoPlan = false
    @State private var editingSavings = false
    @State private var editingIncome = false
    @State private var showDebts = false
    @State private var showGoals = false
    @State private var showPayoff = false
    @State private var showCashback = false

    var body: some View {
        let stats = Analytics.stats(store.transactions, month: store.month)
        let plan = store.planSummary()
        let suggestions = store.suggestedRecurring()

        VStack(spacing: 0) {
            AquaNavBar(title: "План")
            ScrollView {
                VStack(spacing: 16) {
                    distribution(plan)
                    debts(plan)
                    limits(stats)
                    recurring(suggestions)
                    savings(stats, plan)
                    AquaSection(title: "Цели и инструменты") {
                        VStack(spacing: 0) {
                            AquaLinkRow(symbol: "target", color: .blue, title: "Цели накоплений",
                                        value: store.goals.isEmpty ? "" : "\(store.goals.count)") { showGoals = true }
                            Divider().overlay(Aqua.line)
                            AquaLinkRow(symbol: "chart.line.downtrend.xyaxis", color: .red, title: "Стратегия погашения") { showPayoff = true }
                            Divider().overlay(Aqua.line)
                            AquaLinkRow(symbol: "creditcard.fill", color: .orange, title: "Кэшбэк по картам") { showCashback = true }
                        }
                        .groupCard()
                    }
                }
                .padding(10)
            }
        }
        .sheet(item: $editingLimit) { LimitEditor(category: $0, isNew: false) }
        .sheet(isPresented: $addingLimit) { LimitEditor(category: nil, isNew: true) }
        .sheet(item: $editingPayment) { p in
            RecurringEditor(payment: p, isNew: !store.recurring.contains { $0.id == p.id })
        }
        .sheet(isPresented: $showSuggestions) { SuggestedPaymentsSheet() }
        .sheet(isPresented: $showAutoPlan) { AutoPlanSheet().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $editingSavings) {
            AmountEditor(title: "Накопления", caption: "Сколько откладывать каждый месяц",
                         value: store.incomePlan.savings) { store.setSavings($0) }
        }
        .sheet(isPresented: $editingIncome) { IncomeEditor() }
        .sheet(isPresented: $showGoals) { SystemSheet { GoalsView() } }
        .sheet(isPresented: $showPayoff) { SystemSheet { PayoffView() } }
        .sheet(isPresented: $showCashback) { SystemSheet { CashbackView() } }
        .sheet(isPresented: $showDebts) {
            NavigationStack {
                DebtsView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Готово") { showDebts = false } }
                }
            }
        }
    }

    // MARK: Распределение

    private func distribution(_ plan: PlanSummary) -> some View {
        let parts: [(String, Decimal, Color)] = [
            ("Регулярные платежи", plan.recurring, Aqua.blue),
            ("Кредиты", plan.debts, .red),
            ("Лимиты", plan.limits, .orange),
            ("Накопления", plan.savings, Color(red: 0.20, green: 0.70, blue: 0.30)),
            ("Не распределено", max(plan.free, 0), Color(red: 0.62, green: 0.65, blue: 0.70))
        ]
        return AquaSection(title: "Распределение дохода") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.incomeIsExpected ? "Ожидаемый доход" : "Доход за \(Fmt.month(store.month).lowercased())")
                        .font(Aqua.font(12, .bold)).foregroundStyle(Aqua.label)
                    Text(Fmt.money(plan.income)).font(Aqua.font(28, .bold)).foregroundStyle(Aqua.text)
                }
                GeometryReader { geo in
                    let total = max(plan.income, plan.allocated, 1)
                    HStack(spacing: 2) {
                        ForEach(parts.filter { $0.1 > 0 }, id: \.0) { part in
                            AquaGel(shape: RoundedRectangle(cornerRadius: 4), color: part.2, shadow: false)
                                .frame(width: max(4, geo.size.width * (part.1 / total).double - 2))
                        }
                    }
                }
                .frame(height: 20)
                ForEach(parts, id: \.0) { part in
                    HStack(spacing: 8) {
                        Circle().fill(part.2).frame(width: 10, height: 10)
                        Text(part.0).font(Aqua.font(14, .bold)).foregroundStyle(Aqua.text)
                        Spacer()
                        Text(Fmt.money(part.1)).font(Aqua.font(14)).foregroundStyle(Aqua.link)
                    }
                }
                if plan.free < 0 {
                    Text("План больше дохода на \(Fmt.money(-plan.free)).").font(Aqua.font(13, .bold)).foregroundStyle(Aqua.negative)
                }
                AquaButton(title: "Распределить автоматически", symbol: "wand.and.stars") { showAutoPlan = true }
                Button { editingIncome = true } label: {
                    Text(plan.incomeIsExpected ? "Доход для плана: ожидаемый ›" : "Доход для плана: фактический ›")
                        .font(Aqua.font(13, .bold)).foregroundStyle(Aqua.link)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(14)
            .groupCard()
        }
    }

    // MARK: Кредиты

    private func debts(_ plan: PlanSummary) -> some View {
        AquaSection(title: "Кредиты и рассрочки") {
            VStack(spacing: 0) {
                ForEach(store.debts) { debt in
                    let paid = debt.isPaid(in: store.month, transactions: store.transactions)
                    Button { showDebts = true } label: {
                        HStack(spacing: 10) {
                            AquaIcon(symbol: debt.kind.symbol, color: debt.kind.color, size: 30)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(debt.title).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text).lineLimit(1)
                                    Spacer()
                                    Text("\(Fmt.money(debt.monthlyPayment)) / мес").font(Aqua.font(13)).foregroundStyle(Aqua.link)
                                }
                                AquaProgress(value: debt.ringShare, color: debt.kind.color, height: 9)
                                Text(paid ? "Платёж в этом месяце внесён" : debt.summary)
                                    .font(Aqua.font(12)).foregroundStyle(paid ? Aqua.positive : Aqua.label)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Aqua.line)
                }
                addRow(store.debts.isEmpty ? "Добавить кредит или рассрочку" : "Все кредиты и рассрочки") { showDebts = true }
                Text(loadAdvice(plan.debtLoad)).font(Aqua.font(12)).foregroundStyle(Aqua.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
            .groupCard()
        }
    }

    // MARK: Лимиты

    private func limits(_ stats: MonthStats) -> some View {
        AquaSection(title: "Лимиты на месяц") {
            VStack(spacing: 0) {
                ForEach(store.limits) { limit in
                    let spent = stats.byCategory.first { $0.category == limit.category }?.amount ?? 0
                    let share = (spent / limit.amount).double
                    Button { editingLimit = limit.category } label: {
                        HStack(spacing: 10) {
                            AquaIcon(symbol: limit.category.symbol, color: limit.category.systemColor, size: 30)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(limit.category.title).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text)
                                    Spacer()
                                    Text("\(Fmt.money(spent)) из \(Fmt.money(limit.amount))")
                                        .font(Aqua.font(13)).foregroundStyle(share > 1 ? Aqua.negative : Aqua.label)
                                }
                                AquaProgress(value: min(share, 1),
                                             color: share > 1 ? .red : (share > 0.8 ? .orange : limit.category.systemColor),
                                             height: 9)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Aqua.line)
                }
                addRow("Добавить лимит") { addingLimit = true }
            }
            .groupCard()
        }
    }

    // MARK: Регулярные платежи

    private func recurring(_ suggestions: [RecurringPayment]) -> some View {
        AquaSection(title: "Регулярные платежи") {
            VStack(spacing: 0) {
                ForEach(store.recurring) { payment in
                    let paid = payment.isPaid(in: store.month, transactions: store.transactions)
                    Button { editingPayment = payment } label: {
                        HStack(spacing: 10) {
                            AquaIcon(symbol: payment.category.symbol, color: payment.category.systemColor, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(payment.title).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text).lineLimit(1)
                                Text(paid ? "Оплачен в этом месяце" : "Следующий — \(payment.nextDate().formatted(.dateTime.day().month(.wide)))")
                                    .font(Aqua.font(12)).foregroundStyle(paid ? Aqua.positive : Aqua.label)
                            }
                            Spacer()
                            Text(Fmt.money(payment.amount)).font(Aqua.font(15)).foregroundStyle(Aqua.link)
                            if paid {
                                Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Aqua.positive)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Aqua.line)
                }
                if !suggestions.isEmpty {
                    Button { showSuggestions = true } label: {
                        HStack(spacing: 10) {
                            AquaIcon(symbol: "sparkles", color: .purple, size: 30)
                            Text("Найдено в выписках: \(suggestions.count)").font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Aqua.line)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Aqua.line)
                }
                addRow("Добавить платёж") {
                    editingPayment = RecurringPayment(title: "", amount: 0, category: .housing, startDate: Date())
                }
            }
            .groupCard()
        }
    }

    // MARK: Накопления

    private func savings(_ stats: MonthStats, _ plan: PlanSummary) -> some View {
        let saved = stats.byGroup[.savings] ?? 0
        return AquaSection(title: "Накопления") {
            Button { editingSavings = true } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Откладывать в месяц").font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text)
                        Spacer()
                        Text(Fmt.money(plan.savings)).font(Aqua.font(15)).foregroundStyle(Aqua.link)
                    }
                    if plan.savings > 0 {
                        Text("Отложено \(Fmt.money(saved)) из \(Fmt.money(plan.savings))").font(Aqua.font(12)).foregroundStyle(Aqua.label)
                        AquaProgress(value: min((saved / plan.savings).double, 1), color: Color(red: 0.20, green: 0.70, blue: 0.30), height: 11)
                    }
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .groupCard()
        }
    }

    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AquaIcon(symbol: "plus", color: Color(red: 0.20, green: 0.70, blue: 0.30), size: 30)
                Text(title).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.link)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
