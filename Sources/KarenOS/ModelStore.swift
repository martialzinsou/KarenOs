import Foundation
import SwiftUI

@MainActor
final class ModelStore: ObservableObject {
    @Published var installed: [LocalModel] = []
    @Published var downloading: [String: Double] = [:]
    @Published var activeInstalls: Set<String> = []
    @Published var downloadError: [String: String] = [:]

    init() {
        AppPaths.ensure()
        load()
    }

    func isInstalled(id: String) -> Bool {
        installed.contains { $0.id == id }
    }

    func installedModel(id: String) -> LocalModel? {
        installed.first { $0.id == id }
    }

    func download(_ remote: RemoteModel, file: RemoteModel.Sibling) async {
        let key = remote.id
        guard !activeInstalls.contains(key) else { return }
        guard let url = remote.downloadURL(for: file) else { return }

        if installed.contains(where: { $0.id == remote.id && $0.fileName == file.rfilename }) {
            return
        }

        let model = LocalModel(
            id: remote.id,
            displayName: remote.displayName,
            author: remote.author,
            fileName: file.rfilename,
            fileSize: file.size ?? 0,
            quant: remote.quantLabel(from: file),
            installedAt: Date()
        )

        activeInstalls.insert(key)
        downloading[key] = 0
        downloadError[key] = nil
        try? FileManager.default.createDirectory(at: model.directory, withIntermediateDirectories: true)

        do {
            try await DownloadManager.download(url: url, to: model.fileURL) { fraction in
                Task { @MainActor in
                    self.downloading[key] = fraction
                }
            }
            installed.append(model)
            save()
        } catch {
            downloadError[key] = error.localizedDescription
            #if DEBUG
            print("Échec téléchargement \(key) : \(error)")
            #endif
        }
        activeInstalls.remove(key)
        downloading[key] = nil
    }

    func remove(_ model: LocalModel) {
        try? FileManager.default.removeItem(at: model.directory)
        installed.removeAll { $0.id == model.id }
        save()
    }

    // MARK: - Persistance

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.registryURL) else { return }
        let decoded = (try? JSONDecoder().decode([LocalModel].self, from: data)) ?? []
        var seen = Set<String>()
        let deduped = decoded.filter { entry in
            let key = entry.id + "|" + entry.fileName
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        installed = deduped
    }

    private func save() {
        let data = (try? JSONEncoder().encode(installed)) ?? Data()
        try? data.write(to: AppPaths.registryURL)
    }
}

struct LocalModel: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let author: String
    let fileName: String
    var fileSize: Int64
    let quant: String
    let installedAt: Date

    private var modelDirName: String { id.replacingOccurrences(of: "/", with: "__") }
    var directory: URL { AppPaths.modelsDir.appendingPathComponent(modelDirName, isDirectory: true) }
    var fileURL: URL { directory.appendingPathComponent(fileName) }

    var existsOnDisk: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    var sizeLabel: String { FileFormat.bytes(fileSize) }
    var quantLabel: String { quant.isEmpty ? "gguf" : quant }

    var friendlyName: String {
        displayName
            .replacingOccurrences(of: "-GGUF", with: "")
            .replacingOccurrences(of: "-Instruct", with: "")
            .replacingOccurrences(of: "-instruct", with: "")
    }
}