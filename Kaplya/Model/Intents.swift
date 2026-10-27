import AppIntents
import Foundation

/// Команды Siri и «Быстрых команд». Отвечают голосом, не открывая приложение.

struct SpendTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Сколько можно тратить сегодня"
    static var description = IntentDescription("Сколько можно тратить в день, чтобы уложиться в доход месяца.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store()
        let month = Store.startOfMonth(Date())
        guard let f = Analytics.forecast(store.transactions, month: month), !store.transactions.isEmpty else {
            return .result(dialog: "Пока нет операций за этот месяц. Загрузите выписку в iMoney.")
        }
        if f.perDayLeft <= 0 {
            return .result(dialog: "Доход этого месяца уже потрачен: \(Fmt.money(f.spent)).")
        }
        return .result(dialog: "Сегодня можно потратить \(Fmt.money(f.perDayLeft)). До конца месяца \(f.daysLeft) \(Fmt.plural(f.daysLeft, "день", "дня", "дней")).")
    }
}

/// Частые категории для голосового вопроса.
enum SpendCategory: String, AppEnum {
    case groceries, cafe, delivery, taxi, transport, marketplace, subscriptions, health, clothes, entertainment

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Категория"
    static var caseDisplayRepresentations: [SpendCategory: DisplayRepresentation] = [
        .groceries: "Продукты", .cafe: "Кафе и рестораны", .delivery: "Доставка еды", .taxi: "Такси",
        .transport: "Транспорт", .marketplace: "Маркетплейсы", .subscriptions: "Подписки",
        .health: "Здоровье", .clothes: "Одежда", .entertainment: "Развлечения"
    ]

    var category: Category { Category(rawValue: rawValue) ?? .otherExpense }
}

struct CategorySpentIntent: AppIntent {
    static var title: LocalizedStringResource = "Сколько потрачено на категорию"
    static var description = IntentDescription("Траты за текущий месяц по одной категории.")

    @Parameter(title: "Категория")
    var category: SpendCategory

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store()
        let stats = Analytics.stats(store.transactions, month: Store.startOfMonth(Date()))
        let item = stats.byCategory.first { $0.category == category.category }
        let title = category.category.title
        guard let item else { return .result(dialog: "На «\(title)» в этом месяце трат нет.") }
        var answer = "На «\(title)» в этом месяце — \(Fmt.money(item.amount))"
        if let limit = store.limits.first(where: { $0.category == category.category }) {
            answer += ", лимит \(Fmt.money(limit.amount))"
        }
        return .result(dialog: "\(answer).")
    }
}

struct CanBuyIntent: AppIntent {
    static var title: LocalizedStringResource = "Можно ли купить по кредитке"
    static var description = IntentDescription("Проверяет покупку по кредитной карте с учётом доходов, трат и льготного периода.")

    @Parameter(title: "Сумма, ₽")
    var amount: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store()
        guard let card = store.debts.first(where: { $0.isCard }) else {
            return .result(dialog: "В iMoney нет кредитной карты. Добавьте её в «Плане» → «Кредиты и рассрочки».")
        }
        let advice = store.cardAdvice(for: card, purchase: Decimal(amount))
        return .result(dialog: "\(advice.title). \(advice.text)")
    }
}

struct IMoneyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SpendTodayIntent(),
                    phrases: ["Сколько можно тратить в \(.applicationName)", "Сколько можно тратить сегодня \(.applicationName)"],
                    shortTitle: "Можно тратить", systemImageName: "creditcard")
        AppShortcut(intent: CategorySpentIntent(),
                    phrases: ["Сколько потрачено на \(\.$category) в \(.applicationName)", "Траты на \(\.$category) \(.applicationName)"],
                    shortTitle: "Траты по категории", systemImageName: "chart.pie")
        AppShortcut(intent: CanBuyIntent(),
                    phrases: ["Можно ли купить по кредитке в \(.applicationName)"],
                    shortTitle: "Проверить покупку", systemImageName: "cart")
    }
}
