import SwiftUI

/// Какой картой платить: лучший кэшбэк по категориям и сколько недополучено за месяц.
struct CashbackView: View {
    @Environment(Store.self) private var store
    @State private var editing: CashbackCard?

    var body: some View {
        let report = store.cashbackReport()
        List {
            if !store.cashbackCards.isEmpty {
                Section {
                    LabeledContent("Получено за \(Fmt.month(store.month).lowercased())", value: Fmt.money(report.earned))
                    LabeledContent {
                        Text(Fmt.money(report.missed)).foregroundStyle(report.missed > 0 ? Color.orange : .secondary)
                    } label: {
                        Text("Недополучено")
                    }
                } footer: {
                    Text(report.missed > 0
                         ? "Столько бы ещё вернулось, если платить в каждой категории картой с лучшим кэшбэком."
                         : "Вы уже платите самыми выгодными картами.")
                }

                Section("Какой картой платить") {
                    ForEach(report.tips) { tip in
                        HStack(spacing: 12) {
                            CategoryBadge(category: tip.category)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.category.title)
                                Text(tip.card.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(percent(tip.rate)).font(.headline).foregroundStyle(.green)
                        }
                    }
                }
            }

            Section {
                ForEach(store.cashbackCards) { card in
                    Button { editing = card } label: {
                        LabeledContent {
                            Text("\(card.rates.count) \(Fmt.plural(card.rates.count, "категория", "категории", "категорий"))")
                        } label: {
                            Label(card.title, systemImage: "creditcard.fill").foregroundStyle(.primary)
                        }
                    }
                }
                .onDelete { $0.map { store.cashbackCards[$0].id }.forEach(store.deleteCashbackCard) }
                Button { editing = CashbackCard(title: "", bank: .tbank) } label: {
                    Label("Добавить карту", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Мои карты")
            } footer: {
                Text("Укажите категории повышенного кэшбэка. У Т-Банка они меняются каждый месяц — обновляйте их в начале месяца.")
            }
        }
        .navigationTitle("Кэшбэк")
        .sheet(item: $editing) { card in
            CashbackCardEditor(card: card, isNew: !store.cashbackCards.contains { $0.id == card.id })
        }
    }
}

func percent(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "ru_RU"))) + "%"
}

struct CashbackCardEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var card: CashbackCard
    var isNew: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название карты", text: $card.title)
                    Picker("Банк", selection: $card.bank) {
                        ForEach(Bank.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("На всё остальное: \(percent(card.base))", value: $card.base, in: 0...10, step: 0.5)
                } footer: {
                    Text("Банк нужен, чтобы понять, какой картой вы платили в выписке.")
                }
                Section("Повышенный кэшбэк") {
                    ForEach(Category.expenseCases.filter { $0 != .transfersOut }) { c in
                        let value = card.rates[c] ?? 0
                        Stepper(value: Binding(get: { value }, set: { card.rates[c] = $0 > 0 ? $0 : nil }), in: 0...30, step: 1) {
                            HStack(spacing: 10) {
                                CategoryBadge(category: c, size: 26)
                                Text(c.title)
                                Spacer()
                                if value > 0 { Text(percent(value)).foregroundStyle(.green) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Новая карта" : card.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Добавить" : "Готово") { store.saveCashbackCard(card); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(card.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
