import SwiftUI
import UniformTypeIdentifiers

/// Счета как в Wallet: карты стопкой, «+» для загрузки выписки, итог — лист снизу.
struct AccountsView: View {
    @Environment(Store.self) private var store
    @State private var picking = false
    @State private var outcome: ImportOutcome?
    @State private var confirmDeleteAll = false
    @State private var selectedBank: Bank?
    @Namespace private var cards

    var body: some View {
        let stats = Analytics.stats(store.transactions, month: store.month)
        let banks = Bank.allCases.filter { b in store.transactions.contains { $0.bank == b } }

        NavigationStack {
            List {
                Section {
                    cardStack(banks, stats)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    ForEach(store.imports) { record in
                        HStack(spacing: 12) {
                            Image(systemName: record.fileName.lowercased().hasSuffix("pdf") ? "doc.richtext" : "tablecells")
                                .font(.title3).foregroundStyle(.tint).frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.fileName).lineLimit(1)
                                Text("\(record.bank.title) · \(record.added) \(Fmt.plural(record.added, "операция", "операции", "операций"))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Удалить", systemImage: "trash", role: .destructive) { Haptic.delete(); Motion.animate { store.deleteImport(record) } }
                        }
                    }
                } header: {
                    Text("Выписки")
                } footer: {
                    Text("Повторная загрузка той же выписки не создаёт дублей. Данные хранятся только на этом iPhone.")
                }

                Section {
                    AppearancePicker()
                } header: {
                    Text("Оформление")
                } footer: {
                    Text("Глянцевое — в духе iPhone начала 2010-х: выпуклые кнопки, колесо категорий, фон в полоску. Оба оформления сами становятся светлыми или тёмными вместе с телефоном.")
                }

                Section {
                    NavigationLink { CashbackView() } label: {
                        Label("Кэшбэк и проценты", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    NavigationLink { TaxView() } label: {
                        Label("Налоговый вычет", systemImage: "percent")
                    }
                }

                RemindersSection()

                AutoImportSection()

                Section("Как выгрузить выписку") {
                    NavigationLink { HowToView(bank: .tbank) } label: {
                        Label("Т-Банк — PDF или CSV", systemImage: "doc.richtext")
                    }
                    NavigationLink { HowToView(bank: .sber) } label: {
                        Label("Сбер — PDF", systemImage: "doc.richtext")
                    }
                }

                Section {
                    NavigationLink { RulesView() } label: {
                        LabeledContent {
                            Text("\(store.rules.count)")
                        } label: {
                            Label("Запомненные получатели", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }
                }

                Section {
                    // Демо заменяет все данные, поэтому доступно только пока своих данных нет
                    if store.transactions.isEmpty {
                        Button("Загрузить демо-данные") { store.loadDemo() }
                    }
                    Button("Удалить все данные", role: .destructive) { confirmDeleteAll = true }
                        .disabled(store.transactions.isEmpty && store.debts.isEmpty)
                }
            }
            .listStyle(.insetGrouped)
            .overlay { openedCard(banks, stats) }
            .navigationTitle("Счета")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { picking = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Загрузить выписку")
                }
            }
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: [.commaSeparatedText, .pdf, .plainText, .text],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                outcome = ImportOutcome.run(urls, store: store)
            }
            .sheet(item: $outcome) { outcome in
                ImportSummarySheet(outcome: outcome)
                    .presentationDetents([.medium])
            }
            .confirmationDialog("Все операции, выписки и запомненные получатели будут удалены с этого iPhone.",
                                isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Удалить все данные", role: .destructive) { store.deleteAll() }
                Button("Отмена", role: .cancel) {}
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-importSheet"), outcome == nil {
                    outcome = ImportOutcome(records: Array(store.imports.prefix(2)))
                }
            }
        }
    }
}

extension AccountsView {
    /// Стопка карт как в Wallet. Раскрытый счёт показывается слоем поверх списка, а не внутри строки:
    /// список меняет высоту строки мгновенно, не в такт анимации, — карты обрезались, а разделы ниже прыгали.
    /// Пока счёт открыт, в строке остаётся пустое место той же высоты.
    private func cardStack(_ banks: [Bank], _ stats: MonthStats) -> some View {
        ZStack(alignment: .top) {
            Color.clear.frame(height: 200 + CGFloat(max(banks.count - 1, 0)) * 80)
            if selectedBank == nil {
                VStack(spacing: -120) {
                    ForEach(banks) { bank in card(bank, stats) }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedBank)
    }

    /// Выбранная карта наверху, под ней итоги и последние операции, остальные карты — стопкой внизу.
    @ViewBuilder
    private func openedCard(_ banks: [Bank], _ stats: MonthStats) -> some View {
        if let bank = selectedBank, banks.contains(bank) {
            ScrollView {
                VStack(spacing: 14) {
                    // Выбранная карта выше остальных — и при возврате в стопку не пролетает под ними
                    card(bank, stats).zIndex(1)
                    BankDetail(bank: bank)
                        .transition(.opacity.combined(with: .offset(y: 40)))
                    VStack(spacing: -176) {
                        ForEach(banks.filter { $0 != bank }) { other in
                            card(other, stats).scaleEffect(0.94, anchor: .top)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.12).delay(0.2))))
        }
    }

    private func card(_ bank: Bank, _ stats: MonthStats) -> some View {
        Button {
            Motion.animate(.spring(response: 0.42, dampingFraction: 0.86)) {
                selectedBank = (selectedBank == bank) ? nil : bank
            }
        } label: {
            WalletCard(bank: bank, spent: stats.byBank[bank] ?? 0,
                       card: store.transactions.first { $0.bank == bank }?.card ?? "")
        }
        .buttonStyle(CardPress())
        .matchedGeometryEffect(id: bank, in: cards)
        .accessibilityLabel(bank.title)
        .accessibilityValue("Расходы за месяц \(Fmt.money(stats.byBank[bank] ?? 0))")
    }
}

/// Карта при нажатии чуть проседает, как в Wallet.
private struct CardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Итоги выбранного счёта за месяц и последние операции; все — на отдельном экране.
private struct BankDetail: View {
    @Environment(Store.self) private var store
    var bank: Bank

    var body: some View {
        let items = store.monthTransactions.filter { $0.bank == bank }.sorted { $0.date > $1.date }
        let income = items.reduce(Decimal(0)) { $0 + $1.incomeValue }
        let spent = items.reduce(Decimal(0)) { $0 + $1.expenseValue }

        VStack(spacing: 0) {
            HStack {
                BankFigure(title: "Пришло", value: Fmt.money(income), color: .green)
                Divider().frame(height: 34)
                BankFigure(title: "Ушло", value: Fmt.money(spent), color: .primary)
                Divider().frame(height: 34)
                BankFigure(title: "Операций", value: "\(items.count)", color: .secondary)
            }
            .padding(.vertical, 12)
            ForEach(items.prefix(5)) { t in
                Divider().padding(.leading, 68)
                TransactionRow(t: t).padding(.horizontal, 16).padding(.vertical, 8)
            }
            if items.count > 5 {
                Divider().padding(.leading, 16)
                NavigationLink { BankScreen(bank: bank) } label: {
                    HStack {
                        Text("Все операции")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
            }
            if items.isEmpty {
                Divider()
                Text("За \(Fmt.month(store.month).lowercased()) операций нет")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 14)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct BankFigure: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Экран счёта: карта, итоги месяца и все операции этого банка.
struct BankScreen: View {
    @Environment(Store.self) private var store
    var bank: Bank

    var body: some View {
        let items = store.monthTransactions.filter { $0.bank == bank }.sorted { $0.date > $1.date }
        let income = items.reduce(Decimal(0)) { $0 + $1.incomeValue }
        let spent = items.reduce(Decimal(0)) { $0 + $1.expenseValue }

        List {
            Section {
                WalletCard(bank: bank, spent: spent, card: store.transactions.first { $0.bank == bank }?.card ?? "")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                HStack {
                    BankFigure(title: "Пришло", value: Fmt.money(income), color: .green)
                    Divider().frame(height: 34)
                    BankFigure(title: "Ушло", value: Fmt.money(spent), color: .primary)
                    Divider().frame(height: 34)
                    BankFigure(title: "Операций", value: "\(items.count)", color: .secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Операции за \(Fmt.month(store.month).lowercased())") {
                ForEach(items) { t in
                    NavigationLink { TransactionDetail(id: t.id) } label: { TransactionRow(t: t) }
                }
                if items.isEmpty {
                    Text("Операций нет").foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(bank.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Карта банка в стиле Wallet.
struct WalletCard: View {
    var bank: Bank
    var spent: Decimal
    var card: String

    var body: some View {
        let colors: [Color] = bank == .tbank
            ? [Color(red: 0.16, green: 0.16, blue: 0.18), Color(red: 0.05, green: 0.05, blue: 0.06)]
            : [Color(red: 0.10, green: 0.72, blue: 0.35), Color(red: 0.02, green: 0.48, blue: 0.30)]
        VStack(alignment: .leading) {
            HStack {
                Text(bank.title).font(.title3.weight(.bold))
                Spacer()
                Text(bank.short)
                    .font(.headline.weight(.black))
                    .foregroundStyle(bank == .tbank ? Color.black : .white)
                    .frame(width: 34, height: 34)
                    .background(bank == .tbank ? Color.yellow : Color.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Расходы за месяц").font(.caption).opacity(0.75)
                    Text(Fmt.money(spent)).font(.title2.weight(.semibold))
                }
                Spacer()
                Text(card.isEmpty ? "" : "•• " + card.filter(\.isNumber).suffix(4)).font(.subheadline.monospacedDigit()).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(height: 200)
        // Тень только у подложки: тень на всей карте пересчитывается по каждому тексту в каждом кадре анимации
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        }
    }
}

/// Итог загрузки — лист на полэкрана с «Готово» и «Отменить загрузку».
struct ImportSummarySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var outcome: ImportOutcome
    @State private var appeared = false

    var body: some View {
        let added = outcome.records.reduce(0) { $0 + $1.added }
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: outcome.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(outcome.errors.isEmpty ? Color.green : .orange)
                            .symbolEffect(.bounce, value: appeared)
                            .scaleEffect(appeared || Motion.reduced ? 1 : 0.4)
                            .opacity(appeared || Motion.reduced ? 1 : 0)
                        if added > 0 {
                            // Число досчитывается; verbatim — иначе число выводится по-английски, «3,018»
                            CountingText(value: Double(added)) { v in
                                let n = Int(v.rounded())
                                return "Добавлено \(n) \(Fmt.plural(n, "операция", "операции", "операций"))"
                            }
                            .font(.title3.weight(.bold))
                        } else {
                            Text("Новых операций нет").font(.title3.weight(.bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)
                Section {
                    ForEach(outcome.records) { r in
                        LabeledContent(r.fileName, value: "+\(r.added)")
                    }
                    ForEach(outcome.errors, id: \.0) { name, message in
                        LabeledContent(name, value: message)
                    }
                }
                if !outcome.records.isEmpty {
                    Section {
                        Button("Отменить загрузку", role: .destructive) {
                            Motion.animate { outcome.records.forEach(store.deleteImport) }
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { Motion.animate(.spring(response: 0.4, dampingFraction: 0.55)) { appeared = true } }
            .sensoryFeedback(outcome.errors.isEmpty ? .success : .warning, trigger: appeared) { _, new in new }
            .navigationTitle("Выписка загружена")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }
}
