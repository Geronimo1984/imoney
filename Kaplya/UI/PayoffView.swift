import SwiftUI

/// Стратегия погашения: доплата сверх обязательных платежей, лавина или снежный ком.
struct PayoffView: View {
    @Environment(Store.self) private var store
    @State private var extra: Double = 5_000
    @State private var strategy: PayoffStrategy = .avalanche

    var body: some View {
        let debts = store.debts.filter { $0.balance > 0 }
        let base = Payoff.simulate(debts, extra: 0, strategy: strategy)
        let plan = Payoff.simulate(debts, extra: Decimal(extra), strategy: strategy)
        let other = Payoff.simulate(debts, extra: Decimal(extra), strategy: strategy == .avalanche ? .snowball : .avalanche)

        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("БЕЗ ДОЛГОВ").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(plan.debtFreeDate.map { $0.formatted(.dateTime.month(.wide).year()) } ?? "Не получится")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    if plan.feasible, base.feasible, base.months > plan.months {
                        Text("На \(base.months - plan.months) \(Fmt.plural(base.months - plan.months, "месяц", "месяца", "месяцев")) раньше и \(Fmt.money(max(base.interest - plan.interest, 0))) экономии на процентах")
                            .font(.subheadline).foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                if !plan.feasible {
                    Text("Платежи не покрывают проценты. Увеличьте доплату.").foregroundStyle(.red)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Доплата в месяц", value: Fmt.money(Decimal(extra)))
                    Slider(value: $extra, in: 0...50_000, step: 1_000)
                }
                Picker("Стратегия", selection: $strategy) {
                    ForEach(PayoffStrategy.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Сверх обязательных платежей")
            } footer: {
                Text(strategy.explanation)
            }

            Section {
                LabeledContent("Переплата по процентам", value: Fmt.money(plan.interest))
                LabeledContent("Только обязательные платежи", value: Fmt.money(base.interest))
                if other.feasible, plan.feasible, other.interest != plan.interest {
                    LabeledContent(strategy == .avalanche ? "Снежным комом" : "Лавиной", value: Fmt.money(other.interest))
                }
            } header: {
                Text("Проценты")
            }

            Section {
                ForEach(debts.sorted { (plan.closedAfter[$0.id] ?? 999) < (plan.closedAfter[$1.id] ?? 999) }) { debt in
                    HStack(spacing: 12) {
                        Image(systemName: debt.kind.symbol).foregroundStyle(debt.kind.color).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(debt.title).lineLimit(1)
                            Text("\(Fmt.money(debt.balance)) · \(debt.rate > 0 ? percent(debt.rate) : "0%")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(closeDate(plan.closedAfter[debt.id])).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Порядок закрытия")
            }
        }
        .navigationTitle("Стратегия погашения")
    }

    private func closeDate(_ months: Int?) -> String {
        guard let months, let d = Store.calendar.date(byAdding: .month, value: months, to: Date()) else { return "—" }
        return d.formatted(.dateTime.month(.abbreviated).year())
    }
}
