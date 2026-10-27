import SwiftUI

/// Группа для правила 50/30/20: обязательное, желания, накопления и долги.
enum SpendGroup: String, Codable, CaseIterable {
    case needs, wants, savings, none

    var title: String {
        switch self {
        case .needs:   return "Обязательное"
        case .wants:   return "Желания"
        case .savings: return "Накопления и долги"
        case .none:    return "Прочее"
        }
    }

    /// Рекомендуемая доля от дохода.
    var target: Double {
        switch self {
        case .needs:   return 0.5
        case .wants:   return 0.3
        case .savings: return 0.2
        case .none:    return 0
        }
    }
}

/// Единый справочник категорий — общий для всех банков.
enum Category: String, Codable, CaseIterable, Identifiable {
    // Расходы
    case groceries, cafe, delivery, transport, taxi, car, housing, telecom,
         health, beauty, clothes, home, marketplace, entertainment, subscriptions,
         travel, education, kids, pets, gifts, transfersOut, cash, loans,
         savings, taxes, otherExpense
    // Доходы
    case salary, transfersIn, cashback, otherIncome
    // Служебная: переводы между своими счетами
    case internalTransfer

    var id: String { rawValue }

    var isIncome: Bool {
        switch self {
        case .salary, .transfersIn, .cashback, .otherIncome: return true
        default: return false
        }
    }

    var isInternal: Bool { self == .internalTransfer }
    var isExpense: Bool { !isIncome && !isInternal }

    static var expenseCases: [Category] { allCases.filter(\.isExpense) }
    static var incomeCases: [Category] { allCases.filter(\.isIncome) }

    var title: String {
        switch self {
        case .groceries:        return "Продукты"
        case .cafe:             return "Кафе и рестораны"
        case .delivery:         return "Доставка еды"
        case .transport:        return "Транспорт"
        case .taxi:             return "Такси"
        case .car:              return "Авто и топливо"
        case .housing:          return "Жильё и ЖКХ"
        case .telecom:          return "Связь и интернет"
        case .health:           return "Здоровье"
        case .beauty:           return "Красота"
        case .clothes:          return "Одежда и обувь"
        case .home:             return "Дом и ремонт"
        case .marketplace:      return "Маркетплейсы"
        case .entertainment:    return "Развлечения"
        case .subscriptions:    return "Подписки"
        case .travel:           return "Путешествия"
        case .education:        return "Образование"
        case .kids:             return "Дети"
        case .pets:             return "Животные"
        case .gifts:            return "Подарки"
        case .transfersOut:     return "Переводы людям"
        case .cash:             return "Наличные"
        case .loans:            return "Кредиты"
        case .savings:          return "Накопления"
        case .taxes:            return "Налоги и госуслуги"
        case .otherExpense:     return "Другое"
        case .salary:           return "Зарплата"
        case .transfersIn:      return "Переводы от людей"
        case .cashback:         return "Кэшбэк и проценты"
        case .otherIncome:      return "Прочие доходы"
        case .internalTransfer: return "Между своими счетами"
        }
    }

    var symbol: String {
        switch self {
        case .groceries:        return "cart.fill"
        case .cafe:             return "cup.and.saucer.fill"
        case .delivery:         return "takeoutbag.and.cup.and.straw.fill"
        case .transport:        return "tram.fill"
        case .taxi:             return "car.side.fill"
        case .car:              return "fuelpump.fill"
        case .housing:          return "house.fill"
        case .telecom:          return "wifi"
        case .health:           return "cross.case.fill"
        case .beauty:           return "sparkles"
        case .clothes:          return "tshirt.fill"
        case .home:             return "hammer.fill"
        case .marketplace:      return "shippingbox.fill"
        case .entertainment:    return "ticket.fill"
        case .subscriptions:    return "repeat.circle.fill"
        case .travel:           return "airplane"
        case .education:        return "book.fill"
        case .kids:             return "figure.and.child.holdinghands"
        case .pets:             return "pawprint.fill"
        case .gifts:            return "gift.fill"
        case .transfersOut:     return "arrow.up.forward.circle.fill"
        case .cash:             return "banknote.fill"
        case .loans:            return "creditcard.fill"
        case .savings:          return "banknote"
        case .taxes:            return "building.columns.fill"
        case .otherExpense:     return "ellipsis.circle.fill"
        case .salary:           return "briefcase.fill"
        case .transfersIn:      return "arrow.down.backward.circle.fill"
        case .cashback:         return "percent"
        case .otherIncome:      return "plus.circle.fill"
        case .internalTransfer: return "arrow.left.arrow.right.circle.fill"
        }
    }

    var group: SpendGroup {
        switch self {
        case .groceries, .transport, .car, .housing, .telecom, .health,
             .education, .kids, .taxes:
            return .needs
        case .cafe, .delivery, .taxi, .beauty, .clothes, .home, .marketplace,
             .entertainment, .subscriptions, .travel, .pets, .gifts:
            return .wants
        case .loans, .savings:
            return .savings
        default:
            return .none
        }
    }
}
