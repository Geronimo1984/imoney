import SwiftUI

/// Раздел «Цели» — для «Плана» и для отдельного экрана.
struct GoalsSection: View {
    @Environment(Store.self) private var store
    @State private var editing: SavingsGoal?
    @State private var contributing: SavingsGoal?

    var body: some View {
        Section {
            ForEach(store.goals) { goal in
                Button { editing = goal } label: { GoalRow(goal: goal) }
                    // Строка — не ссылка: текст обычного цвета, а не синего
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .leading) {
                        Button("Пополнить", systemImage: "plus") { contributing = goal }.tint(.green)
                    }
                    .swipeActions {
                        Button("Удалить", role: .destructive) { store.deleteGoal(goal.id) }
                    }
            }
            Button { editing = SavingsGoal(title: "", target: 0, deadline: Store.calendar.date(byAdding: .month, value: 6, to: Date())) } label: {
                Label("Новая цель", systemImage: "plus.circle.fill")
            }
            // Листы — на строке: у раздела списка целиком они не открываются
            .sheet(item: $editing) { goal in GoalEditor(goal: goal, isNew: !store.goals.contains { $0.id == goal.id }) }
            .sheet(item: $contributing) { goal in
                AmountEditor(title: goal.title, caption: "Сколько отложили на эту цель", value: 0) { store.contribute($0, to: goal.id) }
            }
        } header: {
            Text("Цели")
        } footer: {
            let need = store.goalsMonthlyNeeded
            if need > 0 {
                Text("Чтобы успеть ко всем срокам, откладывайте \(Fmt.money(need)) в месяц. В плане сейчас \(Fmt.money(store.incomePlan.savings)).")
                    .foregroundStyle(need > store.incomePlan.savings ? Color.orange : .secondary)
            }
        }
    }
}

struct GoalRow: View {
    var goal: SavingsGoal

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                PaidRing(share: goal.share, color: goal.color, lineWidth: 5)
                Image(systemName: goal.isReached ? "checkmark" : goal.symbol)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(goal.color)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title).foregroundStyle(.primary).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(goal.isReached ? Color.green : .secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.money(goal.saved)).foregroundStyle(.primary)
                Text("из \(Fmt.money(goal.target))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        if goal.isReached { return "Цель достигнута" }
        if let need = goal.monthlyNeeded, let d = goal.deadline {
            return "\(Fmt.money(need)) в месяц · до \(Fmt.monthGenitive(d))"
        }
        return "Осталось \(Fmt.money(goal.left))"
    }
}

/// Отдельный экран целей — для глянцевого оформления.
struct GoalsView: View {
    var body: some View {
        List { GoalsSection() }.navigationTitle("Цели")
    }
}

struct GoalEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var goal: SavingsGoal
    var isNew: Bool
    @State private var target: Double = 0
    @State private var saved: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Например, «Отпуск»", text: $goal.title)
                    LabeledContent("Нужно") { amount($target) }
                    LabeledContent("Уже отложено") { amount($saved) }
                }
                Section {
                    Toggle("Срок", isOn: Binding(get: { goal.deadline != nil },
                                                 set: { goal.deadline = $0 ? Store.calendar.date(byAdding: .month, value: 6, to: Date()) : nil }))
                    if let d = goal.deadline {
                        DatePicker("К дате", selection: Binding(get: { d }, set: { goal.deadline = $0 }), in: Date()..., displayedComponents: .date)
                    }
                } footer: {
                    if let months = goal.monthsLeft, target > saved {
                        Text("Откладывайте \(Fmt.money(Decimal((target - saved) / Double(months)))) в месяц.")
                    }
                }
                Section("Значок") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(SavingsGoal.colors.indices, id: \.self) { i in
                            Circle().fill(SavingsGoal.colors[i]).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.primary, lineWidth: goal.colorIndex == i ? 2 : 0).padding(-3))
                                .onTapGesture { goal.colorIndex = i }
                                .accessibilityAddTraits(.isButton)
                        }
                        ForEach(SavingsGoal.symbols, id: \.self) { s in
                            Image(systemName: s).font(.title3)
                                .foregroundStyle(goal.symbol == s ? goal.color : .secondary)
                                .frame(width: 36, height: 36)
                                .onTapGesture { goal.symbol = s }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !isNew {
                    Section { Button("Удалить цель", role: .destructive) { store.deleteGoal(goal.id); dismiss() } }
                }
            }
            .navigationTitle(isNew ? "Новая цель" : goal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Добавить" : "Готово") {
                        goal.target = Decimal(target)
                        goal.saved = Decimal(saved)
                        store.saveGoal(goal)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(goal.title.trimmingCharacters(in: .whitespaces).isEmpty || target <= 0)
                }
            }
            .onAppear {
                target = goal.target.double
                saved = goal.saved.double
            }
        }
    }

    private func amount(_ value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            TextField("0", value: Binding<Double?>(get: { value.wrappedValue == 0 ? nil : value.wrappedValue },
                                                   set: { value.wrappedValue = $0 ?? 0 }),
                      format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            Text("₽").foregroundStyle(.secondary)
        }
    }
}
