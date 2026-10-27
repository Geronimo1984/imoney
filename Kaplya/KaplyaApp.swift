import SwiftUI

@main
struct KaplyaApp: App {
    @State private var store = Store(demo: ProcessInfo.processInfo.arguments.contains("-demo"))

    init() {
        // Флаг для скриншотов и тестов: -design=system|aqua
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-design=") }),
           let design = Design(rawValue: String(arg.dropFirst(8))) {
            UserDefaults.standard.set(design.rawValue, forKey: Design.storageKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(store)
        }
    }
}
