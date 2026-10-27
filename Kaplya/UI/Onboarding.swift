import SwiftUI
import UniformTypeIdentifiers

/// Обучение при первом запуске — как экраны «Добро пожаловать» в приложениях Apple:
/// крупный заголовок, список возможностей со значками, синяя кнопка внизу.
struct OnboardingView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Design.storageKey) private var design = Design.system.rawValue
    @AppStorage(Reminders.enabledKey) private var reminders = false
    @State private var page = 0
    @State private var picking = false
    @State private var outcome: ImportOutcome?

    var body: some View {
        TabView(selection: $page) {
            welcome.tag(0)
            features.tag(1)
            statements.tag(2)
            appearance.tag(3)
            start.tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut, value: page)
        .interactiveDismissDisabled()
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .pdf, .plainText, .text],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            outcome = ImportOutcome.run(urls, store: store)
        }
    }

    // MARK: Страницы

    private var welcome: some View {
        Page(button: "Продолжить", next: next) {
            VStack(spacing: 18) {
                Image("Onboarding").resizable().scaledToFit().frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                Text("Добро пожаловать\nв iMoney").font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
                Text("Все деньги из всех банков — в одном месте. Понятно, куда уходят, и что с этим делать.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.top, 40)
        }
    }

    private var features: some View {
        Page(title: "Что умеет iMoney", button: "Продолжить", next: next) {
            VStack(alignment: .leading, spacing: 22) {
                Feature(symbol: "building.columns.fill", color: .blue, title: "Все банки вместе",
                        text: "Т-Банк и Сбер в одной картине, без двойного счёта переводов между своими картами.")
                Feature(symbol: "list.bullet.clipboard.fill", color: .orange, title: "План на месяц",
                        text: "Лимиты, регулярные платежи, кредиты, накопления и цели — и сколько можно тратить сегодня.")
                Feature(symbol: "creditcard.fill", color: .red, title: "Кредиты под контролем",
                        text: "Когда закроется каждый долг, сколько уйдёт на проценты и как погасить быстрее.")
                Feature(symbol: "percent", color: .green, title: "Деньги назад",
                        text: "Налоговый вычет 13% и кэшбэк: какой картой платить, чтобы не терять.")
            }
        }
    }

    private var statements: some View {
        Page(title: "Откуда берутся данные", button: "Продолжить", next: next) {
            VStack(alignment: .leading, spacing: 22) {
                Feature(symbol: "doc.richtext.fill", color: .yellow, title: "Выписка из банка",
                        text: "Т-Банк: «Справка о движении средств» (PDF) или CSV. Сбер: «Выписка по счёту» (PDF).")
                Feature(symbol: "square.and.arrow.up.fill", color: .blue, title: "«Поделиться» → iMoney",
                        text: "Откройте выписку в приложении банка и отправьте её в iMoney. Повторная загрузка не создаёт дублей.")
                Feature(symbol: "folder.fill", color: .teal, title: "Или папка в «Файлах»",
                        text: "Сохраняйте выписки в «На iPhone › iMoney › Выписки» — новые загрузятся сами. Включается в «Счетах».")
                Feature(symbol: "lock.fill", color: .gray, title: "Только на этом iPhone",
                        text: "Данные никуда не отправляются: ни на сервер, ни разработчику.")
            }
        }
    }

    private var appearance: some View {
        Page(title: "Оформление", subtitle: "Можно поменять в любой момент в «Счетах».", button: "Продолжить", next: next) {
            AppearancePicker().padding(.top, 20)
        }
    }

    private var start: some View {
        Page(title: "Всё готово", subtitle: outcomeText, button: buttonTitle, next: finish) {
            VStack(spacing: 12) {
                Toggle(isOn: Binding(get: { reminders }, set: { on in
                    if on { Task { reminders = await Reminders.requestPermission() } } else { reminders = false }
                })) {
                    Label("Напоминать о платежах", systemImage: "bell.badge.fill")
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button { picking = true } label: {
                    Label("Загрузить выписку", systemImage: "tray.and.arrow.down.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                if store.transactions.isEmpty {
                    Button { store.loadDemo(); finish() } label: {
                        Text("Посмотреть на демо-данных").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless).controlSize(.large)
                }
            }
            .padding(.top, 20)
        }
    }

    private var outcomeText: String {
        guard let outcome else { return "Загрузите первую выписку — или начните с демо-данных, чтобы осмотреться." }
        let added = outcome.records.reduce(0) { $0 + $1.added }
        if added > 0 { return "Загружено \(added) \(Fmt.plural(added, "операция", "операции", "операций")). Можно начинать." }
        return outcome.errors.first?.1 ?? "Новых операций нет."
    }

    private var buttonTitle: String { store.transactions.isEmpty ? "Начать без выписки" : "Начать" }

    private func next() { withAnimation { page += 1 } }

    private func finish() {
        UserDefaults.standard.set(true, forKey: OnboardingView.doneKey)
        dismiss()
    }

    static let doneKey = "onboardingDone"

    /// Показывать при первом запуске; -demo (тесты, скриншоты) — не показывать, -onboarding — показать всегда.
    static var shouldShow: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-onboarding") { return true }
        if args.contains("-demo") { return false }
        return !UserDefaults.standard.bool(forKey: doneKey)
    }
}

/// Страница: заголовок, содержимое, кнопка внизу.
private struct Page<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var button: String
    var next: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let title {
                        Text(title).font(.largeTitle.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                            .padding(.top, 50)
                    }
                    if let subtitle {
                        Text(subtitle).font(.body).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                    }
                    content.padding(.top, title == nil ? 0 : 20)
                }
                .padding(.horizontal, 28)
            }
            Button(action: next) {
                Text(button).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct Feature: View {
    var symbol: String
    var color: Color
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title).foregroundStyle(color).frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
