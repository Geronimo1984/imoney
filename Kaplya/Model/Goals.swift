import SwiftUI

/// Цель накоплений: отпуск, подушка безопасности, ремонт.
struct SavingsGoal: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var symbol: String = "star.fill"
    var target: Decimal
    var saved: Decimal = 0
    var deadline: Date?
    var colorIndex = 0

    static let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal]
    static let symbols = ["airplane", "lifepreserver.fill", "house.fill", "car.fill", "graduationcap.fill",
                          "gift.fill", "laptopcomputer", "heart.fill", "star.fill"]

    var color: Color { SavingsGoal.colors[colorIndex % SavingsGoal.colors.count] }
    var share: Double { target > 0 ? min((saved / target).double, 1) : 0 }
    var left: Decimal { max(target - saved, 0) }
    var isReached: Bool { saved >= target && target > 0 }

    /// Сколько месяцев осталось до срока (минимум 1).
    var monthsLeft: Int? {
        guard let deadline else { return nil }
        let months = Store.calendar.dateComponents([.month], from: Date(), to: deadline).month ?? 0
        return max(months, 1)
    }

    /// Сколько откладывать в месяц, чтобы успеть к сроку.
    var monthlyNeeded: Decimal? {
        guard let monthsLeft, !isReached else { return nil }
        return left / Decimal(monthsLeft)
    }
}

extension Store {
    func saveGoal(_ goal: SavingsGoal) {
        if let i = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[i] = goal
        } else {
            goals.append(goal)
        }
        save()
    }

    func deleteGoal(_ id: SavingsGoal.ID) {
        goals.removeAll { $0.id == id }
        save()
    }

    func contribute(_ amount: Decimal, to id: SavingsGoal.ID) {
        guard let i = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[i].saved = max(goals[i].saved + amount, 0)
        save()
    }

    /// Сколько всего нужно откладывать в месяц, чтобы успеть ко всем срокам.
    var goalsMonthlyNeeded: Decimal { goals.compactMap(\.monthlyNeeded).reduce(0, +) }
}
