import SwiftUI
import UserNotifications

/// Локальные напоминания: платежи по кредитам и подпискам, конец льготного периода, превышение лимитов.
/// Ничего не уходит на сервер — iOS показывает их по расписанию сама.
enum Reminders {
    static let enabledKey = "remindersEnabled"
    private static let prefix = "imoney."
    private static let notifiedLimitsKey = "remindersNotifiedLimits"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Пересобирает расписание по текущим данным. Вызывается при открытии приложения и после изменений.
    static func reschedule(_ store: Store) {
        let center = UNUserNotificationCenter.current()
        // Удаляем синхронно и все сразу (в списке только напоминания iMoney): асинхронное удаление
        // успевало стереть уже новые напоминания с теми же идентификаторами
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }

        let cal = Store.calendar
        let now = Date()
        let horizon = cal.date(byAdding: .day, value: 60, to: now) ?? now

        func add(_ id: String, _ title: String, _ body: String, on date: Date) {
            var c = cal.dateComponents([.year, .month, .day], from: date)
            c.hour = 10
            guard let fire = cal.date(from: c), fire > now, fire < horizon else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: prefix + id, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false)))
        }

        for debt in store.debts where debt.balance > 0 {
            let due = debt.upcomingPayment()
            if let day = cal.date(byAdding: .day, value: -2, to: due) {
                add("debt.\(debt.id)", "Через 2 дня платёж: \(debt.title)",
                    "\(Fmt.money(debt.monthlyPayment)) до \(due.formatted(.dateTime.day().month(.wide))).", on: day)
            }
            if debt.graceActive, let grace = debt.graceEnds, let day = cal.date(byAdding: .day, value: -3, to: grace) {
                add("grace.\(debt.id)", "Льготный период заканчивается",
                    "Погасите \(Fmt.money(debt.balance)) по карте «\(debt.title)» до \(grace.formatted(.dateTime.day().month(.wide))) — и проценты не начислятся.", on: day)
            }
        }
        for payment in store.recurring {
            if let day = cal.date(byAdding: .day, value: -1, to: payment.nextDate()) {
                add("rec.\(payment.id)", "Завтра платёж: \(payment.title)", Fmt.money(payment.amount), on: day)
            }
        }
        notifyExceededLimits(store, center: center)
    }

    /// Превышенный лимит — один раз за месяц на категорию, сразу.
    private static func notifyExceededLimits(_ store: Store, center: UNUserNotificationCenter) {
        let current = Store.startOfMonth(Date())
        let stats = Analytics.stats(store.transactions, month: current)
        let monthKey = Store.calendar.dateComponents([.year, .month], from: current)
        var sent = Set(UserDefaults.standard.stringArray(forKey: notifiedLimitsKey) ?? [])
        for limit in store.limits {
            let spent = stats.byCategory.first { $0.category == limit.category }?.amount ?? 0
            let key = "\(monthKey.year ?? 0)-\(monthKey.month ?? 0)-\(limit.category.rawValue)"
            guard spent > limit.amount, !sent.contains(key) else { continue }
            sent.insert(key)
            let content = UNMutableNotificationContent()
            content.title = "Лимит превышен: \(limit.category.title)"
            content.body = "\(Fmt.money(spent)) из \(Fmt.money(limit.amount)) за месяц."
            center.add(UNNotificationRequest(identifier: prefix + "limit." + key, content: content,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        }
        UserDefaults.standard.set(Array(sent), forKey: notifiedLimitsKey)
    }
}

/// Настройка напоминаний в «Счетах».
struct RemindersSection: View {
    @Environment(Store.self) private var store
    @AppStorage(Reminders.enabledKey) private var enabled = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { enabled }, set: { on in
                if on {
                    Task {
                        enabled = await Reminders.requestPermission()
                        Reminders.reschedule(store)
                    }
                } else {
                    enabled = false
                    Reminders.reschedule(store)
                }
            })) {
                Label("Напоминания", systemImage: "bell.badge")
            }
        } header: {
            Text("Уведомления")
        } footer: {
            Text("За 2 дня до платежа по кредиту, накануне подписки, за 3 дня до конца льготного периода кредитки и когда превышен лимит.")
        }
    }
}

/// То же для глянцевого оформления.
struct AquaRemindersCard: View {
    @Environment(Store.self) private var store
    @AppStorage(Reminders.enabledKey) private var enabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { enabled }, set: { on in
                if on {
                    Task { enabled = await Reminders.requestPermission(); Reminders.reschedule(store) }
                } else {
                    enabled = false
                    Reminders.reschedule(store)
                }
            })) {
                Text("Напоминания").font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text)
            }
            .tint(Aqua.blue)
            Text("О платежах по кредитам и подпискам, конце льготного периода и превышенных лимитах.")
                .font(Aqua.font(12)).foregroundStyle(Aqua.label)
        }
        .padding(12)
        .groupCard()
    }
}
