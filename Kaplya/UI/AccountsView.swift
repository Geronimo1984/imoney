import SwiftUI
import UniformTypeIdentifiers

/// Счета как в Wallet: карты стопкой, «+» для загрузки выписки, итог — лист снизу.
struct AccountsView: View {
    @Environment(Store.self) private var store
    @State private var picking = false
    @State private var outcome: ImportOutcome?
    @State private var confirmDeleteAll = false

    var body: some View {
        let stats = Analytics.stats(store.transactions, month: store.month)
        let banks = Bank.allCases.filter { b in store.transactions.contains { $0.bank == b } }

        NavigationStack {
            List {
                Section {
                    VStack(spacing: -120) {
                        ForEach(banks) { bank in
                            WalletCard(bank: bank, spent: stats.byBank[bank] ?? 0,
                                       card: store.transactions.first { $0.bank == bank }?.card ?? "")
                        }
                    }
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
                            Button("Удалить", systemImage: "trash", role: .destructive) { store.deleteImport(record) }
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
                        Label("Кэшбэк по картам", systemImage: "creditcard.fill")
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
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }
}

/// Итог загрузки — лист на полэкрана с «Готово» и «Отменить загрузку».
struct ImportSummarySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var outcome: ImportOutcome

    var body: some View {
        let added = outcome.records.reduce(0) { $0 + $1.added }
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: outcome.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(outcome.errors.isEmpty ? Color.green : .orange)
                        // verbatim: иначе число выводится по-английски, «3,018»
                        Text(verbatim: added > 0 ? "Добавлено \(added) \(Fmt.plural(added, "операция", "операции", "операций"))" : "Новых операций нет")
                            .font(.title3.weight(.bold))
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
                            outcome.records.forEach(store.deleteImport)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Выписка загружена")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }
}
