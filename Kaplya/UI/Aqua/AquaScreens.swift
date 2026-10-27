import SwiftUI
import UniformTypeIdentifiers

// MARK: Строка операции

struct AquaRow: View {
    var t: Transaction

    var body: some View {
        HStack(spacing: 10) {
            AquaIcon(symbol: t.category.symbol, color: t.category.systemColor, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text).lineLimit(1)
                Text("\(t.category.title) · \(t.bank.title)").font(Aqua.font(12)).foregroundStyle(Aqua.label).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(Fmt.exact(t.amount, sign: true))
                .font(Aqua.font(15, .bold))
                .foregroundStyle(t.category.isInternal ? Aqua.line : (t.amount > 0 ? Aqua.positive : Aqua.link))
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Aqua.line)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: Операции

struct AquaOperations: View {
    @Environment(Store.self) private var store
    @State private var query = ""
    @State private var filter: OperationFilter = .all
    @State private var opened: Transaction?

    var body: some View {
        let items = store.monthTransactions.filter { t in
            filter.matches(t) && (query.isEmpty || t.title.localizedCaseInsensitiveContains(query)
                                  || t.category.title.localizedCaseInsensitiveContains(query))
        }
        let days = Dictionary(grouping: items) { Store.calendar.startOfDay(for: $0.date) }.sorted { $0.key > $1.key }

        NavigationStack {
            VStack(spacing: 0) {
                AquaNavBar(title: "Операции")
                // Строка поиска iOS 6: серо-голубая панель с белым скруглённым полем
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .bold)).foregroundStyle(Aqua.label)
                    TextField("Магазин, получатель, категория", text: $query).font(Aqua.font(15))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Aqua.card).overlay(Capsule().stroke(Aqua.line, lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(LinearGradient(colors: [Aqua.barTop.opacity(0.8), Aqua.barBottom.opacity(0.6)],
                                           startPoint: .top, endPoint: .bottom))

                ScrollView {
                    VStack(spacing: 16) {
                        AquaSegments(items: OperationFilter.allCases.map { ($0, $0.title) }, selection: $filter)
                        ForEach(days, id: \.key) { day, list in
                            AquaSection(title: Fmt.day(day).capitalized) {
                                VStack(spacing: 0) {
                                    let sorted = list.sorted { $0.date > $1.date }
                                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, t in
                                        Button { opened = t } label: { AquaRow(t: t) }.buttonStyle(.plain)
                                        if index < sorted.count - 1 { Divider().overlay(Aqua.line) }
                                    }
                                }
                                .groupCard()
                            }
                        }
                    }
                    .padding(10)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $opened) { AquaTransactionPage(id: $0.id, back: "Операции") }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-edit"), opened == nil {
                    opened = store.monthTransactions.first { $0.category == .transfersOut }
                }
            }
        }
    }
}

// MARK: Страница операции

struct AquaTransactionPage: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var id: Transaction.ID
    var back: String

    var body: some View {
        if let t = store.transactions.first(where: { $0.id == id }) {
            let remembered = store.rules.contains { $0.match == t.counterparty }
            VStack(spacing: 0) {
                AquaNavBar(title: "Операция") {
                    AquaBackButton(title: back) { dismiss() }
                } trailing: { EmptyView() }
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            AquaIcon(symbol: t.category.symbol, color: t.category.systemColor, size: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Fmt.exact(t.amount, sign: true)).font(Aqua.font(26, .bold)).foregroundStyle(Aqua.text)
                                Text(t.title).font(Aqua.font(14, .bold)).foregroundStyle(Aqua.label)
                                Text("\(Fmt.dateTime(t.date)) · \(t.bank.title)").font(Aqua.font(12)).foregroundStyle(Aqua.label)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .groupCard()

                        AquaSection(title: "Категория") {
                            VStack(spacing: 0) {
                                let options = (t.amount < 0 ? Category.expenseCases : Category.incomeCases) + [.internalTransfer]
                                ForEach(Array(options.enumerated()), id: \.element) { index, c in
                                    Button {
                                        store.setCategory(c, for: t.id, remember: remembered)
                                    } label: {
                                        HStack(spacing: 10) {
                                            AquaIcon(symbol: c.symbol, color: c.systemColor, size: 26)
                                            Text(c.title).font(Aqua.font(15, .bold))
                                                .foregroundStyle(c == t.category ? Aqua.selection : Aqua.text)
                                            Spacer()
                                            if c == t.category {
                                                Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy))
                                                    .foregroundStyle(Aqua.selection)
                                            }
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if index < options.count - 1 { Divider().overlay(Aqua.line) }
                                }
                            }
                            .groupCard()
                        }

                        Toggle(isOn: Binding(
                            get: { remembered },
                            set: { on in
                                if on {
                                    store.setCategory(t.category, for: t.id, remember: true)
                                } else if let rule = store.rules.first(where: { $0.match == t.counterparty }) {
                                    store.deleteRule(rule)
                                }
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Применять к будущим").font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text)
                                Text("Все операции «\(t.counterparty)»").font(Aqua.font(12)).foregroundStyle(Aqua.label)
                            }
                        }
                        .tint(Aqua.blue)
                        .padding(12)
                        .groupCard()
                    }
                    .padding(10)
                }
            }
            .background(Pinstripes())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: Советы

struct AquaInsights: View {
    @Environment(Store.self) private var store
    @State private var showRecap = false
    @State private var showTax = false

    var body: some View {
        let insights = Analytics.insights(store.transactions, month: store.month)
        let subs = Analytics.subscriptions(store.transactions)
        let merchants = Analytics.topMerchants(store.transactions, month: store.month)
        VStack(spacing: 0) {
            AquaNavBar(title: "Советы")
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        AquaLinkRow(symbol: "rosette", color: .purple, title: "Итоги \(Fmt.monthGenitiveOnly(store.recapMonth))") { showRecap = true }
                        Divider().overlay(Aqua.line)
                        AquaLinkRow(symbol: "percent", color: .green, title: "Налоговый вычет",
                                    value: refundText) { showTax = true }
                    }
                    .groupCard()
                    ForEach(insights) { insight in
                        HStack(alignment: .top, spacing: 12) {
                            AquaIcon(symbol: insight.symbol, color: tone(insight), size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title).font(Aqua.font(16, .bold)).foregroundStyle(Aqua.text)
                                Text(insight.text).font(Aqua.font(14)).foregroundStyle(Aqua.label)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .groupCard()
                    }
                    if !subs.isEmpty {
                        AquaSection(title: "Регулярные платежи") {
                            VStack(spacing: 0) {
                                ForEach(Array(subs.enumerated()), id: \.element.id) { index, s in
                                    HStack(spacing: 10) {
                                        AquaIcon(symbol: s.category.symbol, color: s.category.systemColor, size: 28)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(s.name).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text).lineLimit(1)
                                            Text("\(Fmt.money(s.amount * 12)) в год").font(Aqua.font(12)).foregroundStyle(Aqua.label)
                                        }
                                        Spacer()
                                        Text(Fmt.money(s.amount)).font(Aqua.font(15)).foregroundStyle(Aqua.link)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    if index < subs.count - 1 { Divider().overlay(Aqua.line) }
                                }
                            }
                            .groupCard()
                        }
                    }
                    if !merchants.isEmpty {
                        AquaSection(title: "Куда ушло больше всего") {
                            VStack(spacing: 0) {
                                ForEach(Array(merchants.enumerated()), id: \.element.id) { index, m in
                                    HStack(spacing: 10) {
                                        Text("\(index + 1)").font(Aqua.font(14, .bold)).onBar()
                                            .frame(width: 26, height: 26)
                                            .background(AquaGel(shape: Circle(), color: m.category.systemColor))
                                        Text(m.name).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text).lineLimit(1)
                                        Spacer()
                                        Text(Fmt.money(m.amount)).font(Aqua.font(15)).foregroundStyle(Aqua.link)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    if index < merchants.count - 1 { Divider().overlay(Aqua.line) }
                                }
                            }
                            .groupCard()
                        }
                    }
                }
                .padding(10)
            }
        }
        .sheet(isPresented: $showRecap) { SystemSheet { RecapView(month: store.recapMonth) } }
        .sheet(isPresented: $showTax) { SystemSheet { TaxView() } }
    }

    private var refundText: String {
        let r = store.taxReport(year: store.taxYears.first ?? Store.calendar.component(.year, from: Date())).refund
        return r > 0 ? Fmt.money(r) : ""
    }

    private func tone(_ insight: Insight) -> Color {
        switch insight.tone {
        case .warning: return .orange
        case .tip:     return Aqua.blue
        case .good:    return .green
        }
    }
}

// MARK: Выписки

struct AquaImports: View {
    @Environment(Store.self) private var store
    @State private var picking = false
    @State private var outcome: ImportOutcome?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AquaNavBar(title: "Выписки")
                ScrollView {
                    VStack(spacing: 16) {
                        AquaButton(title: "Загрузить выписку", symbol: "tray.and.arrow.down.fill") { picking = true }
                        Text("PDF или CSV Т-Банка, PDF Сбера · можно несколько сразу")
                            .font(Aqua.font(13)).foregroundStyle(Aqua.label).embossed()

                        if let outcome {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(outcome.errors.isEmpty ? "Выписка загружена" : "Есть проблемы",
                                      systemImage: outcome.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text)
                                ForEach(outcome.records) { r in
                                    Text("\(r.fileName): добавлено \(r.added)").font(Aqua.font(13)).foregroundStyle(Aqua.label)
                                }
                                ForEach(outcome.errors, id: \.0) { name, message in
                                    Text("\(name): \(message)").font(Aqua.font(13)).foregroundStyle(Aqua.label)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .groupCard()
                        }

                        AquaSection(title: "Уведомления") {
                            AquaRemindersCard()
                        }

                        AquaSection(title: "Автозагрузка") {
                            AquaAutoImportCard()
                        }

                        AquaSection(title: "Как выгрузить выписку") {
                            VStack(spacing: 0) {
                                NavigationLink { HowToView(bank: .tbank) } label: { linkRow("Т-Банк — PDF или CSV", "doc.richtext", .yellow) }
                                Divider().overlay(Aqua.line)
                                NavigationLink { HowToView(bank: .sber) } label: { linkRow("Сбер — PDF", "doc.richtext", .green) }
                            }
                            .buttonStyle(.plain)
                            .groupCard()
                        }

                        if !store.imports.isEmpty {
                            AquaSection(title: "Загружено") {
                                VStack(spacing: 0) {
                                    ForEach(Array(store.imports.enumerated()), id: \.element.id) { index, r in
                                        HStack(spacing: 10) {
                                            AquaIcon(symbol: r.fileName.lowercased().hasSuffix("pdf") ? "doc.richtext" : "tablecells",
                                                     color: r.bank == .tbank ? .yellow : .green, size: 28)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(r.fileName).font(Aqua.font(14, .bold)).foregroundStyle(Aqua.text).lineLimit(1)
                                                Text("\(r.bank.title) · \(r.added) \(Fmt.plural(r.added, "операция", "операции", "операций"))")
                                                    .font(Aqua.font(12)).foregroundStyle(Aqua.label)
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        if index < store.imports.count - 1 { Divider().overlay(Aqua.line) }
                                    }
                                }
                                .groupCard()
                            }
                        }

                        AquaSection(title: "Оформление") {
                            AppearancePicker()
                                .padding(.vertical, 8)
                                .groupCard()
                        }

                        AquaSection(title: "Данные") {
                            VStack(spacing: 10) {
                                if store.transactions.isEmpty {
                                    AquaButton(title: "Загрузить демо-данные", color: Color(red: 0.45, green: 0.50, blue: 0.58)) { store.loadDemo() }
                                }
                                AquaButton(title: "Удалить все данные", color: Color(red: 0.85, green: 0.15, blue: 0.12)) { confirmDelete = true }
                            }
                        }
                    }
                    .padding(10)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .pdf, .plainText, .text],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                outcome = ImportOutcome.run(urls, store: store)
            }
            .confirmationDialog("Все операции, выписки и запомненные получатели будут удалены с этого iPhone.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить все данные", role: .destructive) { store.deleteAll() }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private func linkRow(_ title: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            AquaIcon(symbol: symbol, color: color, size: 28)
            Text(title).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Aqua.line)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
