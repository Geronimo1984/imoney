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
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { auto.choose(url) }
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
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { auto.choose(url) }
        }
    }
}
