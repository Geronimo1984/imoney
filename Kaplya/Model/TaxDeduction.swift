import Foundation

/// Социальные и имущественные вычеты НДФЛ, которые можно найти по выпискам.
enum TaxKind: String, CaseIterable, Identifiable {
    case treatment, medicine, education, kidsEducation, fitness, mortgage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .treatment:     return "Лечение"
        case .medicine:      return "Лекарства"
        case .education:     return "Своё обучение"
        case .kidsEducation: return "Обучение детей"
        case .fitness:       return "Спорт и фитнес"
        case .mortgage:      return "Проценты по ипотеке"
        }
    }

    var symbol: String {
        switch self {
        case .treatment:     return "cross.case.fill"
        case .medicine:      return "pills.fill"
        case .education:     return "graduationcap.fill"
        case .kidsEducation: return "figure.and.child.holdinghands"
        case .fitness:       return "figure.run"
        case .mortgage:      return "house.fill"
        }
    }

    /// Какой документ взять, чтобы вычет одобрили.
    var document: String {
        switch self {
        case .treatment:     return "Справка об оплате медицинских услуг для налоговой — в клинике"
        case .medicine:      return "Рецепт врача с отметкой «Для налоговой» и чеки аптеки"
        case .education:     return "Договор с учебным заведением, копия лицензии, справка об оплате"
        case .kidsEducation: return "Договор и справка об оплате; ребёнку до 24 лет, очное обучение"
        case .fitness:       return "Справка об оплате спортивных услуг — организация должна быть в списке Минспорта"
        case .mortgage:      return "Справка банка об уплаченных процентах и договор ипотеки"
        }
    }
}

struct TaxGroup: Identifiable {
    var kind: TaxKind
    var transactions: [Transaction]
    var amount: Decimal
    var id: TaxKind { kind }
}

struct TaxReport {
    var year: Int
    var groups: [TaxGroup]
    /// Сумма расходов, с которой положен вычет, после лимитов.
    var eligible: Decimal
    /// Сколько вернут: 13% от eligible, но не больше уплаченного налога.
    var refund: Decimal
    /// Оценка уплаченного НДФЛ по зарплате из выписок.
    var taxPaid: Decimal
}

extension Store {
    /// Лимиты НК РФ (ст. 219, 220) с 2024 года.
    static let socialLimit: Decimal = 150_000
    static let kidsLimit: Decimal = 110_000
    static let mortgageLimit: Decimal = 3_000_000

    private static func kind(of t: Transaction) -> TaxKind? {
        let name = t.counterparty
        switch t.category {
        case .health:
            return ["аптек", "apteka", "ригла", "горздрав", "еаптека", "здравсити", "36 6"].contains(where: name.contains)
                ? .medicine : .treatment
        case .education:
            return ["детск", "школ", "сад", "kids"].contains(where: name.contains) ? .kidsEducation : .education
        case .kids:
            return ["школ", "сад", "кружок", "секци"].contains(where: name.contains) ? .kidsEducation : nil
        default:
            return ["фитнес", "fitness", "спортклуб", "бассейн", "спортлайф", "world class", "x fit"].contains(where: name.contains)
                ? .fitness : nil
        }
    }

    /// Годы, за которые есть операции (вычет можно получить за три последних года).
    var taxYears: [Int] {
        let years = Set(transactions.map { Store.calendar.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    /// Год вычета для выбранного месяца; если за него операций нет — последний год с операциями.
    func taxYear(for month: Date) -> Int {
        let year = Store.calendar.component(.year, from: month)
        return taxYears.contains(year) ? year : (taxYears.first ?? year)
    }

    func taxReport(year: Int) -> TaxReport {
        let cal = Store.calendar
        let items = transactions.filter { cal.component(.year, from: $0.date) == year && $0.amount < 0 }
        var byKind: [TaxKind: [Transaction]] = [:]
        for t in items {
            if let k = Store.kind(of: t) { byKind[k, default: []].append(t) }
        }
        var groups = byKind.map { k, list in
            TaxGroup(kind: k, transactions: list.sorted { $0.date > $1.date }, amount: list.reduce(0) { $0 + $1.absAmount })
        }

        // Ипотека: проценты, уплаченные в этом году, — оценка по остатку и ставке
        for debt in debts where debt.kind == .mortgage && debt.rate > 0 {
            let months = year == cal.component(.year, from: Date()) ? cal.component(.month, from: Date()) : 12
            let interest = debt.balance * Decimal(debt.rate / 100 / 12) * Decimal(months)
            groups.append(TaxGroup(kind: .mortgage, transactions: [], amount: interest))
        }
        groups.sort { (TaxKind.allCases.firstIndex(of: $0.kind) ?? 0) < (TaxKind.allCases.firstIndex(of: $1.kind) ?? 0) }

        let social = groups.filter { [.treatment, .medicine, .education, .fitness].contains($0.kind) }.reduce(Decimal(0)) { $0 + $1.amount }
        let kids = groups.first { $0.kind == .kidsEducation }?.amount ?? 0
        let mortgage = groups.first { $0.kind == .mortgage }?.amount ?? 0
        let eligible = min(social, Store.socialLimit) + min(kids, Store.kidsLimit) + min(mortgage, Store.mortgageLimit)

        // В выписке зарплата приходит уже без налога: налог = чистая / 0.87 × 0.13
        let salary = transactions.filter { cal.component(.year, from: $0.date) == year && $0.category == .salary }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let taxPaid = salary / Decimal(0.87) * Decimal(0.13)
        // Зарплаты в выписках может не быть (приходит в другой банк) — тогда налог неизвестен и не ограничиваем
        let refund = taxPaid > 0 ? min(eligible * Decimal(0.13), taxPaid) : eligible * Decimal(0.13)
        return TaxReport(year: year, groups: groups, eligible: eligible, refund: refund, taxPaid: taxPaid)
    }
}
