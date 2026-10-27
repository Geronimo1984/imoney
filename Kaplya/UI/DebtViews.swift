import SwiftUI

/// Кольцо «выплачено» — как у ежемесячных платежей Apple Card.
struct PaidRing: View {
    var share: Double
    var color: Color
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(share, 0.001))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Строка долга: кольцо, название, остаток и когда закроется, платёж.
struct DebtRow: View {
    var debt: Debt
    var paid: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                PaidRing(share: debt.ringShare, color: debt.kind.color, lineWidth: 4)
                Image(systemName: debt.kind.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(debt.kind.color)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(debt.title).foregroundStyle(.primary).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(paid ? Color.green : .secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.money(debt.monthlyPayment)).foregroundStyle(.primary)
                Text(debt.isCard ? "минимум" : "в месяц").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        paid ? "Платёж в этом месяце внесён" : debt.summary
    }
}

/// Все долги: сводка сверху и список — как раздел Apple Card «Ежемесячные платежи».
struct DebtsView: View {
    @Environment(Store.self) private var store
    @State private var editing: Debt?

    var body: some View {
        let plan = store.planSummary()
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ОБЩИЙ ДОЛГ").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(Fmt.money(store.debtsTotal)).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Платежи \(Fmt.money(store.debtsMonthly)) в месяц — \(Int((plan.debtLoad * 100).rounded()))% дохода")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } footer: {
                Text(loadAdvice(plan.debtLoad))
            }

            Section {
                ForEach(store.debts) { debt in
                    NavigationLink { DebtDetail(id: debt.id) } label: {
                        DebtRow(debt: debt, paid: debt.isPaid(in: store.month, transactions: store.transactions))
                    }
                }
                Button { editing = Debt(kind: .loan, title: "", principal: 0, balance: 0, monthlyPayment: 0, nextPayment: Date()) } label: {
                    Label("Добавить кредит или рассрочку", systemImage: "plus.circle.fill")
                }
            }

            if store.debts.contains(where: { $0.balance > 0 }) {
                Section {
                    NavigationLink { PayoffView() } label: {
                        Label("Как погасить быстрее", systemImage: "chart.line.downtrend.xyaxis")
                    }
                } footer: {
                    Text("Сколько сэкономите, если доплачивать сверх обязательных платежей, и в каком порядке закрывать долги.")
                }
            }

            let found = store.suggestedDebts()
            if !found.isEmpty {
                Section {
                    ForEach(found) { debt in
                        Button { editing = debt } label: {
                            HStack {
                                Label(debt.title, systemImage: "sparkles").foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                                Text("\(Fmt.money(debt.monthlyPayment)) в месяц").foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Найдено в выписках")
                } footer: {
                    Text("Похоже на платежи по кредиту. Нажмите и укажите остаток долга.")
                }
            }
        }
        .navigationTitle("Кредиты и рассрочки")
        .sheet(item: $editing) { debt in
            DebtEditor(debt: debt, isNew: !store.debts.contains { $0.id == debt.id })
        }
    }
}

/// Показатель долговой нагрузки (ПДН) — понятным языком.
func loadAdvice(_ load: Double) -> String {
    let percent = Int((load * 100).rounded())
    switch load {
    case ..<0.01: return "Действующих кредитов нет."
    case ..<0.3:  return "Нагрузка \(percent)% — комфортная. Банки считают нормой до 30–40% дохода."
    case ..<0.5:  return "Нагрузка \(percent)% — заметная. Новые кредиты лучше не брать, пока она не снизится."
    default:      return "Нагрузка \(percent)% — высокая: на платежи уходит половина дохода и больше. Начните досрочно гасить кредит с самой высокой ставкой."
    }
}

/// Карточка долга: большое кольцо, остаток, график и платежи из выписок.
struct DebtDetail: View {
    @Environment(Store.self) private var store
    var id: Debt.ID
    @State private var editing = false
    @State private var checkingPurchase = false

    var body: some View {
        if let debt = store.debts.first(where: { $0.id == id }) {
            List {
                Section {
                    VStack(spacing: 12) {
                        ZStack {
                            PaidRing(share: debt.ringShare, color: debt.kind.color, lineWidth: 14)
                            VStack(spacing: 2) {
                                Text("\(Int((debt.ringShare * 100).rounded()))%").font(.system(size: 34, weight: .bold, design: .rounded))
                                Text(debt.isCard ? "лимита занято" : "выплачено").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 150, height: 150)
                        Text(debt.isCard
                             ? "Долг \(Fmt.money(debt.balance)) · доступно \(Fmt.money(debt.available))"
                             : "Осталось \(Fmt.money(debt.balance)) из \(Fmt.money(debt.principal))")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .listRowBackground(Color.clear)

                if debt.isCard {
                    adviceSection(debt)
                    cardSection(debt)
                    if debt.cardKey != nil {
                        cardActivitySection(debt)
                    }
                }

                Section {
                    LabeledContent(debt.isCard ? "Минимальный платёж" : "Ежемесячный платёж", value: Fmt.money(debt.monthlyPayment))
                    LabeledContent("Следующий платёж",
                                   value: debt.upcomingPayment().formatted(.dateTime.day().month(.wide)))
                    if !debt.isCard, let left = debt.paymentsLeft, left > 0 {
                        LabeledContent("Осталось платежей", value: "\(left)")
                    }
                    if let date = debt.payoffDate {
                        LabeledContent(debt.isCard ? "Закроется при минимальных платежах" : "Закроется",
                                       value: date.formatted(.dateTime.month(.wide).year()))
                    }
                    LabeledContent(debt.isCard ? "Ставка после льготного периода" : "Ставка", value: debt.rate > 0 ? "\(debt.rate.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "ru_RU"))))% годовых" : "Без процентов")
                    if debt.interestLeft > 0 {
                        LabeledContent("Ещё уйдёт на проценты", value: Fmt.money(debt.interestLeft))
                    }
                    if !debt.lender.isEmpty { LabeledContent("Кредитор", value: debt.lender) }
                } footer: {
                    if debt.paymentsLeft == nil {
                        Text("Платёж меньше начисляемых процентов — долг не уменьшается. Увеличьте платёж.")
                            .foregroundStyle(.red)
                    } else if debt.rate >= 15 {
                        Text("Ставка высокая. Досрочное погашение этого долга экономит больше всего денег.")
                    }
                }

                let payments = debt.payments(in: store.transactions).sorted { $0.date > $1.date }
                Section {
                    if payments.isEmpty {
                        Text("Платежи появятся здесь, когда пройдут в загруженных выписках.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(payments.prefix(12)) { t in
                        LabeledContent(t.date.formatted(.dateTime.day().month(.wide).year()), value: Fmt.money(t.absAmount))
                    }
                } header: {
                    Text("Платежи в выписках")
                }
            }
            .navigationTitle(debt.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Изменить") { editing = true } }
            }
            .sheet(isPresented: $editing) { DebtEditor(debt: debt, isNew: false) }
            .sheet(isPresented: $checkingPurchase) { PurchaseCheckSheet(card: debt) }
        }
    }
}

extension DebtDetail {
    /// «Можно ли пользоваться картой»: вердикт, безопасная сумма и проверка покупки.
    func adviceSection(_ debt: Debt) -> some View {
        let advice = store.cardAdvice(for: debt)
        return Section {
            AdviceRow(advice: advice)
            if advice.safeAmount > 0 {
                LabeledContent("Можно потратить без процентов", value: Fmt.money(advice.safeAmount))
            }
            LabeledContent("Свободно в месяц", value: Fmt.money(advice.monthlySurplus))
            Button { checkingPurchase = true } label: {
                Label("Проверить покупку", systemImage: "cart.badge.questionmark")
            }
        } header: {
            Text("Можно ли пользоваться картой")
        } footer: {
            Text("Свободно в месяц — доход минус средние траты за три прошлых месяца, без отложенного в накопления.")
        }
    }

    /// Покупки и погашения по кредитке за месяц — из выписок.
    func cardActivitySection(_ debt: Debt) -> some View {
        let activity = store.creditActivity(debt, month: store.month)
        return Section {
            LabeledContent("Покупки", value: Fmt.money(activity.purchases))
            LabeledContent("Погашено", value: Fmt.money(activity.repayments))
            ForEach(activity.items.prefix(15)) { t in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).lineLimit(1)
                        Text("\(t.creditRole?.title ?? "") · \(t.date.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.exact(t.amount, sign: true))
                        .foregroundStyle(t.creditRole == .purchase ? Color.primary : .green)
                }
            }
        } header: {
            Text("Операции по карте за \(Fmt.month(store.month).lowercased())")
        } footer: {
            if activity.items.isEmpty {
                Text("Операций с этими цифрами в загруженных выписках нет. Проверьте цифры карты или номер договора.")
            }
        }
    }

    /// Кредитная карта: как погасить без процентов — главное, что нужно знать о карте.
    @ViewBuilder
    func cardSection(_ debt: Debt) -> some View {
        Section {
            LabeledContent("Кредитный лимит", value: Fmt.money(debt.creditLimit))
            LabeledContent("Доступно", value: Fmt.money(debt.available))
            if let grace = debt.graceEnds {
                LabeledContent("Льготный период до", value: grace.formatted(.dateTime.day().month(.wide)))
            }
        } header: {
            Text("Кредитная карта")
        } footer: {
            if debt.graceActive, let grace = debt.graceEnds {
                Text("Погасите \(Fmt.money(debt.balance)) до \(grace.formatted(.dateTime.day().month(.wide))) — и проценты не начислятся. Если внести только минимальный платёж, за месяц набежит около \(Fmt.money(debt.monthlyInterest)) процентов.")
            } else if debt.monthlyInterest > 0 {
                Text("Льготный период закончился: на долг начисляется около \(Fmt.money(debt.monthlyInterest)) процентов в месяц. Выгоднее погасить карту в первую очередь.")
                    .foregroundStyle(.red)
            }
        }
    }
}

/// Правка долга: вид, название, суммы, ставка, дата платежа.
struct DebtEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var debt: Debt
    var isNew: Bool
    @State private var principal: Double = 0
    @State private var balance: Double = 0
    @State private var payment: Double = 0
    @State private var rate: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Вид", selection: $debt.kind) {
                        ForEach(DebtKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    TextField("Название, например «Ипотека»", text: $debt.title)
                    TextField("Банк или человек", text: $debt.lender)
                }
                Section {
                    amountRow(debt.kind == .creditCard ? "Кредитный лимит" : "Сумма кредита", $principal)
                    amountRow(debt.kind == .creditCard ? "Задолженность" : "Остаток долга", $balance)
                    amountRow(debt.kind == .creditCard ? "Минимальный платёж" : "Платёж в месяц", $payment)
                    if debt.kind != .installment {
                        HStack {
                            Text(debt.kind == .creditCard ? "Ставка после льготного, %" : "Ставка, % годовых")
                            Spacer()
                            TextField("0", value: Binding<Double?>(get: { rate == 0 ? nil : rate }, set: { rate = $0 ?? 0 }), format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                        }
                    }
                    DatePicker("Следующий платёж", selection: $debt.nextPayment, displayedComponents: .date)
                    if debt.kind == .creditCard {
                        Toggle("Идёт льготный период", isOn: Binding(
                            get: { debt.graceEnds != nil },
                            set: { debt.graceEnds = $0 ? (debt.graceEnds ?? debt.nextPayment) : nil }))
                        if let grace = debt.graceEnds {
                            DatePicker("Без процентов до", selection: Binding(get: { grace }, set: { debt.graceEnds = $0 }),
                                       displayedComponents: .date)
                        }
                    }
                } footer: {
                    Text("Остаток и ставку можно посмотреть в приложении банка. По ним iMoney посчитает, когда долг закроется и сколько уйдёт на проценты.")
                }
                if debt.kind == .creditCard {
                    Section {
                        TextField("Последние 4 цифры или номер договора",
                                  text: Binding(get: { debt.cardDigits ?? "" },
                                                set: { debt.cardDigits = String($0.filter(\.isNumber).prefix(20)) }))
                            .keyboardType(.numberPad)
                    } header: {
                        Text("Карта в выписках")
                    } footer: {
                        Text("По этим цифрам iMoney найдёт операции кредитки: покупки останутся тратами, а пополнения кредитки с других счетов станут погашением долга, а не переводом между счетами.")
                    }
                } else {
                    Section {
                        TextField("Название платежа в выписке", text: $debt.match)
                    } footer: {
                        Text("Необязательно. Если указать, iMoney будет отмечать, что платёж в этом месяце уже прошёл.")
                    }
                }
                if !isNew {
                    Section {
                        Button("Удалить", role: .destructive) {
                            store.deleteDebt(debt.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Новый долг" : debt.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Добавить" : "Готово") {
                        debt.principal = Decimal(max(principal, balance))
                        debt.balance = Decimal(balance)
                        debt.monthlyPayment = Decimal(payment)
                        debt.rate = debt.kind == .installment ? 0 : rate
                        debt.match = Transaction.normalize(debt.match)
                        store.saveDebt(debt)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(debt.title.trimmingCharacters(in: .whitespaces).isEmpty || (payment <= 0) || (balance <= 0))
                }
            }
            .onAppear {
                principal = debt.principal.double
                balance = debt.balance.double
                payment = debt.monthlyPayment.double
                rate = debt.rate
            }
        }
    }

    private func amountRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: Binding<Double?>(get: { value.wrappedValue == 0 ? nil : value.wrappedValue },
                                                   set: { value.wrappedValue = $0 ?? 0 }),
                      format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 130)
            Text("₽").foregroundStyle(.secondary)
        }
    }
}

/// Вердикт подсказки: цветной значок, заголовок и пояснение — как «Основные моменты» в Здоровье.
struct AdviceRow: View {
    var advice: CardAdvice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: advice.symbol)
                .font(.title2)
                .foregroundStyle(advice.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(advice.title).font(.headline)
                Text(advice.text).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Проверка конкретной покупки по карте: вводите сумму — вердикт меняется сразу.
struct PurchaseCheckSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var card: Debt
    @State private var amount: Double = 0

    var body: some View {
        let advice = store.cardAdvice(for: card, purchase: Decimal(amount))
        NavigationStack {
            Form {
                Section {
                    BigAmountField(value: $amount)
                } footer: {
                    Text("Сколько хотите потратить по карте «\(card.title)».")
                }
                Section {
                    AdviceRow(advice: advice)
                    if (amount > 0) && (advice.level == .no) && (advice.interestPerMonth > 0) && (Decimal(amount) <= card.available) {
                        LabeledContent("Проценты в месяц", value: Fmt.money(advice.interestPerMonth))
                    }
                    if advice.safeAmount > 0 {
                        LabeledContent("Безопасная сумма", value: Fmt.money(advice.safeAmount))
                    }
                }
                .animation(.default, value: advice.level)
            }
            .navigationTitle("Проверить покупку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
