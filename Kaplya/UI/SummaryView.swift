import SwiftUI
import Charts

/// «Сводка» в духе Здоровья и Apple Card: главный график, основные моменты, категории.
struct SummaryView: View {
    @Environment(Store.self) private var store
    @State private var period: Span.Kind = .month
    @State private var selectedDate: Date?

    struct Bar: Identifiable {
        var id = UUID()
        var date: Date
        var category: String
        var amount: Double
    }

    var body: some View {
        // Всё на экране — за выбранный период: график, основные моменты, полезное, категории
        let span = Analytics.span(period, month: store.month, all: store.transactions)
        let stats = Analytics.stats(store.transactions, range: span.range)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if store.transactions.isEmpty {
                        ContentUnavailableView {
                            Label("Пока нет операций", systemImage: "chart.bar.xaxis")
                        } description: {
                            Text("Загрузите выписку Т-Банка или Сбера на вкладке «Счета» — здесь появятся траты по категориям и подсказки.")
                        } actions: {
                            Button("Посмотреть на демо-данных") { store.loadDemo() }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 60)
                    } else {
                        spendingCard(stats, span)
                        highlights(span)
                        tools(span)
                        categories(stats, span)
                    }
                    learn
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            // Выбранный на графике день из прошлого периода не должен оставаться выбранным
            .onChange(of: period) { selectedDate = nil }
            .onChange(of: store.month) { selectedDate = nil }
            .navigationTitle("Сводка")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Предыдущий месяц", systemImage: "chevron.left") { store.shiftMonth(-1) }
                            .disabled(!store.hasPreviousMonth)
                        Button("Следующий месяц", systemImage: "chevron.right") { store.shiftMonth(1) }
                            .disabled(!store.hasNextMonth)
                    } label: {
                        Label(Fmt.month(store.month), systemImage: "calendar")
                    }
                }
            }
        }
    }

    // MARK: Главная карточка

    private func spendingCard(_ stats: MonthStats, _ span: Span) -> some View {
        let bars = self.bars(stats, span)
        let total = bars.reduce(0) { $0 + $1.amount }
        let top = stats.byCategory.prefix(5).map(\.category)
        let selectedTotal = selectedDate.map { d in
            bars.filter { Store.calendar.isDate($0.date, equalTo: d, toGranularity: period == .year ? .month : .day) }
                .reduce(0) { $0 + $1.amount }
        }

        return VStack(alignment: .leading, spacing: 14) {
            Picker("Период", selection: $period) {
                ForEach(Span.Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDate == nil ? "ПОТРАЧЕНО" : "ЗА ВЫБРАННЫЙ ДЕНЬ")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(Fmt.money(Decimal(selectedTotal ?? total)))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                Text(subtitle(span)).font(.subheadline).foregroundStyle(.secondary)
            }

            Chart(bars) { bar in
                BarMark(x: .value("Дата", bar.date, unit: period == .year ? .month : .day),
                        y: .value("Сумма", bar.amount))
                    .foregroundStyle(by: .value("Категория", bar.category))
                    .cornerRadius(3)
                if let selectedDate {
                    RuleMark(x: .value("Выбрано", selectedDate, unit: period == .year ? .month : .day))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .zIndex(-1)
                }
            }
            .chartForegroundStyleScale(domain: top.map(\.title) + ["Другое"],
                                       range: top.map(\.systemColor) + [Color(.systemGray3)])
            .chartXSelection(value: $selectedDate)
            .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(v >= 1000 ? "\(Int(v / 1000)) тыс" : "\(Int(v))") }
                    }
                }
            }
            .frame(height: 220)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func subtitle(_ span: Span) -> String {
        let last = Store.calendar.date(byAdding: .day, value: -1, to: span.range.upperBound)!
        switch span.kind {
        case .week:
            return "\(span.range.lowerBound.formatted(.dateTime.day().month(.wide))) — \(last.formatted(.dateTime.day().month(.wide)))"
        case .month:
            return Fmt.month(store.month)
        case .year:
            return "\(Fmt.month(span.range.lowerBound)) — \(Fmt.month(store.month))"
        }
    }

    /// Столбики по дням (или месяцам), разбитые на 5 главных категорий и «Другое».
    private func bars(_ stats: MonthStats, _ span: Span) -> [Bar] {
        let cal = Store.calendar
        let top = Set(stats.byCategory.prefix(5).map(\.category))
        var sums: [String: Double] = [:]
        var dates: [String: Date] = [:]
        for t in store.transactions where t.category.isExpense && span.range.contains(t.date) {
            let bucket = period == .year ? Store.startOfMonth(t.date) : cal.startOfDay(for: t.date)
            let name = top.contains(t.category) ? t.category.title : "Другое"
            let key = "\(bucket.timeIntervalSince1970)|\(name)"
            sums[key, default: 0] += t.expenseValue.double
            dates[key] = bucket
        }
        return sums.compactMap { key, value in
            guard value > 0, let date = dates[key] else { return nil }
            return Bar(date: date, category: String(key.split(separator: "|")[1]), amount: value)
        }
    }

    // MARK: Основные моменты

    private func highlights(_ span: Span) -> some View {
        let insights = Analytics.insights(store.transactions, span: span, reserved: store.plannedReserve()).prefix(3)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Основные моменты").font(.title2.weight(.bold))
            ForEach(Array(insights)) { insight in
                NavigationLink {
                    InsightDetail(insight: insight)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(insight.tone == .warning ? "Внимание" : (insight.tone == .good ? "Хорошо" : "Совет"),
                                  systemImage: insight.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tint(insight))
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        Text(insight.title).font(.headline).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(insight.text).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tint(_ insight: Insight) -> Color {
        switch insight.tone {
        case .warning: return .orange
        case .tip:     return .blue
        case .good:    return .green
        }
    }

    // MARK: Полезное: итоги, вычет, кэшбэк

    private func tools(_ span: Span) -> some View {
        let year = store.taxYear(for: store.month)
        let refund = store.taxReport(year: year).refund
        let cashback = store.cashbackTotal(in: span.range)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Полезное").font(.title2.weight(.bold))
            NavigationLink { RecapView(month: store.month) } label: {
                toolCard("rosette", .purple, "Итоги \(Fmt.monthGenitiveOnly(store.month))",
                         Analytics.isCurrent(store.month)
                            ? "Месяц ещё идёт — итоги на сегодня: сколько отложили, на чём сэкономили"
                            : "Сколько отложили, на чём сэкономили — карточка, которой можно поделиться")
            }
            HStack(spacing: 10) {
                NavigationLink { TaxView(year: year) } label: {
                    toolCard("percent", .green, refund > 0 ? "Вернуть \(Fmt.money(refund))" : "Налоговый вычет",
                             "13% с лечения, учёбы, спорта", compact: true)
                }
                NavigationLink { CashbackView() } label: {
                    toolCard("arrow.uturn.backward", .orange,
                             cashback > 0 ? "+\(Fmt.money(cashback))" : "Кэшбэк",
                             "Кэшбэк и проценты \(span.forTitle)", compact: true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func toolCard(_ symbol: String, _ color: Color, _ title: String, _ text: String, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol).font(.headline).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            Text(title).font(.headline).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            Text(text).font(.subheadline).foregroundStyle(.secondary).lineLimit(compact ? 2 : 2)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: compact ? 130 : nil, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Азбука

    private var learn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Азбука финансов").font(.title2.weight(.bold))
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Lesson.all) { lesson in
                        NavigationLink { LessonView(lesson: lesson) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: lesson.symbol)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(lesson.color.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                Text(lesson.title).font(.headline).foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .frame(width: 160, height: 140, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Категории

    private func categories(_ stats: MonthStats, _ span: Span) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Категории").font(.title2.weight(.bold))
            VStack(spacing: 0) {
                ForEach(Array(stats.byCategory.prefix(8).enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        CategoryDetail(category: item.category, range: span.range, subtitle: subtitle(span))
                    } label: {
                        HStack(spacing: 12) {
                            CategoryBadge(category: item.category)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.category.title).foregroundStyle(.primary)
                                    Spacer()
                                    Text(Fmt.money(item.amount)).foregroundStyle(.secondary)
                                }
                                ProgressView(value: (item.amount / (stats.byCategory.first?.amount ?? 1)).double)
                                    .tint(item.category.systemColor)
                            }
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < min(stats.byCategory.count, 8) - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct InsightDetail: View {
    var insight: Insight

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: insight.symbol).font(.largeTitle).foregroundStyle(.tint)
                    Text(insight.title).font(.title2.weight(.bold))
                    Text(insight.text).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Основной момент")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CategoryDetail: View {
    @Environment(Store.self) private var store
    var category: Category
    /// Период из сводки; по умолчанию — выбранный месяц.
    var range: Range<Date>? = nil
    var subtitle: String? = nil

    var body: some View {
        let source = range.map { r in store.transactions.filter { r.contains($0.date) } } ?? store.monthTransactions
        let items = source.filter { $0.category == category }.sorted { $0.date > $1.date }
        let total = items.reduce(Decimal(0)) { $0 + $1.expenseValue }
        List {
            Section {
                HStack(spacing: 14) {
                    CategoryBadge(category: category, size: 52)
                    VStack(alignment: .leading) {
                        Text(Fmt.money(total)).font(.title.weight(.bold))
                        Text("\(items.count) \(Fmt.plural(items.count, "операция", "операции", "операций")) · \(subtitle ?? Fmt.month(store.month))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            Section("Операции") {
                ForEach(items) { t in
                    NavigationLink { TransactionDetail(id: t.id) } label: { TransactionRow(t: t) }
                }
            }
        }
        .navigationTitle(category.title)
    }
}
