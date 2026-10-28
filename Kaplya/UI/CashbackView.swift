import SwiftUI

/// Сколько банки вернули: кэшбэк, бонусы и проценты на остаток — по поступлениям из выписок.
struct CashbackView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let report = store.cashbackReport()
        List {
            if report.history.isEmpty {
                ContentUnavailableView("Кэшбэка пока нет", systemImage: "arrow.uturn.backward.circle",
                                       description: Text("Начисления кэшбэка и процентов появятся здесь, когда они будут в загруженных выписках."))
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ВЕРНУЛОСЬ ЗА \(Fmt.month(store.month).uppercased())")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(Fmt.money(report.month.total)).font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(report.month.total > 0 ? Color.green : .primary)
                        Text("За \(report.history.count) \(Fmt.plural(report.history.count, "месяц", "месяца", "месяцев")) — \(Fmt.money(report.yearTotal))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    ForEach(CashbackKind.allCases) { kind in
                        LabeledContent {
                            Text(Fmt.money(report.month.byKind[kind] ?? 0))
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                } footer: {
                    Text("Считаем по поступлениям из выписок с категорией «Кэшбэк и проценты». Если начисление попало в другую категорию — поменяйте её в операции.")
                }

                if report.byBank.count > 1 {
                    Section("По банкам") {
                        ForEach(report.byBank, id: \.bank) { item in
                            LabeledContent(item.bank.title, value: Fmt.money(item.amount))
                        }
                    }
                }

                Section("По месяцам") {
                    ForEach(report.history) { m in
                        LabeledContent {
                            Text(Fmt.money(m.total)).foregroundStyle(m.total > 0 ? Color.primary : .secondary)
                        } label: {
                            Text(Fmt.month(m.month))
                        }
                    }
                }

                if !report.transactions.isEmpty {
                    Section("Начисления") {
                        ForEach(report.transactions) { t in
                            LabeledContent {
                                Text("+\(Fmt.money(t.amount))").foregroundStyle(.green)
                            } label: {
                                Text(t.title)
                                Text("\(t.bank.title) · \(t.date.formatted(.dateTime.day().month(.wide)))")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Кэшбэк")
    }
}
