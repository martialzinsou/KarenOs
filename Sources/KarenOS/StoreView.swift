import SwiftUI

struct StoreView: View {
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager

    @State private var query = ""
    @State private var results: [RemoteModel] = []
    @State private var curated: [RemoteModel] = []
    @State private var isSearching = false
    @State private var activeSearch: String?
    @State private var errorMessage: String?
    @State private var selectedDetail: RemoteModel?
    @State private var curatedLoaded = false

    private var shown: [RemoteModel] {
        guard let q = activeSearch, !q.isEmpty else { return curated }
        return results
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 14)]
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            if let error = errorMessage {
                MessageBar(text: error, isError: true)
            }

            if isSearching {
                Spacer()
                ProgressView("Recherche sur Hugging Face…")
                Spacer()
            } else if !curatedLoaded && activeSearch == nil {
                searchingPlaceholder
            } else if shown.isEmpty {
                emptyPlaceholder
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(shown) { model in
                            StoreCard(model: model)
                                .onTapGesture { selectedDetail = model }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Boutique")
        .sheet(item: $selectedDetail) { detail in
            StoreDetailSheet(model: detail)
        }
        .task(id: query) { await searchChanged() }
        .task { await loadCurated() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Rechercher un modèle GGUF (ex : qwen, phi)…", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.bar)
    }

    private var searchingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Chargement de la sélection…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("Aucun résultat")
                .font(.headline)
            Text("Essaie une autre recherche.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func searchChanged() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            activeSearch = nil
            errorMessage = nil
            return
        }
        isSearching = true
        activeSearch = trimmed
        do {
            results = try await HuggingFaceClient.search(trimmed)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    private func loadCurated() async {
        guard !curatedLoaded else { return }
        await withTaskGroup(of: RemoteModel?.self) { group in
            for id in HuggingFaceClient.curatedIDs {
                group.addTask {
                    try? await HuggingFaceClient.detail(id: id)
                }
            }
            for await result in group {
                if let model = result {
                    curated.append(model)
                }
            }
        }
        curated.sort { ($0.downloads ?? 0) > ($1.downloads ?? 0) }
        curatedLoaded = true
    }
}

private struct MessageBar: View {
    let text: String
    var isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(isError ? .orange : .secondary)
            Text(text)
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isError ? Color.orange.opacity(0.12) : Color.clear)
    }
}

struct StoreCard: View {
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager
    let model: RemoteModel

    private var installed: Bool { store.isInstalled(id: model.id) }
    private var isDownloading: Bool { store.activeInstalls.contains(model.id) }
    private var progress: Double { store.downloading[model.id] ?? 0 }
    private var defaultSize: Int64? { model.defaultFile?.size }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                Spacer()
                Text(model.prettyContext.isEmpty ? "" : "\(model.prettyContext) ctx")
                    .font(.caption)
                    .padding(4)
                    .background(Capsule().fill(.quaternary))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text("par \(model.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if model.downloads != nil {
                    Label("\(model.downloadCountText)", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let size = defaultSize {
                    Text(FileFormat.bytes(size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if installed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Installé")
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else if isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100)) %")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    installDefault()
                } label: {
                    Label("Installer", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.defaultFile == nil || engine.isInstallingEngine)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.06)))
    }

    private func installDefault() {
        guard let file = model.defaultFile else { return }
        Task {
            await store.download(model, file: file)
        }
    }
}

private extension EngineManager {
    var isInstallingEngine: Bool {
        if case .installingEngine = state { return true }
        return false
    }
}