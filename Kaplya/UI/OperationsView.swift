import SwiftUI

enum OperationFilter: String, CaseIterable, Identifiable {
    case all, expenses, income, own, unsorted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:      return "Все"
        case .expenses: return "Расходы"
        case .income:   return "Доходы"
        case .own:      return "Переводы себе"
        case .unsorted: return "Без категории"
        }
    }

    func matches(_ t: Transaction) -> Bool {
        switch self {
        case .all:      return true
        case .expenses: return t.category.isExpense
        case .income:   return t.category.isIncome
        case .own:      return t.category.isInternal
        case .unsorted: return [.transfersOut, .transfersIn, .otherExpense, .otherIncome].contains(t.category)
        }
    }
}

/// Операции как в Wallet: список по дням, поиск, фильтр в меню, свайпы, отдельная страница операции.
struct OperationsView: View {
    @Environment(Store.self) private var store
    @State private var query = ""
    @State private var filter: OperationFilter = .all
    @State private var categoryFor: Transaction?
    /// Флаг для скриншотов: -edit сразу открывает страницу перевода без категории
    @State private var opened: Transaction?

    var body: some View {
        let items = store.monthTransactions.filter { t in
            filter.matches(t) && (query.isEmpty
                || t.title.localizedCaseInsensitiveContains(query)
                || t.category.title.localizedCaseInsensitiveContains(query))
        }
        let days = Dictionary(grouping: items) { Store.calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }

        NavigationStack {
            List {
                ForEach(days, id: \.key) { day, list in
                    Section {
                        ForEach(list.sorted { $0.date > $1.date }) { t in
                            NavigationLink { TransactionDetail(id: t.id) } label: { TransactionRow(t: t) }
                                .swipeActions(edge: .trailing) {
                                    Button { categoryFor = t } label: { Label("Категория", systemImage: "tag") }
                                        .tint(.indigo)
                                }
                                .contextMenu {
                                    Button("Изменить категорию", systemImage: "tag") { categoryFor = t }
                                    Button("Скопировать сумму", systemImage: "doc.on.doc") {
                                        UIPasteboard.general.string = Fmt.exact(t.amount)
                                    }
                                }
                        }
                    } header: {
                        Text(Fmt.day(day).capitalized)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if days.isEmpty {
                    if store.transactions.isEmpty {
                        ContentUnavailableView("Нет операций", systemImage: "tray",
                                               description: Text("Загрузите выписку на вкладке «Счета»."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query, prompt: "Магазин, получатель, категория")
            .navigationTitle("Операции")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Показать", selection: $filter) {
                            ForEach(OperationFilter.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Image(systemName: filter == .all
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .navigationDestination(item: $opened) { t in TransactionDetail(id: t.id) }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-edit"), opened == nil {
                    opened = store.monthTransactions.first { $0.category == .transfersOut }
                }
            }
            .sheet(item: $categoryFor) { t in
                NavigationStack { CategoryPicker(id: t.id, closeOnPick: true) }
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

/// Страница операции: крупная сумма сверху, дальше сгруппированные строки, как в Настройках.
struct TransactionDetail: View {
    @Environment(Store.self) private var store
    var id: Transaction.ID

    var body: some View {
        if let t = store.transactions.first(where: { $0.id == id }) {
            List {
                Section {
                    VStack(spacing: 10) {
                        CategoryBadge(category: t.category, size: 64)
                        Text(Fmt.exact(t.amount, sign: t.amount > 0))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text(t.title).font(.headline).multilineTextAlignment(.center)
                        Text(Fmt.dateTime(t.date)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    NavigationLink {
                        CategoryPicker(id: t.id, closeOnPick: false)
                    } label: {
                        LabeledContent("Категория", value: t.category.title)
                    }
                    Toggle(isOn: Binding(
                        get: { store.rules.contains { $0.match == t.counterparty } },
                        set: { on in
                            if on {
                                store.setCategory(t.category, for: t.id, remember: true)
                            } else if let rule = store.rules.first(where: { $0.match == t.counterparty }) {
                                store.deleteRule(rule)
                            }
                        })) {
                        Text("Применять к будущим")
                    }
                } footer: {
                    Text("Операции от «\(t.counterparty)» будут сами попадать в эту категорию, в том числе из новых выписок.")
                }

                Section("Подробности") {
                    LabeledContent("Банк", value: t.bank.title)
                    if !t.card.isEmpty { LabeledContent("Карта", value: t.card) }
                    if !t.bankCategory.isEmpty { LabeledContent("Категория банка", value: t.bankCategory) }
                    if !t.mcc.isEmpty { LabeledContent("MCC", value: t.mcc) }
                }
            }
            .navigationTitle("Операция")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Выбор категории: список с галочкой, как выбор рингтона в Настройках.
struct CategoryPicker: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var id: Transaction.ID
    var closeOnPick: Bool

    var body: some View {
        let t = store.transactions.first { $0.id == id }
        let options = (t?.amount ?? 0) < 0 ? Category.expenseCases : Category.incomeCases
        List {
            Section {
                ForEach(options) { c in
                    row(c, current: t?.category)
                }
            }
            Section {
                row(.internalTransfer, current: t?.category)
            } footer: {
                Text("Переводы между своими картами не считаются ни расходом, ни доходом.")
            }
        }
        .navigationTitle("Категория")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if closeOnPick {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }

    private func row(_ c: Category, current: Category?) -> some View {
        Button {
            store.setCategory(c, for: id, remember: store.rules.contains { $0.match == store.transactions.first { $0.id == id }?.counterparty })
            if closeOnPick { dismiss() }
        } label: {
            HStack(spacing: 12) {
                CategoryBadge(category: c)
                Text(c.title).foregroundStyle(.primary)
                Spacer()
                if c == current {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: current)
    }
}
