import SwiftUI

/// Короткие объяснения основ — как статьи «Узнать больше» в приложении Здоровье.
struct Lesson: Identifiable, Hashable {
    var id: String { title }
    var symbol: String
    var color: Color
    var title: String
    var text: String

    static let all: [Lesson] = [
        Lesson(symbol: "lifepreserver.fill", color: .orange, title: "Подушка безопасности",
               text: "Запас на 3–6 месяцев обязательных трат на отдельном накопительном счёте. Она спасает при потере работы или болезни и избавляет от кредитов на срочные нужды."),
        Lesson(symbol: "chart.pie.fill", color: .blue, title: "Правило 50 / 30 / 20",
               text: "50% дохода — обязательное (жильё, еда, транспорт), 30% — желания, 20% — накопления и досрочное погашение долгов. Это ориентир, а не закон: главное — чтобы последняя часть не была нулевой."),
        Lesson(symbol: "creditcard.trianglebadge.exclamationmark", color: .red, title: "Рассрочка и кредитка",
               text: "«Сплит», «долями» и льготный период кажутся бесплатными, но легко копятся. Пропустили платёж или вышли за льготный период — ставка может быть 30–60% годовых."),
        Lesson(symbol: "arrow.down.to.line", color: .green, title: "Сначала заплати себе",
               text: "Откладывайте фиксированную сумму в день зарплаты, а не то, что осталось в конце месяца. В конце месяца обычно не остаётся ничего.")
    ]
}

struct LessonView: View {
    var lesson: Lesson

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: lesson.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(lesson.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(lesson.title).font(.largeTitle.weight(.bold))
                Text(lesson.text).font(.body)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Пошаговая инструкция, как выгрузить выписку из банка.
struct HowToView: View {
    var bank: Bank

    var steps: [String] {
        switch bank {
        case .tbank:
            return ["В приложении Т-Банка закажите «Справку о движении средств» за нужный период — придёт PDF",
                    "Или в веб-версии tbank.ru: «Операции» → период → выгрузка в CSV",
                    "«Поделиться» → «iMoney» или «Сохранить в Файлы»",
                    "Если файл сохранён в папку автозагрузки, iMoney загрузит его сам"]
        case .sber, .other:
            return ["СберБанк Онлайн → нужная карта",
                    "«Выписки и справки» → «Выписка по счёту»",
                    "Выберите период и формат PDF",
                    "«Поделиться» → «iMoney» или «Сохранить в Файлы»"]
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.accentColor, in: Circle())
                        Text(step)
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Названия пунктов в приложении банка могут немного отличаться.")
            }
        }
        .navigationTitle(bank == .tbank ? "Выписка Т-Банка" : "Выписка Сбера")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Запомненные получатели — правила «всегда в эту категорию».
struct RulesView: View {
    @Environment(Store.self) private var store

    var body: some View {
        List {
            ForEach(store.rules) { rule in
                HStack(spacing: 12) {
                    CategoryBadge(category: rule.category)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.match).lineLimit(1)
                        Text(rule.category.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { store.rules[$0] }.forEach(store.deleteRule)
            }
        }
        .overlay {
            if store.rules.isEmpty {
                ContentUnavailableView("Нет запомненных получателей", systemImage: "person.crop.circle.badge.checkmark",
                                       description: Text("Включите «Применять к будущим» на странице операции."))
            }
        }
        .toolbar { if !store.rules.isEmpty { EditButton() } }
        .navigationTitle("Получатели")
    }
}
