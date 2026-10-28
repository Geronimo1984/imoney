import SwiftUI

enum Bank: String, Codable, CaseIterable, Identifiable {
    case tbank, sber, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tbank: return "Т-Банк"
        case .sber:  return "Сбер"
        case .other: return "Другой банк"
        }
    }

    var short: String {
        switch self {
        case .tbank: return "Т"
        case .sber:  return "С"
        case .other: return "Б"
        }
    }
}

/// Одна операция. Сумма со знаком: минус — списание, плюс — зачисление.
struct Transaction: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var amount: Decimal
    var currency: String = "RUB"
    var bank: Bank
    var card: String = ""
    var title: String
    var bankCategory: String = ""
    var mcc: String = ""
    var category: Category
    /// Категорию выбрал пользователь — правила и автоопределение её не трогают.
    var isManual = false
    /// Отпечаток для поиска дублей при повторном импорте.
    var fingerprint: String = ""
    var importID: UUID?
    /// Операция по кредитной карте: какой долг и что это — покупка, погашение или снятие.
    var creditDebtID: UUID?
    var creditRole: CreditRole?
    /// Категория до разметки по кредитке — чтобы вернуть её, если карту удалят или сменят цифры.
    var categoryBeforeCredit: Category?

    var absAmount: Decimal { amount < 0 ? -amount : amount }

    /// Сколько операция добавляет к расходам: возврат по расходной категории уменьшает их.
    var expenseValue: Decimal {
        guard category.isExpense else { return 0 }
        return -amount
    }

    var incomeValue: Decimal {
        guard category.isIncome else { return 0 }
        return amount
    }

    /// Получатель или магазин без мусора — ключ для правил и подписок.
    /// Нормализация — пять регулярных выражений; сводка спрашивает получателя тысячи раз за перерисовку,
    /// поэтому результат кэшируется по исходному названию (NSCache потокобезопасен).
    var counterparty: String {
        let key = title as NSString
        if let cached = Transaction.counterpartyCache.object(forKey: key) { return cached as String }
        let value = Transaction.normalize(title)
        Transaction.counterpartyCache.setObject(value as NSString, forKey: key)
        return value
    }

    private static let counterpartyCache = NSCache<NSString, NSString>()

    static func normalize(_ text: String) -> String {
        var s = text.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
        // Номера карт, коды авторизации, города и страны в конце строки из PDF Сбера
        s = s.replacingOccurrences(of: #"\*+\d{2,4}"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b\d{4,}\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b(rus|moscow|moskva|g\.?|россия)\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[^\p{L}\p{N} .]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}

/// «Всегда относить операции с этим получателем к категории».
struct CategoryRule: Codable, Identifiable, Hashable {
    var id = UUID()
    var match: String
    var category: Category
}

struct ImportRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var fileName: String
    var bank: Bank
    var added: Int
    var duplicates: Int
    var internalFound: Int
}

extension Decimal {
    var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}

/// Роль операции по кредитной карте.
enum CreditRole: String, Codable {
    /// Покупка по кредитке — обычная трата, но в долг.
    case purchase
    /// Пополнение кредитки — погашение долга.
    case repayment
    /// Снятие или перевод с кредитки на свой счёт — долг растёт, но это не трата.
    case withdrawal

    var title: String {
        switch self {
        case .purchase:   return "Покупка по кредитке"
        case .repayment:  return "Погашение кредитки"
        case .withdrawal: return "Снятие с кредитки"
        }
    }
}

