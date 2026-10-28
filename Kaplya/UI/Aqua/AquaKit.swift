import SwiftUI

/// Глянцевое оформление в духе Aqua и iOS 6: выпуклые «леденцы» с бликом на верхней половине,
/// глянцевые панели, фон в тонкую полоску, белые сгруппированные таблицы.
enum Aqua {
    static let font = "Helvetica Neue"
    /// Синий гель — одинаковый в обеих темах.
    static let blue = Color(red: 0.16, green: 0.45, blue: 0.92)

    // Цвета, которые меняются вместе с темой телефона: светлая — как iOS 6, тёмная — графит в духе чёрных панелей iOS 6.
    static let text = Color.dynamic(UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1), UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))
    static let label = Color.dynamic(UIColor(red: 0.30, green: 0.34, blue: 0.42, alpha: 1), UIColor(red: 0.66, green: 0.69, blue: 0.75, alpha: 1))
    static let line = Color.dynamic(UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1), UIColor(red: 0.24, green: 0.25, blue: 0.28, alpha: 1))
    /// Синий для текста: в тёмной теме светлее, чтобы читался на графите.
    static let link = Color.dynamic(UIColor(red: 0.16, green: 0.45, blue: 0.92, alpha: 1), UIColor(red: 0.45, green: 0.68, blue: 1.0, alpha: 1))
    static let positive = Color.dynamic(UIColor(red: 0.13, green: 0.55, blue: 0.25, alpha: 1), UIColor(red: 0.38, green: 0.85, blue: 0.48, alpha: 1))
    static let negative = Color.dynamic(UIColor(red: 0.75, green: 0.15, blue: 0.12, alpha: 1), UIColor(red: 1.0, green: 0.48, blue: 0.44, alpha: 1))
    static let card = Color.dynamic(.white, UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1))
    static let stripeA = Color.dynamic(UIColor(red: 0.78, green: 0.81, blue: 0.86, alpha: 1), UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1))
    static let stripeB = Color.dynamic(UIColor(red: 0.82, green: 0.84, blue: 0.89, alpha: 1), UIColor(red: 0.10, green: 0.11, blue: 0.12, alpha: 1))
    static let emboss = Color.dynamic(UIColor(white: 1, alpha: 0.8), UIColor(white: 0, alpha: 0.7))
    static let barTop = Color.dynamic(UIColor(red: 0.69, green: 0.75, blue: 0.84, alpha: 1), UIColor(red: 0.30, green: 0.31, blue: 0.34, alpha: 1))
    static let barBottom = Color.dynamic(UIColor(red: 0.43, green: 0.52, blue: 0.67, alpha: 1), UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1))
    static let barEdge = Color.dynamic(UIColor(red: 0.18, green: 0.24, blue: 0.33, alpha: 1), .black)
    static let chromeTop = Color.dynamic(.white, UIColor(red: 0.30, green: 0.31, blue: 0.34, alpha: 1))
    static let chromeBottom = Color.dynamic(UIColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1), UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1))
    static let gloss = Color.dynamic(.white, UIColor(white: 1, alpha: 0.35))
    static let troughTop = Color.dynamic(UIColor(red: 0.80, green: 0.81, blue: 0.84, alpha: 1), UIColor(white: 0.03, alpha: 1))
    static let troughBottom = Color.dynamic(UIColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1), UIColor(white: 0.14, alpha: 1))
    static let selection = Color.dynamic(UIColor(red: 0.22, green: 0.33, blue: 0.53, alpha: 1), UIColor(red: 0.45, green: 0.68, blue: 1.0, alpha: 1))

    /// Цвет кнопок на панели навигации: синий в светлой теме, графитовый в тёмной.
    static func barButton(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.26, green: 0.27, blue: 0.30) : Color(red: 0.30, green: 0.42, blue: 0.62)
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(weight == .bold ? "HelveticaNeue-Bold" : (weight == .medium ? "HelveticaNeue-Medium" : "HelveticaNeue"), size: size)
    }
}

// MARK: Фон в полоску (как у сгруппированных таблиц iOS 6)

struct Pinstripes: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Aqua.stripeA))
            var x: CGFloat = 0
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 3, height: size.height)),
                             with: .color(Aqua.stripeB))
                x += 7
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: Гель-«леденец»

/// Выпуклый глянцевый гель: цвет густеет книзу, снизу светится, верхнюю половину накрывает яркий блик.
struct AquaGel<S: Shape>: View {
    var shape: S
    var color: Color = Aqua.blue
    var shadow = true

    var body: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [color.mixed(with: .white, 0.25), color, color.mixed(with: .black, 0.25)],
                                      startPoint: .top, endPoint: .bottom))
            // Свечение снизу: свет проходит сквозь гель
            shape.fill(RadialGradient(colors: [color.mixed(with: .white, 0.55).opacity(0.9), .clear],
                                      center: UnitPoint(x: 0.5, y: 1.05), startRadius: 0, endRadius: 60))
            // Глянцевый блик: резко обрывается на середине
            shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0.85), location: 0),
                                              .init(color: .white.opacity(0.30), location: 0.46),
                                              .init(color: .white.opacity(0.0), location: 0.5)],
                                      startPoint: .top, endPoint: .bottom))
                .padding(.horizontal, 3)
                .padding(.top, 1.5)
            shape.stroke(color.mixed(with: .black, 0.45), lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: shadow ? .black.opacity(0.35) : .clear, radius: 1.5, x: 0, y: 1)
        .allowsHitTesting(false)
    }
}

/// Белый глянцевый «леденец» — для невыбранных кнопок.
struct AquaWhite<S: Shape>: View {
    var shape: S

    var body: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [Aqua.chromeTop, Aqua.chromeBottom], startPoint: .top, endPoint: .bottom))
            shape.fill(LinearGradient(stops: [.init(color: Aqua.gloss, location: 0),
                                              .init(color: Aqua.gloss.opacity(0.6), location: 0.48),
                                              .init(color: .clear, location: 0.5)],
                                      startPoint: .top, endPoint: .bottom))
                .padding(.horizontal, 3)
            shape.stroke(Aqua.line, lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
        .allowsHitTesting(false)
    }
}

extension Color {
    func mixed(with other: Color, _ amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return Color(red: Double(r1 + (r2 - r1) * t), green: Double(g1 + (g2 - g1) * t), blue: Double(b1 + (b2 - b1) * t))
    }
}

extension View {
    /// Выдавленный текст: светлая тень снизу, как подписи на фоне в полоску.
    func embossed() -> some View {
        shadow(color: Aqua.emboss, radius: 0, x: 0, y: 1)
    }

    /// Текст на глянцевой панели: белый с тёмной тенью сверху.
    func onBar() -> some View {
        foregroundStyle(.white).shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: -1)
    }

    /// Белая карточка сгруппированной таблицы.
    func groupCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Aqua.card)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Aqua.line, lineWidth: 1))
                .shadow(color: Aqua.emboss, radius: 0, x: 0, y: 1)
        )
    }
}

// MARK: Глянцевая панель навигации

struct AquaNavBar<Leading: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title).font(Aqua.font(20, .bold)).onBar().lineLimit(1)
            HStack {
                leading
                Spacer()
                trailing
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: [Aqua.barTop, Aqua.barBottom],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(stops: [.init(color: .white.opacity(0.35), location: 0), .init(color: .white.opacity(0.08), location: 0.5),
                                       .init(color: .clear, location: 0.5)],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: 0) {
                    Color.white.opacity(0.5).frame(height: 1)
                    Spacer()
                    Aqua.barEdge.frame(height: 1)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}

extension AquaNavBar where Leading == EmptyView, Trailing == EmptyView {
    init(title: String) {
        self.init(title: title, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// Кнопка на панели навигации: тёмно-синий глянцевый прямоугольник.
struct AquaBarButton: View {
    @Environment(\.colorScheme) private var scheme
    var symbol: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .onBar()
                .frame(width: 34, height: 30)
                .background(AquaGel(shape: RoundedRectangle(cornerRadius: 5), color: Aqua.barButton(scheme), shadow: false))
        }
        .buttonStyle(AquaPress())
        .accessibilityLabel(label)
    }
}

/// Кнопка «Назад» в форме стрелки, как в iOS 6.
struct BackArrowShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let tip: CGFloat = 12
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + tip, y: r.minY + 1))
        p.addLine(to: CGPoint(x: r.maxX - 5, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 5), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 5))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 5, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + tip, y: r.maxY - 1))
        p.closeSubpath()
        return p
    }
}

struct AquaBackButton: View {
    @Environment(\.colorScheme) private var scheme
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Aqua.font(12, .bold)).onBar()
                .padding(.leading, 16).padding(.trailing, 9)
                .frame(height: 30)
                .background(AquaGel(shape: BackArrowShape(), color: Aqua.barButton(scheme), shadow: false))
        }
        .buttonStyle(AquaPress())
    }
}

// MARK: Кнопки

/// Большая кнопка-«леденец».
struct AquaButton: View {
    var title: String
    var symbol: String? = nil
    var color: Color = Aqua.blue
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 16, weight: .bold)) }
                Text(title).font(Aqua.font(17, .bold))
            }
            .onBar()
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(AquaGel(shape: Capsule(), color: color))
        }
        .buttonStyle(AquaPress())
    }
}

/// Нажатие в духе iOS 6: гель темнеет и чуть «вдавливается», без системного полупрозрачного мигания.
struct AquaPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.14 : 0)
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.97 : 1)
            .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.18), value: configuration.isPressed)
    }
}

/// Сегменты в духе iOS 6: выбранный — синий гель, остальные — белый глянец.
struct AquaSegments<T: Hashable>: View {
    var items: [(T, String)]
    @Binding var selection: T

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(items, id: \.0) { value, title in
                    Button { Motion.animate(.easeOut(duration: 0.15)) { selection = value } } label: {
                        Text(title).font(Aqua.font(13, .bold))
                            .foregroundStyle(selection == value ? .white : Aqua.label)
                            .shadow(color: selection == value ? .black.opacity(0.4) : Aqua.emboss, radius: 0, x: 0, y: selection == value ? -1 : 1)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background {
                                if selection == value {
                                    AquaGel(shape: Capsule())
                                } else {
                                    AquaWhite(shape: Capsule())
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
        }
        .buttonStyle(AquaPress())
        .sensoryFeedback(.selection, trigger: selection)
        .scrollIndicators(.hidden)
    }
}

/// Полоса прогресса Aqua: утопленный жёлоб и гелевая заливка.
struct AquaProgress: View {
    var value: Double
    var color: Color = Aqua.blue
    var marker: Double? = nil
    var height: CGFloat = 12

    var body: some View {
        // Гель наливается при появлении и плавно следует за значением
        Growing(value: value) { shown in
            bar(shown)
        }
        .frame(height: height)
    }

    private func bar(_ value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [Aqua.troughTop, Aqua.troughBottom],
                                              startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(Aqua.line, lineWidth: 1))
                AquaGel(shape: Capsule(), color: color, shadow: false)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .opacity(value > 0 ? 1 : 0)
                if let marker {
                    Rectangle().fill(Aqua.text.opacity(0.7))
                        .frame(width: 2, height: height + 6)
                        .offset(x: geo.size.width * min(max(marker, 0), 1) - 1)
                }
            }
        }
        .frame(height: height)
    }
}

/// Значок категории — гелевый квадратик.
struct AquaIcon: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .bold))
            .onBar()
            .frame(width: size, height: size)
            .background(AquaGel(shape: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous), color: color))
    }
}

/// Заголовок раздела над карточкой — выдавленный текст на полоске.
struct AquaSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(Aqua.font(16, .bold)).foregroundStyle(Aqua.label).embossed()
                .padding(.leading, 10)
            content
        }
    }
}

// MARK: Чёрная глянцевая панель вкладок

struct AquaTabBar: View {
    @Binding var tab: String
    var items: [(String, String, String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { id, title, symbol in
                let selected = tab == id
                Button { tab = id } label: {
                    VStack(spacing: 2) {
                        Image(systemName: symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(selected
                                             ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.55, green: 0.85, blue: 1), Color(red: 0.10, green: 0.50, blue: 0.95)],
                                                                            startPoint: .top, endPoint: .bottom))
                                             : AnyShapeStyle(Color(red: 0.55, green: 0.55, blue: 0.57)))
                            .shadow(color: selected ? Color(red: 0.3, green: 0.7, blue: 1).opacity(0.8) : .clear, radius: 4)
                            .frame(height: 28)
                        Text(title).font(Aqua.font(10, .bold))
                            .foregroundStyle(selected ? .white : Color(red: 0.6, green: 0.6, blue: 0.62))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.14))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.4), lineWidth: 1))
                        }
                    }
                }
                .accessibilityLabel(title)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 3)
        .background {
            ZStack {
                LinearGradient(colors: [Color(red: 0.24, green: 0.24, blue: 0.25), Color(red: 0.05, green: 0.05, blue: 0.05)],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .white.opacity(0.05), location: 0.5),
                                       .init(color: .clear, location: 0.5)],
                               startPoint: .top, endPoint: .bottom)
                VStack { Color.white.opacity(0.25).frame(height: 1); Spacer() }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

extension Color {
    /// Цвет, который сам меняется вместе со светлой и тёмной темой телефона.
    static func dynamic(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

// MARK: Экраны системного вида внутри глянцевого оформления

/// Системный экран в листе с кнопкой «Готово».
struct SystemSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content.toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.fontWeight(.semibold) }
            }
        }
    }
}

/// Строка-ссылка с гелевым значком.
struct AquaLinkRow: View {
    var symbol: String
    var color: Color
    var title: String
    var value: String = ""
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AquaIcon(symbol: symbol, color: color, size: 30)
                Text(title).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text)
                Spacer()
                if !value.isEmpty { Text(value).font(Aqua.font(14)).foregroundStyle(Aqua.link) }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Aqua.line)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
