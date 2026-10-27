import SwiftUI

/// Поле суммы крупным шрифтом, как ввод суммы в Wallet.
struct BigAmountField: View {
    @Binding var value: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            // Пустое поле с серой подсказкой «0», иначе ввод дописывается к нулю
            TextField("0", value: Binding<Double?>(get: { value == 0 ? nil : value }, set: { value = $0 ?? 0 }),
                      format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("₽").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Ввод одной суммы.
struct AmountEditor: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var caption: String
    @State private var amount: Double
    var onSave: (Decimal) -> Void

    init(title: String, caption: String, value: Decimal, onSave: @escaping (Decimal) -> Void) {
        self.title = title
        self.caption = caption
        self.onSave = onSave
        _amount = State(initialValue: value.double)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BigAmountField(value: $amount)
                } footer: {
                    Text(caption)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { onSave(Decimal(amount)); dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Какой доход распределять: фактический за месяц или ожидаемый.
struct IncomeEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var useExpected = false
    @State private var amount: Double = 0

    var body: some View {
        let actual = Analytics.stats(store.transactions, month: store.month).income
        NavigationStack {
            Form {
                Section {
                    Toggle("Задать вручную", isOn: $useExpected.animation())
                    if useExpected {
                        BigAmountField(value: $amount)
                    } else {
                        LabeledContent("Доход за \(Fmt.month(store.month).lowercased())", value: Fmt.money(actual))
                    }
                } footer: {
                    Text(useExpected
                         ? "Удобно, если зарплата ещё не пришла: план строится заранее."
                         : "План строится по фактическим поступлениям из выписок, без переводов между своими счетами.")
                }
            }
            .navigationTitle("Доход для плана")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        store.setExpectedIncome(useExpected ? Decimal(amount) : nil)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                useExpected = store.incomePlan.expectedIncome != nil
                amount = (store.incomePlan.expectedIncome ?? actual).double
            }
        }
        .presentationDetents([.medium])
    }
}

/// Лимит на категорию.
struct LimitEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var category: Category?
    var isNew: Bool
    @State private var amount: Double = 0

    var body: some View {
        let spentAvg = average(for: category)
        NavigationStack {
            Form {
                Section {
                    Picker("Категория", selection: $category) {
                        Text("Не выбрана").tag(Category?.none)
                        ForEach(Category.expenseCases) { c in
                            Label(c.title, systemImage: c.symbol).tag(Category?.some(c))
                        }
                    }
                    .disabled(!isNew)
                }
                Section {
                    BigAmountField(value: $amount)
                } footer: {
                    if spentAvg > 0 {
                        Text("В среднем на «\(category?.title ?? "")» уходит \(Fmt.money(spentAvg)) в месяц.")
                    }
                }
                if !isNew, let category {
                    Section {
                        Button("Удалить лимит", role: .destructive) {
                            store.setLimit(category, nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Новый лимит" : (category?.title ?? "Лимит"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Добавить" : "Готово") {
                        if let category { store.setLimit(category, Decimal(amount)) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(category == nil || amount <= 0)
                }
            }
            .onAppear {
                if let category, let limit = store.limits.first(where: { $0.category == category }) {
                    amount = limit.amount.double
                }
            }
        }
    }

    private func average(for category: Category?) -> Decimal {
        guard let category else { return 0 }
        let months = (1...3).compactMap { Store.calendar.date(byAdding: .month, value: -$0, to: store.month) }
            .map { Analytics.stats(store.transactions, month: $0) }
            .filter { $0.expenses > 0 }
        guard !months.isEmpty else { return 0 }
        let sum = months.reduce(Decimal(0)) { acc, s in acc + (s.byCategory.first { $0.category == category }?.amount ?? 0) }
        return sum / Decimal(months.count)
    }
}

/// Регулярный платёж: как событие в Календаре — название, сумма, категория, повтор, дата.
struct RecurringEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var payment: RecurringPayment
    var isNew: Bool
    @State private var amount: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $payment.title)
                    BigAmountField(value: $amount)
                }
                Section {
                    Picker("Категория", selection: $payment.category) {
                        ForEach(Category.expenseCases) { c in
                            Label(c.title, systemImage: c.symbol).tag(c)
                        }
                    }
                    Picker("Повтор", selection: $payment.period) {
                        ForEach(Period.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Дата платежа", selection: $payment.startDate, displayedComponents: .date)
                } footer: {
                    Text("В месяц: \(Fmt.money(payment.period.perMonth(Decimal(amount)))). Когда платёж появится в выписке, он отметится как оплаченный.")
                }
                if !isNew {
                    Section {
                        Button("Удалить платёж", role: .destructive) {
                            store.deleteRecurring(payment.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Новый платёж" : "Платёж")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Добавить" : "Готово") {
                        payment.amount = Decimal(amount)
                        if payment.match.isEmpty { payment.match = Transaction.normalize(payment.title) }
                        store.saveRecurring(payment)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(payment.title.trimmingCharacters(in: .whitespaces).isEmpty || amount <= 0)
                }
            }
            .onAppear { amount = payment.amount.double }
        }
    }
}

/// Найденные в выписках регулярные платежи — добавить одним нажатием.
struct SuggestedPaymentsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let suggestions = store.suggestedRecurring()
        NavigationStack {
            List {
                Section {
                    ForEach(suggestions) { s in
                        HStack(spacing: 12) {
                            CategoryBadge(category: s.category)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).lineLimit(1)
                                Text("\(Fmt.money(s.amount)) каждый месяц").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Добавить") { store.saveRecurring(s) }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                        }
                    }
                } footer: {
                    Text("Платежи одному получателю примерно на одну сумму раз в месяц.")
                }
            }
            .overlay {
                if suggestions.isEmpty {
                    ContentUnavailableView("Все добавлены", systemImage: "checkmark.circle",
                                           description: Text("Новых регулярных платежей в выписках нет."))
                }
            }
            .navigationTitle("Найдено в выписках")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.fontWeight(.semibold) }
            }
        }
    }
}

/// Предлагаемый план: что изменится, и «Применить».
struct AutoPlanSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let plan = store.suggestedPlan()
        let summary = store.planSummary()
        let total = summary.recurring + plan.savings + plan.limits.reduce(0) { $0 + $1.amount }
        NavigationStack {
            List {
                Section {
                    LabeledContent("Доход", value: Fmt.money(summary.income))
                    LabeledContent("Регулярные платежи", value: Fmt.money(summary.recurring))
                    LabeledContent("Накопления — 20%", value: Fmt.money(plan.savings))
                    LabeledContent("Останется свободно", value: Fmt.money(summary.income - total))
                } footer: {
                    Text("Накопления — по правилу 50/30/20, лимиты — по средним тратам за три прошлых месяца. Если не помещаются в доход, лимиты уменьшаются поровну.")
                }
                Section("Лимиты") {
                    ForEach(plan.limits) { limit in
                        HStack(spacing: 12) {
                            CategoryBadge(category: limit.category)
                            Text(limit.category.title)
                            Spacer()
                            Text(Fmt.money(limit.amount)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Предлагаемый план")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить") { store.applySuggestedPlan(); dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}
