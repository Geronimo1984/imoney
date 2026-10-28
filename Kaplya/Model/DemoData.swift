import Foundation

/// Правдоподобные три месяца операций по Т-Банку и Сберу — для знакомства с приложением.
enum DemoData {

    private struct RNG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(1 << 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() * Double(range.count)) % range.count
        }
        mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }
    }

    static func transactions(now: Date = Date()) -> [Transaction] {
        let cal = Store.calendar
        var rng = RNG(state: 42)
        var rows: [(Bank, ParsedRow)] = []
        let thisMonth = Store.startOfMonth(now)

        func date(_ month: Date, _ day: Int, _ hour: Int, _ minute: Int) -> Date? {
            var c = cal.dateComponents([.year, .month], from: month)
            c.day = day
            c.hour = hour
            c.minute = minute
            guard let d = cal.date(from: c), d <= now else { return nil }
            return d
        }

        func add(_ bank: Bank, _ month: Date, _ day: Int, _ amount: Decimal, _ title: String,
                 category: String = "", mcc: String = "", hour: Int? = nil, card: String? = nil) {
            let h = hour ?? rng.int(8...22)
            guard let d = date(month, day, h, rng.int(0...59)) else { return }
            rows.append((bank, ParsedRow(date: d, amount: amount,
                                         card: card ?? (bank == .tbank ? "*4417" : "****2058"),
                                         title: title, bankCategory: category, mcc: mcc)))
        }

        for offset in (0...3).reversed() {
            guard let month = cal.date(byAdding: .month, value: -offset, to: thisMonth) else { continue }
            let days = cal.range(of: .day, in: .month, for: month)?.count ?? 30
            let isCurrent = offset == 0

            // Доходы — на Сбер
            add(.sber, month, 5, 78_000, "Зачисление заработной платы ООО Ромашка", category: "Зарплата", hour: 10)
            add(.sber, month, 20, 57_000, "Зачисление заработной платы (аванс) ООО Ромашка", category: "Зарплата", hour: 10)
            add(.tbank, month, 3, Decimal(rng.int(900...1600)), "Кэшбэк за покупки", category: "Бонусы")
            add(.sber, month, 1, Decimal(rng.int(250...450)), "Выплата процентов по накопительному счёту", category: "Проценты")

            // Перевод себе со Сбера на Т-Банк — банки видят его как расход и доход
            add(.sber, month, 5, -40_000, "Перевод с карты на карту ТБАНК", category: "Перевод с карты", hour: 12)
            add(.tbank, month, 5, 40_000, "Пополнение. Сбербанк", category: "Пополнения", hour: 12)
            add(.sber, month, 20, -25_000, "Перевод СБП в Т-Банк", category: "Перевод СБП", hour: 13)
            add(.tbank, month, 20, 25_000, "Пополнение через СБП. Сбербанк", category: "Пополнения", hour: 13)

            // Аренда — перевод человеку, банк не знает, что это
            add(.sber, month, 1, -35_000, "Перевод для Ивана П.", category: "Перевод с карты", hour: 9)
            add(.sber, month, 12, -6_480, "ЖКУ Москва ЕПД", category: "Коммунальные платежи, связь, интернет", mcc: "4900")
            add(.tbank, month, 7, -650, "МТС", category: "Мобильная связь", mcc: "4814")
            add(.tbank, month, 15, -890, "Ростелеком интернет", category: "Связь", mcc: "4814")

            // Подписки
            add(.tbank, month, 9, -399, "YANDEX PLUS", category: "Цифровые товары", mcc: "5815")
            add(.tbank, month, 14, -299, "APPLE.COM/BILL", category: "Цифровые товары", mcc: "5818")
            add(.tbank, month, 22, -399, "OKKO", category: "Цифровые товары", mcc: "5815")
            add(.sber, month, 18, -1_990, "Фитнес Спортлайф абонемент", category: "Отдых и развлечения", mcc: "7997")

            // Ежедневные траты
            let groceries = ["ПЯТЕРОЧКА", "ПЕРЕКРЕСТОК", "ВКУСВИЛЛ", "MAGNIT MM"]
            for _ in 0..<11 {
                add(.tbank, month, rng.int(1...days), -Decimal(rng.int(380...3200)), rng.pick(groceries),
                    category: "Супермаркеты", mcc: "5411")
            }
            for _ in 0..<2 {
                add(.sber, month, rng.int(1...days), -Decimal(rng.int(1500...5200)), "AUCHAN", category: "Супермаркеты", mcc: "5411")
            }
            let coffeeCount = isCurrent ? 16 : 11
            for _ in 0..<coffeeCount {
                add(.tbank, month, rng.int(1...days), -Decimal(rng.int(190...420)), rng.pick(["COFIX", "STARS COFFEE", "SURF COFFEE"]),
                    category: "Фастфуд", mcc: "5814", hour: rng.int(8...11))
            }
            for _ in 0..<3 {
                add(.tbank, month, rng.int(1...days), -Decimal(rng.int(1800...4600)), rng.pick(["Ресторан Хачапури и вино", "Теремок", "Суши Make"]),
                    category: "Рестораны", mcc: "5812")
            }
            // Доставка растёт в текущем месяце — повод для подсказки
            let deliveryCount = isCurrent ? 11 : 5
            for _ in 0..<deliveryCount {
                add(.tbank, month, rng.int(1...days), -Decimal(rng.int(650...1900)), rng.pick(["Яндекс Еда", "Самокат", "Кухня на районе"]),
                    category: "Фастфуд", mcc: "5814", hour: rng.int(19...23))
            }
            for _ in 0..<6 {
                add(.tbank, month, rng.int(1...days), -Decimal(rng.int(260...980)), "Яндекс Такси", category: "Такси", mcc: "4121")
            }
            for _ in 0..<5 {
                add(.tbank, month, rng.int(1...days), -Decimal(rng.int(62...130)), "MOSMETRO", category: "Местный транспорт", mcc: "4111")
            }
            for _ in 0..<4 {
                add(.tbank, month, rng.int(1...days), -Decimal(rng.int(700...6800)), rng.pick(["OZON", "WILDBERRIES"]),
                    category: "Различные товары", mcc: "5399")
            }
            for _ in 0..<2 {
                add(.sber, month, rng.int(1...days), -Decimal(rng.int(350...2400)), "Аптека Ригла", category: "Здоровье и красота", mcc: "5912")
            }
            if offset == 1 {
                add(.sber, month, 11, -8_990, "ZARA", category: "Одежда и аксессуары", mcc: "5651")
                add(.tbank, month, 24, -2_800, "Кинотеатр Формула Кино", category: "Кино", mcc: "7832")
            }
            if offset == 2 {
                add(.tbank, month, 3, -18_400, "AEROFLOT", category: "Авиабилеты", mcc: "4511")
                add(.tbank, month, 4, -24_600, "OSTROVOK.RU", category: "Отели", mcc: "7011")
            }
            // Переводы людям
            add(.sber, month, rng.int(1...days), -Decimal(rng.int(5...15) * 100), "Перевод для Анны С.", category: "Перевод СБП")
            add(.tbank, month, rng.int(1...days), -3_000, "Перевод Марии К.", category: "Переводы")
            add(.sber, month, 25, -4_500, "Перевод для Олега Р. Репетитор", category: "Перевод с карты")
            add(.tbank, month, rng.int(1...days), Decimal(rng.int(4...12) * 100), "Перевод от Дмитрия В.", category: "Пополнения")
            // Возврат по маркетплейсу
            if offset == 1 {
                add(.tbank, month, 19, 2_390, "OZON возврат", category: "Различные товары", mcc: "5399")
            }
            add(.sber, month, 28, -5_000, "Погашение кредита по договору", category: "Прочие операции")
            add(.tbank, month, 10, -10_000, "Перевод в Копилку", category: "Финансы")
            // Кредитная карта *7788: покупки по ней и погашение с дебетовой карты
            add(.tbank, month, 6, -Decimal(rng.int(2500...6000)), "OZON", category: "Различные товары", mcc: "5399", card: "*7788")
            add(.tbank, month, 14, -Decimal(rng.int(1500...3500)), "Ресторан Хачапури и вино", category: "Рестораны", mcc: "5812", card: "*7788")
            add(.tbank, month, 21, -Decimal(rng.int(800...2000)), "ПЯТЕРОЧКА", category: "Супермаркеты", mcc: "5411", card: "*7788")
            add(.tbank, month, 25, -8_000, "Внутренний перевод на карту *7788", category: "Переводы", hour: 12)
            add(.tbank, month, 25, 8_000, "Пополнение. Внутренний перевод", category: "Пополнения", hour: 12, card: "*7788")
        }

        var occurrences: [String: Int] = [:]
        return rows.map { bank, row in
            let base = Store.fingerprint(bank: bank, row: row)
            let n = occurrences[base, default: 0]
            occurrences[base] = n + 1
            return Transaction(
                date: row.date, amount: row.amount, bank: bank, card: row.card, title: row.title,
                bankCategory: row.bankCategory, mcc: row.mcc,
                category: Categorizer.category(title: row.title, bankCategory: row.bankCategory,
                                               mcc: row.mcc, amount: row.amount, rules: []),
                fingerprint: base + "#\(n)", importID: bank == .tbank ? tbankImport : sberImport)
        }
        .sorted { $0.date > $1.date }
    }

    private static let tbankImport = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private static let sberImport = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    static func imports(for transactions: [Transaction]) -> [ImportRecord] {
        let tCount = transactions.filter { $0.importID == tbankImport }.count
        let sCount = transactions.count - tCount
        return [
            ImportRecord(id: tbankImport, date: Date(), fileName: "operations_tbank_demo.csv", bank: .tbank,
                         added: tCount, duplicates: 0, internalFound: 0),
            ImportRecord(id: sberImport, date: Date(), fileName: "Выписка_Сбер_демо.pdf", bank: .sber,
                         added: sCount, duplicates: 0, internalFound: 0)
        ]
    }
}
