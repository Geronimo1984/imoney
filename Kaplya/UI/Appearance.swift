import SwiftUI

/// Оформление приложения: системное (iOS) или глянцевое в духе Aqua / iOS 6. Выбор хранится на устройстве.
enum Design: String, CaseIterable, Identifiable {
    case system, aqua

    static let storageKey = "design"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системное"
        case .aqua:   return "Глянцевое"
        }
    }
}

/// Корень приложения: показывает выбранное оформление и принимает выписки из «Поделиться».
struct AppShell: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var phase
    @AppStorage(Design.storageKey) private var design = Design.system.rawValue
    @State private var auto = AutoImporter()
    /// Итог загрузки файла, открытого через «Поделиться» в приложении банка
    @State private var opened: ImportOutcome?
    @State private var onboarding = OnboardingView.shouldShow
    /// После переключения оформления остаёмся на экране с переключателем, а не прыгаем на первую вкладку.
    /// Ставится выбором до смены оформления, поэтому новое оформление сразу открывается на нужной вкладке.
    static var switched = false

    var body: some View {
        Group {
            if design == Design.aqua.rawValue {
                AquaRoot(startTab: AppShell.switched ? "imports" : nil)
            } else {
                RootView(startTab: AppShell.switched ? "accounts" : nil)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.35), value: design)
        // Оба оформления следуют светлой или тёмной теме телефона; -light и -dark — для скриншотов
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-light") ? .light
                              : (ProcessInfo.processInfo.arguments.contains("-dark") ? .dark : nil))
        .environment(auto)
        .onOpenURL { url in
            opened = ImportOutcome.run([url], store: store)
        }
        // Автозагрузка: при каждом возвращении в приложение проверяем папку с выписками
        .onChange(of: phase) { _, now in
            guard now == .active else { return }
            if opened == nil, let outcome = auto.check(store: store) {
                opened = outcome
            }
            Reminders.reschedule(store)
            WidgetBridge.update(store)
        }
        // После любых изменений данных — новое расписание напоминаний и свежий виджет
        .onChange(of: store.changes) {
            Reminders.reschedule(store)
            WidgetBridge.update(store)
        }
        .onAppear {
            // Флаг для проверки импорта в симуляторе: -import=/путь/к/выписке
            if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-import=") }) {
                opened = ImportOutcome.run([URL(fileURLWithPath: String(arg.dropFirst(8)))], store: store)
            } else if let outcome = auto.check(store: store) {
                opened = outcome
            }
        }
        .fullScreenCover(isPresented: $onboarding) { OnboardingView() }
        .sheet(item: $opened) { outcome in
            ImportSummarySheet(outcome: outcome)
                .presentationDetents([.medium])
        }
    }
}

/// Выбор оформления как «Оформление» в Настройках → Экран и яркость: два мини-экрана и кружок под каждым.
struct AppearancePicker: View {
    @AppStorage(Design.storageKey) private var design = Design.system.rawValue

    var body: some View {
        HStack(spacing: 40) {
            ForEach(Design.allCases) { option in
                let selected = design == option.rawValue
                Button {
                    AppShell.switched = true
                    design = option.rawValue
                } label: {
                    VStack(spacing: 10) {
                        DesignThumbnail(design: option)
                            .frame(width: 74, height: 150)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selected ? Color.accentColor : Color(.separator), lineWidth: selected ? 2.5 : 1))
                        Text(option.title).font(.subheadline).foregroundStyle(.primary)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(selected ? Color.accentColor : Color(.tertiaryLabel))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Оформление: \(option.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .sensoryFeedback(.selection, trigger: design)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Мини-экран оформления.
struct DesignThumbnail: View {
    var design: Design

    var body: some View {
        ZStack(alignment: .top) {
            switch design {
            case .system:
                Color(.systemGroupedBackground)
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.8)).frame(width: 34, height: 6)
                    RoundedRectangle(cornerRadius: 6).fill(Color(.secondarySystemGroupedBackground))
                        .frame(height: 46)
                        .overlay(alignment: .bottomLeading) {
                            HStack(alignment: .bottom, spacing: 3) {
                                ForEach([14, 22, 10, 26, 16, 20], id: \.self) { h in
                                    RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(width: 4, height: CGFloat(h))
                                }
                            }
                            .padding(6)
                        }
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4).fill(Color(.secondarySystemGroupedBackground)).frame(height: 14)
                    }
                    Spacer()
                }
                .padding(.horizontal, 7)
                .padding(.top, 14)
            case .aqua:
                Pinstripes()
                VStack(spacing: 6) {
                    LinearGradient(colors: [Aqua.barTop, Aqua.barBottom], startPoint: .top, endPoint: .bottom)
                        .frame(height: 14)
                    ZStack {
                        Circle()
                            .trim(from: 0, to: 0.3).stroke(Color.gray, lineWidth: 14)
                        Circle()
                            .trim(from: 0.3, to: 0.6).stroke(Color.green, lineWidth: 14)
                        Circle()
                            .trim(from: 0.6, to: 1).stroke(Color.orange, lineWidth: 14)
                        Circle().stroke(LinearGradient(colors: [.white.opacity(0.8), .clear], startPoint: .top, endPoint: .center), lineWidth: 14)
                    }
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                    .padding(.top, 4)
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3).fill(Aqua.card)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Aqua.line, lineWidth: 0.5))
                            .frame(height: 13)
                            .padding(.horizontal, 6)
                    }
                    Spacer()
                    LinearGradient(colors: [Color(white: 0.25), .black], startPoint: .top, endPoint: .bottom).frame(height: 16)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}
