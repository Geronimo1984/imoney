import SwiftUI

/// Общие анимации приложения. Все они короткие и выключаются при «Уменьшении движения»:
/// тогда значения меняются сразу, без пружин и перелётов.
enum Motion {
    static let standard: Animation = .smooth(duration: 0.4)
    static let spring: Animation = .spring(response: 0.45, dampingFraction: 0.82)
    /// Рост полосок и колец: ровно полсекунды, без пружинного «хвоста», который держит анимацию ещё секунду-две.
    static let grow: Animation = .easeOut(duration: 0.5).delay(0.05)

    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// withAnimation, который уважает «Уменьшение движения».
    static func animate(_ animation: Animation = standard, _ body: () -> Void) {
        if reduced { body() } else { withAnimation(animation, body) }
    }
}

extension View {
    /// Неявная анимация, выключенная при «Уменьшении движения».
    func motion<V: Equatable>(_ animation: Animation = Motion.standard, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }

    /// Источник «зум»-перехода (iOS 18): экран раскрывается из карточки и сворачивается в неё обратно.
    /// На iOS 17 — обычный переход.
    @ViewBuilder
    func zoomSource(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Экран, который открывается «зумом» из zoomSource с тем же id.
    @ViewBuilder
    func zoomTransition(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

extension View {
    /// Значок пустого экрана медленно «дышит», как у системных заглушек (на iOS 17 — мерцает).
    func emptyStateSymbol() -> some View {
        modifier(EmptyStateSymbol())
    }
}

private struct EmptyStateSymbol: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else if #available(iOS 18, *) {
            content.symbolEffect(.breathe)
        } else {
            content.symbolEffect(.pulse)
        }
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animation: Animation
    var value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// Значение, которое при появлении дорастает от нуля, а потом плавно следует за изменениями —
/// как кольца в «Фитнесе». Используется полосками прогресса.
struct Growing<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.growOnAppear) private var growOnAppear
    var value: Double
    /// Растёт при каждом появлении, даже на вкладке, где вступление уже сыграло:
    /// итоги месяца, результат загрузки, подробности долга — это отдельные события, а не содержимое вкладки.
    var always = false
    @ViewBuilder var content: (Double) -> Content
    @State private var shown: Double?

    private var grows: Bool { always || growOnAppear }

    var body: some View {
        content(shown ?? (grows ? 0 : value))
            .onAppear {
                guard shown == nil else { return }
                if reduceMotion || !grows { shown = value } else { withAnimation(Motion.grow) { shown = value } }
            }
            .onChange(of: value) { _, new in
                if reduceMotion { shown = new } else { withAnimation(Motion.standard) { shown = new } }
            }
    }
}

/// Полоска прогресса, которая дорастает до значения; смена цвета (например, при превышении лимита) тоже плавная.
struct GrowingProgress: View {
    var value: Double
    var tint: Color

    var body: some View {
        Growing(value: value) { shown in
            ProgressView(value: min(max(shown, 0), 1))
                .tint(tint)
                .motion(value: tint)
        }
    }
}

/// Сумма, которая при появлении досчитывается от нуля — для итогов и результата загрузки.
struct CountingText: View {
    var value: Double
    var format: (Double) -> String

    var body: some View {
        Growing(value: value, always: true) { shown in
            CountingLabel(value: shown, format: format).monospacedDigit()
        }
    }
}

/// Текст, который SwiftUI перерисовывает на каждом кадре анимации, — поэтому число именно досчитывается.
private struct CountingLabel: View, Animatable {
    var value: Double
    var format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

/// Отклик для действий, у которых нет своего состояния-триггера (удаление свайпом).
enum Haptic {
    static func delete() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

extension EnvironmentValues {
    /// Полоски и кольца вырастают при появлении. Выключается, когда вкладка уже показывала вступление.
    @Entry var growOnAppear = true
}

extension View {
    /// Вступительный рост полосок и колец — только при первом открытии вкладки.
    /// Список пересоздаёт строки при каждом возврате на вкладку, и без этого всё росло заново:
    /// десятки анимаций разом, переключение вкладок подтормаживало.
    func growIntro(_ screen: String) -> some View {
        modifier(GrowIntro(screen: screen))
    }
}

private struct GrowIntro: ViewModifier {
    @MainActor static var played: Set<String> = []
    var screen: String
    @State private var active: Bool?

    func body(content: Content) -> some View {
        content
            .environment(\.growOnAppear, active ?? !GrowIntro.played.contains(screen))
            .onAppear {
                guard active == nil else { return }
                active = !GrowIntro.played.contains(screen)
                GrowIntro.played.insert(screen)
                // Вступление успевает доиграть, дальше полоски сразу стоят на месте
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { active = false }
            }
    }
}
