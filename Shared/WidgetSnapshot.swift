import Foundation

/// Что показывает виджет. Приложение пишет снимок в общую папку группы, виджет его читает.
struct WidgetSnapshot: Codable {
    var perDay: Double
    var daysLeft: Int
    var spent: Double
    var income: Double
    /// Доли 50/30/20 относительно цели: обязательное, желания, накопления.
    var rings: [Double]
    var nextPaymentTitle: String?
    var nextPaymentAmount: Double?
    var nextPaymentDate: Date?
    var updated: Date

    static let group = "group.com.geronimo.kaplya"

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("widget.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = WidgetSnapshot.url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static let placeholder = WidgetSnapshot(perDay: 1_675, daysLeft: 3, spent: 131_841, income: 136_867,
                                            rings: [0.48, 1.2, 0.55], nextPaymentTitle: "Автокредит",
                                            nextPaymentAmount: 24_500, nextPaymentDate: Date().addingTimeInterval(86_400 * 3),
                                            updated: Date())

    /// «1 675 ₽» — без зависимости от форматтеров приложения.
    static func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = "\u{00A0}"
        return (f.string(from: NSNumber(value: value)) ?? "0") + "\u{00A0}₽"
    }
}
