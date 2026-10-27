import SwiftUI

/// Налоговый вычет 13%: что найдено в выписках, сколько вернут и как подать.
struct TaxView: View {
    @Environment(Store.self) private var store
    @State private var year: Int = Store.calendar.component(.year, from: Date())

    var body: some View {
        let report = store.taxReport(year: year)
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("МОЖНО ВЕРНУТЬ").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(Fmt.money(report.refund)).font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(report.refund > 0 ? Color.green : .primary)
                    Text(report.eligible > 0
                         ? "13% от \(Fmt.money(report.eligible)) расходов за \(String(year)) год"
                         : "За \(String(year)) год подходящих расходов не найдено")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                if store.taxYears.count > 1 {
                    Picker("Год", selection: $year) {
                        ForEach(store.taxYears.prefix(3), id: \.self) { Text(String($0)).tag($0) }
                    }
                }
            } footer: {
                if (report.taxPaid > 0) && (report.eligible * Decimal(0.13) > report.taxPaid) {
                    Text("Вернуть можно не больше уплаченного налога. По зарплате в выписках это около \(Fmt.money(report.taxPaid)).")
                } else {
                    Text("Это оценка по выпискам. Точную сумму посчитает налоговая по документам.")
                }
            }

            ForEach(report.groups) { group in
                Section {
                    LabeledContent {
                        Text(Fmt.money(group.amount))
                    } label: {
                        Label(group.kind.title, systemImage: group.kind.symbol)
                    }
                    ForEach(group.transactions.prefix(20)) { t in
                        LabeledContent(t.title, value: Fmt.money(t.absAmount)).font(.subheadline)
                    }
                    if group.transactions.count > 20 {
                        Text("и ещё \(group.transactions.count - 20)").font(.subheadline).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(group.kind.document)
                }
            }

            Section("Как получить") {
                step(1, "Соберите документы — какие именно, указано под каждой группой выше.")
                step(2, "Проще всего — упрощённый вычет: в личном кабинете налоговой или на Госуслугах заявление по многим расходам формируется само.")
                step(3, "Если упрощённого нет — заполните декларацию 3-НДФЛ в личном кабинете nalog.ru и приложите сканы документов.")
                step(4, "Деньги придут на карту в течение 1–2 месяцев после проверки. Подать можно за три последних года.")
            }

            Section {
                Text("Лимиты: лечение, лекарства, своё обучение и спорт — вместе до 150 000 ₽ в год; обучение детей — до 110 000 ₽ на ребёнка; проценты по ипотеке — до 3 000 000 ₽. Дорогостоящее лечение — без лимита.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Налоговый вычет")
        .onAppear {
            if let latest = store.taxYears.first { year = latest }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Color.accentColor, in: Circle())
            Text(text)
        }
        .padding(.vertical, 2)
    }
}
