import Foundation

/// Итог загрузки одного или нескольких файлов.
struct ImportOutcome: Identifiable {
    var id = UUID()
    var records: [ImportRecord] = []
    var errors: [(String, String)] = []

    static func run(_ urls: [URL], store: Store) -> ImportOutcome {
        var outcome = ImportOutcome()
        for url in urls {
            do {
                outcome.records.append(try store.importStatement(at: url))
            } catch {
                outcome.errors.append((url.lastPathComponent, error.localizedDescription))
            }
        }
        return outcome
    }
}
