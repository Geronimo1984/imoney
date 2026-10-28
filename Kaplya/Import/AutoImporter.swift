import Foundation
import Observation

/// Автозагрузка выписок: при каждом открытии приложения берёт самый новый файл из папки
/// и загружает его, если он ещё не загружался.
/// Папка по умолчанию — «На iPhone › iMoney › Выписки» (видна в «Файлах»), можно выбрать любую другую.
@Observable
final class AutoImporter {
    private static let enabledKey = "autoImportEnabled"
    private static let bookmarkKey = "autoImportBookmark"
    private static let lastKey = "autoImportLastFile"
    private static let lastDateKey = "autoImportLastDate"

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }
    /// Имя выбранной папки; nil — папка приложения по умолчанию.
    private(set) var customFolderName: String?
    private(set) var lastFile: String?
    private(set) var lastDate: Date?
    /// Почему не удалось сменить папку — показывается под кнопкой выбора.
    private(set) var folderError: String?

    @ObservationIgnored private var bookmark: Data?

    static let extensions: Set<String> = ["csv", "pdf", "txt"]

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.bool(forKey: Self.enabledKey)
        bookmark = defaults.data(forKey: Self.bookmarkKey)
        lastFile = defaults.string(forKey: Self.lastKey)
        lastDate = defaults.object(forKey: Self.lastDateKey) as? Date
        customFolderName = resolveBookmark().map(Self.displayName)
        Self.ensureDefaultFolder()
    }

    // MARK: Папка

    /// «На iPhone › iMoney › Выписки».
    static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Выписки", isDirectory: true)
    }

    static func ensureDefaultFolder() {
        try? FileManager.default.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
    }

    var folderTitle: String {
        customFolderName ?? "На iPhone › iMoney › Выписки"
    }

    /// Папка, выбранная в «Файлах»: запоминаем закладку, чтобы доступ сохранился после перезапуска.
    func choose(_ url: URL) {
        // Своя папка приложения — закладка не нужна, это просто папка по умолчанию
        if url.resolvingSymlinksInPath().path == Self.defaultFolder.resolvingSymlinksInPath().path {
            useDefaultFolder()
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        // Проверяем, что папку действительно можно прочитать, иначе молча осталась бы старая
        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            bookmark = data
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            customFolderName = Self.displayName(url)
            folderError = nil
            enabled = true
        } catch {
            folderError = "Не удалось открыть доступ к папке «\(url.lastPathComponent)». Выберите другую."
        }
    }

    /// Имя, как в «Файлах»: папка Documents приложения там называется «iMoney».
    private static func displayName(_ url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
    }

    func useDefaultFolder() {
        bookmark = nil
        customFolderName = nil
        folderError = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    private func resolveBookmark() -> URL? {
        guard let bookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData() {
            self.bookmark = fresh
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }

    // MARK: Проверка

    /// Загружает самый новый файл выписки, если он новый. Возвращает итог или nil, если загружать нечего.
    func check(store: Store) -> ImportOutcome? {
        guard enabled else { return nil }
        let folder = resolveBookmark() ?? Self.defaultFolder
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }

        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                         options: [.skipsHiddenFiles]) else { return nil }
        var files: [(URL, Date)] = []
        for url in items {
            // Файл в iCloud, который ещё не скачан на телефон: просим скачать, загрузим при следующем открытии
            if url.lastPathComponent.hasPrefix(".") && url.pathExtension == "icloud" {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard Self.extensions.contains(url.pathExtension.lowercased()) else { continue }
            let date = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            files.append((url, date))
        }
        guard let newest = files.max(by: { $0.1 < $1.1 }) else { return nil }

        let key = "\(newest.0.lastPathComponent)|\(Int(newest.1.timeIntervalSince1970))"
        guard key != UserDefaults.standard.string(forKey: Self.lastKey + "Key") else { return nil }

        let outcome = ImportOutcome.run([newest.0], store: store)
        UserDefaults.standard.set(key, forKey: Self.lastKey + "Key")
        lastFile = newest.0.lastPathComponent
        lastDate = Date()
        UserDefaults.standard.set(lastFile, forKey: Self.lastKey)
        UserDefaults.standard.set(lastDate, forKey: Self.lastDateKey)
        // Повтор той же выписки не показываем: если новых операций нет и ошибок нет — молча
        let added = outcome.records.reduce(0) { $0 + $1.added }
        return (added > 0 || !outcome.errors.isEmpty) ? outcome : nil
    }
}
