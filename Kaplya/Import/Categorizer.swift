import Foundation

/// Определяет категорию операции: правила пользователя → ключевые слова → категория банка → MCC.
enum Categorizer {

    static func category(title: String, bankCategory: String, mcc: String,
                         amount: Decimal, rules: [CategoryRule]) -> Category {
        let name = Transaction.normalize(title)
        let bankCat = bankCategory.lowercased().replacingOccurrences(of: "ё", with: "е")

        if let rule = rules.first(where: { !$0.match.isEmpty && name.contains($0.match) }) {
            return rule.category
        }

        if isInternalMarker(name) || isInternalMarker(bankCat) {
            return .internalTransfer
        }

        // Копилка и Кубышка — накопления в обе стороны: возврат из копилки уменьшает отложенное
        if ["копилк", "кубышк", "накопительный счет"].contains(where: { name.contains($0) }) {
            return .savings
        }

        let income = amount > 0
        // Отмена покупки или возврат — это не доход, а минус к расходам той же категории
        if income, ["отмена операции", "возврат"].contains(where: { name.contains($0) }),
           let refund = keyword(name) ?? fromBankCategory(bankCat) ?? fromMCC(mcc) {
            return refund
        }
        if income {
            return incomeCategory(name: name, bankCat: bankCat)
        }

        if let byName = keyword(name) { return byName }
        if let byBank = fromBankCategory(bankCat) { return byBank }
        if let byMCC = fromMCC(mcc) { return byMCC }
        if isTransfer(name) || isTransfer(bankCat) { return .transfersOut }
        return .otherExpense
    }

    // MARK: Переводы

    /// Перевод самому себе: в описании имя и отчество владельца счёта («Перевод от А. Анна Сергеевна»).
    static func isOwnTransfer(_ title: String, owner: String?) -> Bool {
        guard let owner else { return false }
        let parts = Transaction.normalize(owner).split(separator: " ").map(String.init)
        guard parts.count >= 3 else { return false }
        let name = Transaction.normalize(title)
        return name.contains(parts[1]) && name.contains(parts[2]) && isTransfer(name)
    }

    static func isInternalMarker(_ s: String) -> Bool {
        let markers = ["между своими", "между счетами", "на свой счет", "на свою карту",
                       "с моего счета", "перевод себе", "собственных счетов",
                       "внутренний перевод", "внутрибанковский перевод с договора"]
        return markers.contains { s.contains($0) }
    }

    static func isTransfer(_ s: String) -> Bool {
        let markers = ["перевод", "сбп", "transfer", "card2card", "c2c", "по номеру телефона",
                       "пополнение", "зачисление", "внесение"]
        return markers.contains { s.contains($0) }
    }

    // MARK: Доходы

    private static func incomeCategory(name: String, bankCat: String) -> Category {
        let text = name + " " + bankCat
        if ["зарплат", "заработн", "аванс", "salary", "оплата труда", "отпускн", "премия"]
            .contains(where: text.contains) { return .salary }
        if ["кэшбэк", "кешбэк", "cashback", "проценты", "капитализац", "бонус", "вознаграждение"]
            .contains(where: text.contains) { return .cashback }
        if isTransfer(text) { return .transfersIn }
        return .otherIncome
    }

    // MARK: Ключевые слова в названии

    private static let keywords: [(Category, [String])] = [
        (.delivery, ["kuper", "купер", "яндекс еда", "yandex eda", "eda.yandex", "delivery club", "деливери", "самокат",
                     "samokat", "кухня на районе", "vkusvill dostavka", "dodo", "додо", "kfc delivery"]),
        (.taxi, ["яндекс такси", "yandex.taxi", "yandex taxi", "yandex go", "uber", "ситимобил",
                 "citymobil", "максим", "taxi"]),
        (.subscriptions, ["vk music", "timeweb", "яндекс плюс", "yandex plus", "кинопоиск", "kinopoisk", "netflix", "spotify",
                          "apple.com", "itunes", "google play", "youtube", "okko", "ivi", "иви",
                          "start.ru", "wink", "vk музыка", "boosty", "patreon", "chatgpt", "openai",
                          "anthropic", "claude", "икс5 пакет", "сберпрайм", "sberprime", "pro подписка"]),
        (.marketplace, ["ozon", "озон", "wildberries", "вайлдберриз", "wb ", "яндекс маркет",
                        "yandex market", "market.yandex", "aliexpress", "мегамаркет", "lamoda", "avito", "авито"]),
        (.groceries, ["minimarket", "минимаркет", "bristol", "krasnoe beloe", "пятерочк", "pyaterochk", "ovoshhi", "frukty", "овощи", "metro store", "магнит", "magnit", "перекресток", "perekrestok",
                      "ашан", "auchan", "лента", "lenta", "вкусвилл", "vkusvill", "дикси", "dixy",
                      "metro cash", "окей", "o'key", "spar", "спар", "азбука вкуса", "globus", "глобус",
                      "верный", "светофор", "fix price", "fixprice", "мария ра", "бристоль", "красное белое"]),
        (.cafe, ["кофе", "coffee", "cofix", "starbucks", "шоколадница", "теремок", "вкусно и точка",
                 "burger", "бургер", "kfc", "ростикс", "rostics", "макдоналдс", "subway", "ресторан",
                 "cafe", "кафе", "пицц", "pizza", " bar ", "pop korn", "konditer", "кондитер", "суши", "sushi", "stars coffee", "surf coffee"]),
        (.transport, ["avtotrans", "метро", "metro moscow", "mosmetro", "тройка", "troika", "мцд", "ржд", "rzd",
                      "аэроэкспресс", "transport", "мосгортранс", "whoosh", "юрент", "urent", "самокаты"]),
        (.car, ["лукойл", "lukoil", "роснефть", "rosneft", "газпромнефть", "gazprom", "shell",
                "татнефть", "tatneft", "азс", "парковк", "parking", "автомойк", "шиномонтаж", "осаго", "каско"]),
        (.housing, ["yandex arenda", "яндекс аренда", "жкх", "жку", "квартплат", "мосэнерго", "энергосбыт", "мосводоканал", "управляющ",
                    "аренда квартиры", "ипотек", "газпром межрегионгаз", "единый платежный документ", "епд"]),
        (.telecom, ["мтс", "mts", "билайн", "beeline", "мегафон", "megafon", "tele2", "теле2", "т2 ",
                    "ростелеком", "rostelecom", "йота", "yota", "дом.ру", "интернет", "т-мобайл"]),
        (.health, ["аптек", "apteka", "36,6", "ригла", "горздрав", "здравсити", "еаптека", "клиник",
                   "стоматолог", "медси", "инвитро", "invitro", "гемотест", "доктор", "medical"]),
        (.beauty, ["барбершоп", "barbershop", "салон красоты", "золотое яблоко", "летуаль", "letu",
                   "рив гош", "маникюр", "косметик"]),
        (.clothes, ["zara", "h&m", "uniqlo", "gloria jeans", "глория джинс", "спортмастер", "sportmaster",
                    "befree", "love republic", "ostin", "остин", "lime", "zolla", "обувь", "familia", "фамилия"]),
        (.home, ["леруа", "leroy", "оби ", "obi ", "икеа", "ikea", "hoff", "хофф", "петрович",
                 "максидом", "castorama", "дом и сад"]),
        (.entertainment, ["фитнес", "fitness", "qtickets", "кино", "cinema", "синема", "театр", "концерт", "яндекс афиша", "afisha",
                          "kassir", "кассир", "музей", "steam", "playstation", "боулинг", "квест"]),
        (.travel, ["авиабилет", "aeroflot", "аэрофлот", "s7", "победа", "pobeda", "утэйр", "utair",
                   "booking", "ostrovok", "островок", "отель", "hotel", "суточно", "tutu", "туту", "aviasales"]),
        (.education, ["курс", "skillbox", "нетология", "netology", "яндекс практикум", "practicum",
                      "geekbrains", "школа", "университет", "учебник", "литрес", "litres"]),
        (.kids, ["детский мир", "detskiy mir", "дочки сыночки", "кораблик", "детск"]),
        (.pets, ["бетховен", "четыре лапы", "зоомагазин", "ветеринар", "petshop", "зоо"]),
        (.gifts, ["цветы", "flowers", "подарок", "gift"]),
        (.taxes, ["налог", "госуслуг", "гибдд", "штраф", "фнс", "пошлин", "nalog"]),
        (.loans, ["погашение кредита", "погашение по кредит", "платеж по кредит", "кредитной карты",
                  "ипотечн", "рассрочк", "долями", "сплит", "split"]),
        (.savings, ["копилк", "кубышк", "накопительный счет", "брокерск", "иис", "инвестиц", "вклад"]),
        (.cash, ["банкомат", "atm", "выдача наличных", "снятие наличных"])
    ]

    private static func keyword(_ name: String) -> Category? {
        let padded = " " + name + " "
        for (category, words) in keywords where words.contains(where: padded.contains) {
            return category
        }
        return nil
    }

    // MARK: Категории банков (Т-Банк и Сбер называют по-разному)

    private static func fromBankCategory(_ c: String) -> Category? {
        guard !c.isEmpty else { return nil }
        let table: [(String, Category)] = [
            ("фастфуд", .cafe), ("ресторан", .cafe), ("кафе", .cafe),
            ("супермаркет", .groceries), ("продукт", .groceries),
            ("такси", .taxi), ("местный транспорт", .transport), ("транспорт", .transport),
            ("ж/д", .travel), ("авиабилет", .travel), ("отел", .travel), ("турагент", .travel), ("путешеств", .travel),
            ("топливо", .car), ("автоуслуг", .car), ("автомобил", .car), ("аренда авто", .car),
            ("аптек", .health), ("медицин", .health), ("здоровье", .health),
            ("красот", .beauty), ("косметик", .beauty),
            ("одежд", .clothes), ("обувь", .clothes),
            ("дом и ремонт", .home), ("все для дома", .home), ("мебель", .home),
            ("маркетплейс", .marketplace), ("различные товары", .marketplace),
            ("связь", .telecom), ("мобильн", .telecom), ("телеком", .telecom),
            ("коммунальн", .housing), ("жкх", .housing),
            ("кино", .entertainment), ("развлечен", .entertainment), ("отдых", .entertainment), ("искусств", .entertainment),
            ("цифровые товары", .subscriptions), ("музыка", .subscriptions),
            ("образован", .education), ("книги", .education),
            ("животн", .pets), ("цветы", .gifts), ("подарк", .gifts),
            ("госуслуг", .taxes), ("налог", .taxes), ("штраф", .taxes),
            ("наличны", .cash),
            ("кредит", .loans), ("финансы", .loans),
            ("инвестиц", .savings)
        ]
        return table.first { c.contains($0.0) }?.1
    }

    private static func fromMCC(_ mcc: String) -> Category? {
        guard let code = Int(mcc) else { return nil }
        switch code {
        case 5411, 5422, 5441, 5451, 5462, 5499:        return .groceries
        case 5812, 5813, 5814:                          return .cafe
        case 4121:                                      return .taxi
        case 4111, 4112, 4131, 4789:                    return .transport
        case 5541, 5542, 5172, 7523, 7531...7549, 5533: return .car
        case 4900:                                      return .housing
        case 4812, 4814, 4816, 4899:                    return .telecom
        case 5912, 8011...8099:                         return .health
        case 7230, 7298, 5977:                          return .beauty
        case 5611...5699, 5137, 5139, 5661:             return .clothes
        case 5200, 5211, 5231, 5251, 5712...5719, 5722: return .home
        case 5262, 5300, 5310, 5311, 5331, 5399:        return .marketplace
        case 7832, 7841, 7922, 7929, 7991, 7996, 7999, 5816: return .entertainment
        case 5815, 5817, 5818, 4815:                    return .subscriptions
        case 3000...3350, 4511, 4722, 7011, 3501...3999: return .travel
        case 8211...8299, 5942, 5943:                   return .education
        case 5641, 5945:                                return .kids
        case 5995, 0742:                                return .pets
        case 5992, 5947:                                return .gifts
        case 9311, 9222, 9399, 9402:                    return .taxes
        case 6010, 6011:                                return .cash
        default:                                        return nil
        }
    }
}
