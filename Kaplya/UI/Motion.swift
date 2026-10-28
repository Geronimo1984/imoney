import SwiftUI

/// Общие анимации приложения. Все они короткие и выключаются при «Уменьшении движения»:
/// тогда значения меняются сразу, без пружин и перелётов.
enum Motion {
    static let standard: Animation = .smooth(duration: 0.4)
    static let spring: Animation = .spring(response: 0.45, dampingFraction: 0.82)
    static let grow: Animation = .spring(response: 0.7, dampingFraction: 0.85).delay(0.1)

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
    var value: Double
    @ViewBuilder var content: (Double) -> Content
    @State private var shown: Double?

    var body: some View {
        content(shown ?? 0)
            .onAppear {
                guard shown == nil else { return }
                if reduceMotion { shown = value } else { withAnimation(Motion.grow) { shown = value } }
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
        Growing(value: value) { shown in
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
