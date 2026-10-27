import WidgetKit
import SwiftUI

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .placeholder)
        // Приложение само обновляет виджет после изменений; раз в несколько часов — на всякий случай
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(4 * 3600))))
    }
}

private let ringColors: [Color] = [Color(red: 0.98, green: 0.07, blue: 0.31), Color(red: 0.6, green: 0.98, blue: 0.0), Color(red: 0.0, green: 0.85, blue: 0.95)]

/// Кольца 50/30/20, как в Активности.
struct Rings: View {
    var values: [Double]
    var width: CGFloat

    var body: some View {
        ZStack {
            ForEach(Array(values.prefix(3).enumerated()), id: \.offset) { i, v in
                let inset = CGFloat(i) * (width + 2)
                Circle().stroke(ringColors[i].opacity(0.25), lineWidth: width).padding(inset + width / 2)
                Circle().trim(from: 0, to: min(max(v, 0.001), 1))
                    .stroke(ringColors[i], style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset + width / 2)
            }
        }
    }
}

// MARK: «Можно тратить сегодня»

struct SpendView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryInline:
            Text("Сегодня можно \(WidgetSnapshot.money(s.perDay))")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Можно тратить").font(.caption2).foregroundStyle(.secondary)
                Text(WidgetSnapshot.money(s.perDay)).font(.headline)
                Text("ещё \(s.daysLeft) дн. до конца месяца").font(.caption2)
            }
        case .systemMedium:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Можно тратить сегодня").font(.caption).foregroundStyle(.secondary)
                    Text(WidgetSnapshot.money(s.perDay)).font(.system(size: 30, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text("Потрачено \(WidgetSnapshot.money(s.spent)) из \(WidgetSnapshot.money(s.income))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    if let title = s.nextPaymentTitle, let amount = s.nextPaymentAmount, let date = s.nextPaymentDate {
                        Label("\(title) · \(WidgetSnapshot.money(amount)) · \(date.formatted(.dateTime.day().month(.abbreviated)))",
                              systemImage: "calendar")
                            .font(.caption2).foregroundStyle(.orange).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Rings(values: s.rings, width: 9).frame(width: 96, height: 96)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "creditcard.fill").foregroundStyle(.blue)
                Spacer(minLength: 0)
                Text("Можно тратить").font(.caption).foregroundStyle(.secondary)
                Text(WidgetSnapshot.money(s.perDay)).font(.system(size: 26, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text("ещё \(s.daysLeft) дн.").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "spend", provider: SnapshotProvider()) { entry in
            SpendView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Можно тратить")
        .description("Сколько можно тратить в день, чтобы уложиться в доход.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Кольца 50/30/20

struct RingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "rings", provider: SnapshotProvider()) { entry in
            Rings(values: entry.snapshot.rings, width: 5)
                .padding(2)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Кольца бюджета")
        .description("Обязательное, желания и накопления по правилу 50/30/20.")
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

@main
struct KaplyaWidgets: WidgetBundle {
    var body: some Widget {
        SpendWidget()
        RingsWidget()
    }
}
