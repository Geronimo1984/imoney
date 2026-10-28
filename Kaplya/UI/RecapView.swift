import SwiftUI

/// Итоги месяца: карточка-награда, которой можно поделиться.
struct RecapView: View {
    @Environment(Store.self) private var store
    @Environment(\.displayScale) private var scale
    var month: Date

    var body: some View {
        let recap = store.recap(for: month)
        // Для картинки «Поделиться» — карточка без анимации, сразу с итоговыми числами
        let card = RecapCard(recap: recap)
        ScrollView {
            VStack(spacing: 20) {
                RecapCard(recap: recap, animated: true)
                if let image = ImageRenderer(content: card.frame(width: 360).environment(\.colorScheme, .dark)).withScale(scale).uiImage {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Итоги \(Fmt.month(month))", image: Image(uiImage: image))) {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Итоги месяца")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension ImageRenderer {
    @MainActor func withScale(_ s: CGFloat) -> ImageRenderer {
        scale = s
        return self
    }
}

struct RecapCard: View {
    var recap: MonthRecap
    /// На экране блоки появляются по очереди, а суммы досчитываются — как в «Воспоминаниях»
    var animated = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Analytics.isCurrent(recap.month) ? "ИТОГИ НА СЕГОДНЯ" : "ИТОГИ МЕСЯЦА").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                Text(Fmt.month(recap.month)).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            .modifier(Reveal(step: 0, shown: shown, pop: true))
            HStack(spacing: 12) {
                tile(recap.balance >= 0 ? "В плюсе" : "В минусе", money(recap.balance < 0 ? -recap.balance : recap.balance),
                     recap.balance >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill", recap.balance >= 0 ? .green : .orange)
                tile("Отложено", money(recap.saved), "banknote.fill", .mint)
            }
            .modifier(Reveal(step: 1, shown: shown))
            HStack(spacing: 12) {
                tile("Дней без трат", number(Double(recap.daysWithoutSpending)) { "\(Int($0.rounded()))" }, "leaf.fill", .teal)
                tile("Погашено долгов", money(recap.debtPaid), "checkmark.seal.fill", .purple)
            }
            .modifier(Reveal(step: 2, shown: shown))
            VStack(alignment: .leading, spacing: 8) {
                if let cut = recap.bestCut {
                    line("arrow.down.right", .green, "\(cut.0.title): на \(Fmt.money(cut.1)) меньше, чем \(Analytics.isCurrent(recap.month) ? "за те же дни прошлого месяца" : "в прошлом месяце")")
                }
                if let top = recap.topCategory {
                    line(top.category.symbol, .orange, "Больше всего — \(top.category.title.lowercased()), \(Fmt.money(top.amount))")
                }
                line("list.bullet", .white.opacity(0.7), "\(recap.operations) \(Fmt.plural(recap.operations, "операция", "операции", "операций")), доход \(Fmt.money(recap.income))")
            }
            .modifier(Reveal(step: 3, shown: shown))
            HStack {
                Spacer()
                Text("iMoney").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.16), Color(red: 0.05, green: 0.05, blue: 0.08)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            guard animated, !appeared else { return }
            if Motion.reduced { appeared = true } else { withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { appeared = true } }
        }
    }

    private var shown: Bool { !animated || appeared }

    private func money(_ value: Decimal) -> AnyView {
        number(value.double) { Fmt.money(Decimal($0.rounded())) }
    }

    /// Число на экране досчитывается от нуля, в картинке для «Поделиться» — сразу итоговое.
    private func number(_ value: Double, _ format: @escaping (Double) -> String) -> AnyView {
        animated ? AnyView(CountingText(value: value, format: format)) : AnyView(Text(format(value)))
    }

    private func tile(_ title: String, _ value: AnyView, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
                .symbolEffect(.bounce, value: appeared)
            value.font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func line(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 20)
            Text(text).font(.subheadline).foregroundStyle(.white)
        }
    }
}

/// Блок итогов появляется своим шагом: снизу вверх с лёгкой задержкой; заголовок — с пружиной.
private struct Reveal: ViewModifier {
    var step: Int
    var shown: Bool
    var pop = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .scaleEffect(shown || !pop ? 1 : 0.85, anchor: .leading)
            .animation(Motion.reduced ? nil : .spring(response: 0.5, dampingFraction: 0.72).delay(Double(step) * 0.12), value: shown)
    }
}
