import SwiftUI
import Charts

/// Корень глянцевого варианта: раскладка первого варианта (Обзор, Операции, Советы, Выписки).
struct AquaRoot: View {
    @State private var tab: String

    init(startTab: String? = nil) {
        let arg = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-tab=") }
        _tab = State(initialValue: startTab ?? arg.map { String($0.dropFirst(5)) } ?? "overview")
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case "operations": AquaOperations()
                case "plan":       AquaPlan()
                case "insights":   AquaInsights()
                case "imports":    AquaImports()
                default:           AquaOverview()
                }
            }
            .frame(maxHeight: .infinity)
            AquaTabBar(tab: $tab, items: [
                ("overview", "Обзор", "chart.pie.fill"),
                ("operations", "Операции", "list.bullet.rectangle.fill"),
                ("plan", "План", "list.bullet.clipboard.fill"),
                ("insights", "Советы", "lightbulb.fill"),
                ("imports", "Выписки", "tray.and.arrow.down.fill")
            ])
        }
        .background(Pinstripes())
    }
}

// MARK: Обзор

struct AquaOverview: View {
    @Environment(Store.self) private var store
    @State private var opened: Category?

    var body: some View {
        let stats = Analytics.stats(store.transactions, month: store.month)
        NavigationStack {
            VStack(spacing: 0) {
                AquaNavBar(title: "iMoney") {
                    AquaBarButton(symbol: "chevron.left", label: "Предыдущий месяц") { store.shiftMonth(-1) }
                        .disabled(!store.hasPreviousMonth)
                } trailing: {
                    AquaBarButton(symbol: "chevron.right", label: "Следующий месяц") { store.shiftMonth(1) }
                        .disabled(!store.hasNextMonth)
                }
                ScrollView {
                    VStack(spacing: 18) {
                        Text(Fmt.month(store.month)).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.label).embossed()
                        HStack(spacing: 8) {
                            tile("Доходы", stats.income, Aqua.positive)
                            tile("Расходы", stats.expenses, Aqua.negative)
                            tile("Остаток", stats.balance, Aqua.link)
                        }
                        if stats.expenses > 0 {
                            AquaWheel(totals: stats.byCategory, total: stats.expenses) { opened = $0 }
                                .padding(.horizontal, 8)
                            AquaSection(title: "Категории") {
                                let colors = Category.distinctColors(stats.byCategory.prefix(7).map(\.category))
                                VStack(spacing: 0) {
                                    ForEach(Array(stats.byCategory.prefix(6).enumerated()), id: \.element.id) { index, item in
                                        Button { opened = item.category } label: {
                                            HStack(spacing: 10) {
                                                AquaIcon(symbol: item.category.symbol, color: colors[item.category] ?? item.category.systemColor, size: 30)
                                                VStack(alignment: .leading, spacing: 5) {
                                                    HStack {
                                                        Text(item.category.title).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text)
                                                        Spacer()
                                                        Text(Fmt.money(item.amount)).font(Aqua.font(15)).foregroundStyle(Aqua.link)
                                                    }
                                                    AquaProgress(value: (item.amount / (stats.byCategory.first?.amount ?? 1)).double,
                                                                 color: colors[item.category] ?? item.category.systemColor, height: 9)
                                                }
                                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Aqua.line)
                                            }
                                            .padding(.horizontal, 12).padding(.vertical, 9)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        if index < min(stats.byCategory.count, 6) - 1 { Divider().overlay(Aqua.line) }
                                    }
                                }
                                .groupCard()
                            }
                        }
                        if let f = store.forecast() {
                            AquaSection(title: "Прогноз на месяц") {
                                VStack(alignment: .leading, spacing: 10) {
                                    AquaProgress(value: stats.income > 0 ? (f.spent / stats.income).double : 0,
                                                 color: f.projected > stats.income ? .orange : Aqua.blue,
                                                 marker: stats.income > 0 ? min((f.projected / stats.income).double, 1) : nil, height: 14)
                                    HStack {
                                        labelled("Потрачено", Fmt.money(f.spent))
                                        Spacer()
                                        labelled("К концу месяца", "≈ " + Fmt.money(f.projected), trailing: true)
                                    }
                                    Text("Можно тратить \(Fmt.money(f.perDayLeft)) в день, чтобы уложиться в доход.")
                                        .font(Aqua.font(13)).foregroundStyle(Aqua.label)
                                }
                                .padding(14)
                                .groupCard()
                            }
                        }
                        if stats.income > 0 {
                            AquaSection(title: "Правило 50 / 30 / 20") {
                                VStack(spacing: 12) {
                                    rule(.needs, stats.byGroup[.needs] ?? 0, stats.income, Aqua.blue)
                                    rule(.wants, stats.byGroup[.wants] ?? 0, stats.income, Color(red: 0.85, green: 0.30, blue: 0.60))
                                    rule(.savings, (stats.byGroup[.savings] ?? 0) + max(stats.balance, 0), stats.income, Color(red: 0.20, green: 0.70, blue: 0.30))
                                }
                                .padding(14)
                                .groupCard()
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 14)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $opened) { AquaCategoryPage(category: $0) }
        }
    }

    private func tile(_ title: String, _ value: Decimal, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title).font(Aqua.font(12, .bold)).foregroundStyle(Aqua.label)
            Text(Fmt.compact(value)).font(Aqua.font(18, .bold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .groupCard()
    }

    private func labelled(_ title: String, _ value: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(title).font(Aqua.font(11)).foregroundStyle(Aqua.label)
            Text(value).font(Aqua.font(17, .bold)).foregroundStyle(Aqua.text)
        }
    }

    private func rule(_ group: SpendGroup, _ amount: Decimal, _ income: Decimal, _ color: Color) -> some View {
        let share = (amount / income).double
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(group.title).font(Aqua.font(14, .bold)).foregroundStyle(Aqua.text)
                Spacer()
                Text("\(Int((share * 100).rounded()))% из \(Int(group.target * 100))%").font(Aqua.font(13)).foregroundStyle(Aqua.label)
            }
            AquaProgress(value: share, color: color, marker: group.target, height: 11)
        }
    }
}

// MARK: Колесо категорий из гелевых «леденцов»

struct WheelWedge: Shape {
    var start: Angle
    var end: Angle
    var innerRatio: CGFloat = 0.42
    var gap: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rOut = min(rect.width, rect.height) / 2
        let rIn = rOut * innerRatio
        let sweep = end.radians - start.radians
        var r = min(12, (rOut - rIn) * 0.3)
        while (r > 1) && (2 * asin(min(1, Double((gap / 2 + r) / (rIn + r)))) > sweep * 0.8) { r -= 1 }
        // Острый сегмент, уменьшенный на r, раздуваем обратно круглой кистью — углы скругляются ровно
        let ro = rOut - r, ri = rIn + r, h = gap / 2 + r
        guard ro > ri, h < ri else { return Path() }
        let a0o = start.radians + asin(Double(h / ro)), a1o = end.radians - asin(Double(h / ro))
        let a0i = start.radians + asin(Double(h / ri)), a1i = end.radians - asin(Double(h / ri))
        guard a1o > a0o, a1i > a0i else { return Path() }
        var core = Path()
        core.addArc(center: c, radius: ro, startAngle: .radians(a0o), endAngle: .radians(a1o), clockwise: false)
        core.addArc(center: c, radius: ri, startAngle: .radians(a1i), endAngle: .radians(a0i), clockwise: true)
        core.closeSubpath()
        return core.union(core.strokedPath(StrokeStyle(lineWidth: r * 2, lineCap: .round, lineJoin: .round)))
    }
}

struct AquaWheel: View {
    var totals: [CategoryTotal]
    var total: Decimal
    var onOpen: (Category) -> Void
    @State private var selected: Category?
    /// При появлении колесо докручивается на место, как барабан в iOS 6
    @State private var spun = false

    var body: some View {
        let top = Array(totals.prefix(7))
        let colors = Category.distinctColors(top.map(\.category))
        let raw = top.map { max(($0.amount / total).double * 360, 14) }
        let scale = 360 / raw.reduce(0, +)
        let starts = raw.indices.map { i in -90 + raw[..<i].reduce(0, +) * scale }
        let current = top.first { $0.category == selected }

        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let rOut = size / 2, rIn = rOut * 0.42
            ZStack {
                ForEach(Array(top.enumerated()), id: \.element.id) { i, item in
                    let a0 = Angle.degrees(starts[i]), a1 = Angle.degrees(starts[i] + raw[i] * scale)
                    let mid = (a0.radians + a1.radians) / 2
                    let isOn = item.category == selected
                    let wedge = WheelWedge(start: a0, end: a1)
                    Button {
                        Motion.animate(.spring(response: 0.3, dampingFraction: 0.6)) {
                            if isOn { onOpen(item.category) } else { selected = item.category }
                        }
                    } label: {
                        ZStack {
                            AquaGel(shape: wedge, color: colors[item.category] ?? item.category.systemColor)
                            VStack(spacing: 2) {
                                Image(systemName: item.category.symbol).font(.system(size: 18, weight: .bold))
                                if raw[i] * scale >= 30 {
                                    Text(Fmt.percent(item.amount, of: total)).font(Aqua.font(14, .bold))
                                }
                            }
                            .onBar()
                            .position(x: size / 2 + (rIn + rOut) / 2 * CGFloat(cos(mid)),
                                      y: size / 2 + (rIn + rOut) / 2 * CGFloat(sin(mid)))
                        }
                        .frame(width: size, height: size)
                        .contentShape(wedge)
                    }
                    .buttonStyle(.plain)
                    .offset(x: isOn ? 7 * CGFloat(cos(mid)) : 0, y: isOn ? 7 * CGFloat(sin(mid)) : 0)
                    .accessibilityLabel(item.category.title)
                }
                // Каждый сектор размером с колесо, поэтому все крутятся вокруг общего центра
                .rotationEffect(.degrees(spun ? 0 : -140))
                .scaleEffect(spun ? 1 : 0.75)
                .opacity(spun ? 1 : 0)
                // Хромированная середина
                VStack(spacing: 2) {
                    Text(current?.category.title ?? "Расходы").font(Aqua.font(12, .bold)).foregroundStyle(Aqua.label)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(Fmt.compact(current?.amount ?? total)).font(Aqua.font(22, .bold)).foregroundStyle(Aqua.text)
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(current.map { Fmt.percent($0.amount, of: total) + " · ещё раз — подробнее" } ?? "нажмите на сектор")
                        .font(Aqua.font(10)).foregroundStyle(Aqua.label)
                }
                .embossed()
                .padding(12)
                .frame(width: rIn * 2 - 10, height: rIn * 2 - 10)
                .background(AquaWhite(shape: Circle()))
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear {
            guard !spun else { return }
            Motion.animate(.spring(response: 0.9, dampingFraction: 0.68)) { spun = true }
        }
    }
}

/// Операции одной категории.
struct AquaCategoryPage: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var category: Category

    var body: some View {
        let items = store.monthTransactions.filter { $0.category == category }.sorted { $0.date > $1.date }
        VStack(spacing: 0) {
            AquaNavBar(title: category.title) {
                AquaBackButton(title: "Обзор") { dismiss() }
            } trailing: { EmptyView() }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, t in
                        NavigationLink { AquaTransactionPage(id: t.id, back: category.title) } label: { AquaRow(t: t) }
                            .buttonStyle(.plain)
                        if index < items.count - 1 { Divider().overlay(Aqua.line) }
                    }
                }
                .groupCard()
                .padding(10)
            }
        }
        .background(Pinstripes())
        .toolbar(.hidden, for: .navigationBar)
    }
}
