import SwiftUI

/// «План»: распределение дохода, лимиты по категориям, регулярные платежи и накопления —
/// списком в духе Настроек и Экранного времени, правка — в листах «Отмена / Готово».
struct PlanView: View {
    @Environment(Store.self) private var store
    @State private var editingLimit: Category?
    @State private var addingLimit = false
    @State private var editingPayment: RecurringPayment?
    @State private var editingPlanned: PlannedExpense?
    @State private var showSuggestions = false
    @State private var showAutoPlan = false
    @State private var editingSavings = false
    @State private var editingIncome = false

    var body: some View {
        let stats = Analytics.stats(store.transactions, month: store.month)
        let plan = store.planSummary()
        let forecast = store.forecast()
        let suggestions = store.suggestedRecurring()

        NavigationStack {
            List {
                distribution(plan)

                if let forecast {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("МОЖНО ТРАТИТЬ СЕГОДНЯ").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(Fmt.money(forecast.perDayLeft))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(forecast.perDayLeft > 0 ? Color.primary : Color.red)
                                // Отметили расход оплаченным или поменяли план — сумма перещёлкивается
                                .contentTransition(.numericText())
                                .motion(value: forecast.perDayLeft)
                            Text("Чтобы уложиться в доход до конца месяца. Осталось \(forecast.daysLeft) \(Fmt.plural(forecast.daysLeft, "день", "дня", "дней")).")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                debtsSection(plan)
                limitsSection(stats)
                recurringSection(suggestions)
                plannedSection
                savingsSection(stats, plan)
                GoalsSection()
                rulesSection(stats)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("План")
            .sheet(item: $editingLimit) { category in
                LimitEditor(category: category, isNew: false)
            }
            .sheet(isPresented: $addingLimit) {
                LimitEditor(category: nil, isNew: true)
            }
            .sheet(item: $editingPayment) { payment in
                RecurringEditor(payment: payment, isNew: !store.recurring.contains { $0.id == payment.id })
            }
            .sheet(item: $editingPlanned) { expense in
                PlannedExpenseEditor(expense: expense, isNew: !store.planned.contains { $0.id == expense.id })
            }
            .sheet(isPresented: $showSuggestions) { SuggestedPaymentsSheet() }
            .sheet(isPresented: $showAutoPlan) { AutoPlanSheet().presentationDetents([.medium, .large]) }
            .sheet(isPresented: $editingSavings) {
                AmountEditor(title: "Накопления", caption: "Сколько откладывать каждый месяц",
                             value: store.incomePlan.savings) { store.setSavings($0) }
            }
            .sheet(isPresented: $editingIncome) { IncomeEditor() }
        }
    }

    // MARK: Распределение дохода

    @ViewBuilder
    private func distribution(_ plan: PlanSummary) -> some View {
        let parts: [(String, Decimal, Color)] = [
            ("Регулярные платежи", plan.recurring, .blue),
            ("Разовые расходы", plan.planned, .purple),
            ("Кредиты", plan.debts, .red),
            ("Лимиты", plan.limits, .orange),
            ("Накопления", plan.savings, .green),
            ("Не распределено", max(plan.free, 0), Color(.systemGray4))
        ]
        Section {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.incomeIsExpected ? "ОЖИДАЕМЫЙ ДОХОД" : "ДОХОД ЗА \(Fmt.month(store.month).uppercased())")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(Fmt.money(plan.income)).font(.system(size: 34, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .motion(value: plan.income)
                }
                // Полоса распределения — как полоса хранилища в Настройках; при открытии заполняется слева направо
                Growing(value: 1) { fill in
                    GeometryReader { geo in
                        let total = max(plan.income, plan.allocated, 1)
                        HStack(spacing: 2) {
                            ForEach(parts.filter { $0.1 > 0 }, id: \.0) { part in
                                Rectangle().fill(part.2)
                                    .frame(width: max(3, geo.size.width * fill * (part.1 / total).double - 2))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .motion(value: plan.allocated)
                }
                .frame(height: 18)
                VStack(spacing: 6) {
                    ForEach(parts, id: \.0) { part in
                        HStack {
                            Circle().fill(part.2).frame(width: 9, height: 9)
                            Text(part.0).font(.subheadline)
                            Spacer()
                            Text(Fmt.money(part.1)).font(.subheadline).foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                                .motion(value: part.1)
                        }
                    }
                }
            }
            .padding(.vertical, 6)

            Button { showAutoPlan = true } label: {
                Label("Распределить автоматически", systemImage: "wand.and.stars")
            }
            Button { editingIncome = true } label: {
                LabeledContent {
                    Text(plan.incomeIsExpected ? "Ожидаемый" : "Фактический")
                } label: {
                    Label("Доход для плана", systemImage: "banknote")
                }
            }
            .foregroundStyle(.primary)
        } header: {
            Text("Распределение дохода")
        } footer: {
            if plan.free < 0 {
                Text("План больше дохода на \(Fmt.money(-plan.free)). Уменьшите лимиты или накопления.")
                    .foregroundStyle(.red)
            } else if plan.free > 0 {
                Text("Нераспределённые \(Fmt.money(plan.free)) можно отправить в накопления или задать на них лимиты.")
            }
        }
    }

    // MARK: Кредиты

    private func debtsSection(_ plan: PlanSummary) -> some View {
        Section {
            ForEach(store.debts.prefix(4)) { debt in
                NavigationLink { DebtDetail(id: debt.id) } label: {
                    DebtRow(debt: debt, paid: debt.isPaid(in: store.month, transactions: store.transactions))
                }
            }
            if store.debts.contains(where: { $0.balance > 0 }) {
                NavigationLink { PayoffView() } label: {
                    Label("Стратегия погашения", systemImage: "chart.line.downtrend.xyaxis")
                }
            }
            NavigationLink { DebtsView() } label: {
                LabeledContent {
                    Text(Fmt.money(store.debtsTotal))
                } label: {
                    Label(store.debts.isEmpty ? "Добавить кредит или рассрочку" : "Все кредиты и рассрочки",
                          systemImage: store.debts.isEmpty ? "plus.circle.fill" : "list.bullet")
                }
            }
        } header: {
            Text("Кредиты и рассрочки")
        } footer: {
            Text(loadAdvice(plan.debtLoad))
        }
    }

    // MARK: Лимиты

    private func limitsSection(_ stats: MonthStats) -> some View {
        Section {
            ForEach(store.limits) { limit in
                let spent = stats.byCategory.first { $0.category == limit.category }?.amount ?? 0
                let share = (spent / limit.amount).double
                Button { editingLimit = limit.category } label: {
                    HStack(spacing: 12) {
                        CategoryBadge(category: limit.category)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(limit.category.title).foregroundStyle(.primary)
                                Spacer()
                                Text("\(Fmt.money(spent)) из \(Fmt.money(limit.amount))")
                                    .font(.subheadline)
                                    .foregroundStyle(share > 1 ? Color.red : .secondary)
                            }
                            GrowingProgress(value: min(share, 1),
                                            tint: share > 1 ? .red : (share > 0.8 ? .orange : limit.category.systemColor))
                        }
                    }
                }
                .foregroundStyle(.primary)
                // Лимит только что превышен — короткое предупреждение
                .sensoryFeedback(.warning, trigger: share > 1) { old, new in !old && new }
                .swipeActions {
                    Button("Удалить", role: .destructive) { Haptic.delete(); Motion.animate { store.setLimit(limit.category, nil) } }
                }
            }
            Button { addingLimit = true } label: {
                Label("Добавить лимит", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Лимиты на месяц")
        } footer: {
            Text("Сколько готовы потратить на категорию. Полоса становится оранжевой после 80% и красной, когда лимит превышен.")
        }
    }

    // MARK: Регулярные платежи

    private func recurringSection(_ suggestions: [RecurringPayment]) -> some View {
        Section {
            ForEach(store.recurring) { payment in
                let paid = payment.isPaid(in: store.month, transactions: store.transactions)
                Button { editingPayment = payment } label: {
                    HStack(spacing: 12) {
                        CategoryBadge(category: payment.category)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payment.title).foregroundStyle(.primary).lineLimit(1)
                            Text(paid ? "Оплачен в этом месяце" : "Следующий — \(payment.nextDate().formatted(.dateTime.day().month(.wide)))")
                                .font(.caption)
                                .foregroundStyle(paid ? Color.green : .secondary)
                        }
                        Spacer()
                        Text(Fmt.money(payment.amount)).foregroundStyle(.secondary)
                        if paid {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions {
                    Button("Удалить", role: .destructive) { Haptic.delete(); Motion.animate { store.deleteRecurring(payment.id) } }
                }
            }
            if !suggestions.isEmpty {
                Button { showSuggestions = true } label: {
                    LabeledContent {
                        Text("\(suggestions.count)")
                    } label: {
                        Label("Найдено в выписках", systemImage: "sparkles")
                    }
                }
            }
            Button {
                editingPayment = RecurringPayment(title: "", amount: 0, category: .housing, startDate: Date())
            } label: {
                Label("Добавить платёж", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Регулярные платежи")
        } footer: {
            Text("Итого \(Fmt.money(store.recurring.reduce(0) { $0 + $1.monthly })) в месяц, \(Fmt.money(store.recurring.reduce(0) { $0 + $1.monthly } * 12)) в год.")
        }
    }

    // MARK: Разовые расходы

    private var plannedSection: some View {
        let thisMonth = store.planned(in: store.month).reduce(Decimal(0)) { $0 + $1.amount }
        // Оплаченные уезжают вниз, к концу списка
        let paidIDs = Set(store.upcomingPlanned.filter { $0.isPaid(transactions: store.transactions) }.map(\.id))
        let rows = store.upcomingPlanned.filter { !paidIDs.contains($0.id) } + store.upcomingPlanned.filter { paidIDs.contains($0.id) }
        return Section {
            ForEach(rows) { expense in
                let paid = paidIDs.contains(expense.id)
                Button { editingPlanned = expense } label: {
                    HStack(spacing: 12) {
                        CategoryBadge(category: expense.category)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(expense.title).foregroundStyle(.primary).lineLimit(1)
                            Text(paid ? "Оплачено" : expense.date.formatted(.dateTime.day().month(.wide).year()))
                                .font(.caption)
                                .foregroundStyle(paid ? Color.green : .secondary)
                        }
                        Spacer()
                        Text(Fmt.money(expense.amount)).foregroundStyle(.secondary)
                            .strikethrough(paid, color: .secondary)
                        if paid {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .foregroundStyle(.primary)
                .sensoryFeedback(.success, trigger: paid) { old, new in !old && new }
                .swipeActions {
                    Button("Удалить", role: .destructive) { Haptic.delete(); Motion.animate { store.deletePlanned(expense.id) } }
                }
                .swipeActions(edge: .leading) {
                    Button(expense.done ? "Не оплачено" : "Оплачено", systemImage: "checkmark") {
                        Motion.animate(Motion.spring) { store.togglePlannedDone(expense.id) }
                    }
                    .tint(.green)
                }
            }
            Button {
                editingPlanned = PlannedExpense(title: "", amount: 0, category: .gifts, date: Date())
            } label: {
                Label("Добавить расход", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Разовые расходы")
        } footer: {
            Text(thisMonth > 0
                 ? "За \(Fmt.month(store.month).lowercased()) — \(Fmt.money(thisMonth)). Пока расход не оплачен, его сумма откладывается из «можно тратить сегодня»."
                 : "Отпуск, подарки, страховка — покупки на определённую дату. Они попадут в план своего месяца.")
        }
    }

    // MARK: Накопления

    private func savingsSection(_ stats: MonthStats, _ plan: PlanSummary) -> some View {
        let saved = stats.byGroup[.savings] ?? 0
        return Section {
            Button { editingSavings = true } label: {
                LabeledContent("Откладывать в месяц", value: Fmt.money(plan.savings))
            }
            .foregroundStyle(.primary)
            if plan.savings > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Отложено \(Fmt.money(saved)) из \(Fmt.money(plan.savings))").font(.subheadline)
                    GrowingProgress(value: min((saved / plan.savings).double, 1), tint: .green)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Накопления")
        } footer: {
            Text("Переводы в копилку, на накопительный счёт и вклад. Лучше откладывать сразу в день зарплаты.")
        }
    }

    // MARK: 50 / 30 / 20

    private func rulesSection(_ stats: MonthStats) -> some View {
        let income = max(stats.income, 1)
        let needs = ((stats.byGroup[.needs] ?? 0) / income).double
        let wants = ((stats.byGroup[.wants] ?? 0) / income).double
        let savings = (((stats.byGroup[.savings] ?? 0) + max(stats.balance, 0)) / income).double
        return Section {
            HStack(spacing: 20) {
                ActivityRings(rings: [
                    (needs / 0.5, Color(red: 0.98, green: 0.07, blue: 0.31)),
                    (wants / 0.3, Color(red: 0.6, green: 0.98, blue: 0.0)),
                    (savings / 0.2, Color(red: 0.0, green: 0.85, blue: 0.95))
                ])
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 8) {
                    ringLegend("Обязательное", needs, 0.5, Color(red: 0.98, green: 0.07, blue: 0.31))
                    ringLegend("Желания", wants, 0.3, Color(red: 0.4, green: 0.8, blue: 0.0))
                    ringLegend("Накопления", savings, 0.2, Color(red: 0.0, green: 0.7, blue: 0.85))
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Правило 50 / 30 / 20")
        } footer: {
            Text("Доля дохода за месяц. Первые два кольца лучше не замыкать, третье — замкнуть.")
        }
    }

    private func ringLegend(_ title: String, _ value: Double, _ target: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.subheadline.weight(.semibold))
            Text("\(Int((value * 100).rounded()))% / \(Int(target * 100))%")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(color)
        }
    }
}

/// Вложенные кольца прогресса в стиле приложения Активность.
struct ActivityRings: View {
    var rings: [(Double, Color)]

    var body: some View {
        // Кольца замыкаются при открытии, как в «Фитнесе»
        Growing(value: 1) { fill in
            drawing(fill)
        }
    }

    private func drawing(_ fill: Double) -> some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let width = size * 0.13
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                    let inset = CGFloat(index) * (width + 3)
                    Circle()
                        .stroke(ring.1.opacity(0.22), lineWidth: width)
                        .padding(inset + width / 2)
                    Circle()
                        .trim(from: 0, to: min(ring.0, 1) * fill)
                        .stroke(ring.1.gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(inset + width / 2)
                }
            }
        }
        .background(Color.black, in: Circle())
    }
}
