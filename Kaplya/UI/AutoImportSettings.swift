import SwiftUI
import UniformTypeIdentifiers

/// Раздел «Автозагрузка» для системного оформления: переключатель, папка, последний файл.
struct AutoImportSection: View {
    @Environment(AutoImporter.self) private var auto
    @State private var picking = false

    var body: some View {
        @Bindable var auto = auto
        Section {
            Toggle(isOn: $auto.enabled) {
                Label("Загружать новые выписки", systemImage: "arrow.down.doc")
            }
            if auto.enabled {
                LabeledContent("Папка", value: auto.folderTitle)
                Button("Выбрать другую папку…") { picking = true }
                    // Лист на самой кнопке: повешенный на Section внутри List не открывается
                    .sheet(isPresented: $picking) {
                        FolderPicker { auto.choose($0) }.ignoresSafeArea()
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
    @State private var picking = false

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
                Button { picking = true } label: {
                    Text("Выбрать другую папку…").font(Aqua.font(15, .bold)).foregroundStyle(Aqua.link)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
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
        .sheet(isPresented: $picking) {
            FolderPicker { auto.choose($0) }.ignoresSafeArea()
        }
    }
}

/// Выбор папки в «Файлах». Не fileImporter: экран выше уже держит свой для выписок,
/// а SwiftUI показывает только один из вложенных — кнопка выбора папки молча не срабатывала.
struct FolderPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.directoryURL = AutoImporter.defaultFolder
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
