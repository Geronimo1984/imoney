import SwiftUI
import UniformTypeIdentifiers

/// Раздел «Автозагрузка» для системного оформления: переключатель, папка, последний файл.
struct AutoImportSection: View {
    @Environment(AutoImporter.self) private var auto

    var body: some View {
        @Bindable var auto = auto
        Section {
            Toggle(isOn: $auto.enabled) {
                Label("Загружать новые выписки", systemImage: "arrow.down.doc")
            }
            if auto.enabled {
                LabeledContent("Папка", value: auto.folderTitle)
                Button("Выбрать другую папку…") { FolderPicker.present { auto.choose($0) } }
                if let error = auto.folderError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                if auto.customFolderName != nil {
                    Button("Вернуть папку iMoney") { auto.useDefaultFolder() }
                }
                if let file = auto.lastFile, let date = auto.lastDate {
                    LabeledContent("Последний файл") {
                        Text("\(file)\n\(date.formatted(.dateTime.day().month(.wide).hour().minute()))")
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        } header: {
            Text("Автозагрузка")
        } footer: {
            Text("Сохраняйте выписки из банка в эту папку: «Поделиться» → «Сохранить в Файлы». При каждом открытии iMoney загрузит самый новый файл, если его ещё не было.")
        }
    }
}

/// То же для глянцевого оформления.
struct AquaAutoImportCard: View {
    @Environment(AutoImporter.self) private var auto

    var body: some View {
        @Bindable var auto = auto
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $auto.enabled) {
                Text("Загружать новые выписки").font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text)
            }
            .tint(Aqua.blue)
            .padding(12)
            if auto.enabled {
                Divider().overlay(Aqua.line)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Папка").font(Aqua.font(12)).foregroundStyle(Aqua.label)
                    Text(auto.folderTitle).font(Aqua.font(15, .bold)).foregroundStyle(Aqua.text)
                }
                .padding(12)
                Divider().overlay(Aqua.line)
                Button { FolderPicker.present { auto.choose($0) } } label: {
                    Text("Выбрать другую папку…").font(Aqua.font(15, .bold)).foregroundStyle(Aqua.link)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                if let error = auto.folderError {
                    Text(error).font(Aqua.font(12)).foregroundStyle(.red).padding(.horizontal, 12).padding(.bottom, 10)
                }
                if auto.customFolderName != nil {
                    Divider().overlay(Aqua.line)
                    Button { auto.useDefaultFolder() } label: {
                        Text("Вернуть папку iMoney").font(Aqua.font(15, .bold)).foregroundStyle(Aqua.link)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
                if let file = auto.lastFile {
                    Divider().overlay(Aqua.line)
                    Text("Последний файл: \(file)").font(Aqua.font(12)).foregroundStyle(Aqua.label).padding(12)
                }
            }
        }
        .groupCard()
    }
}

/// Выбор папки в «Файлах». Показывается напрямую через UIKit поверх верхнего экрана:
/// внутри SwiftUI-листа выборщик после выбора закрывался сам, в обход SwiftUI, —
/// лист «оставался открытым», кнопка переставала срабатывать, а на устройстве приложение иногда падало.
/// Не fileImporter: экран выше уже держит свой для выписок, а SwiftUI показывает только один из вложенных.
@MainActor
enum FolderPicker {
    /// Делегат выборщика слабый — держим его, пока окно открыто.
    private static var delegate: Delegate?

    static func present(onPick: @escaping (URL) -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let root = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?
            .windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.directoryURL = AutoImporter.defaultFolder
        let delegate = Delegate(onPick: onPick)
        picker.delegate = delegate
        Self.delegate = delegate
        top.present(picker, animated: true)
    }

    final class Delegate: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
            FolderPicker.delegate = nil
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            FolderPicker.delegate = nil
        }
    }
}
