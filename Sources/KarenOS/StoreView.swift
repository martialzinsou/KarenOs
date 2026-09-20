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
        try? await Task.sleep(nanoseconds: 450_000_000)
        if Task.isCancelled { return }

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
            let found = try await HuggingFaceClient.search(trimmed, limit: 12)
            let enriched = await enrich(found)
            results = enriched.filter { !($0.gated?.isGated ?? false) && !$0.ggufSiblings.isEmpty }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    private func enrich(_ list: [RemoteModel]) async -> [RemoteModel] {
        await withTaskGroup(of: RemoteModel?.self) { group in
            for model in list {
                group.addTask {
                    try? await HuggingFaceClient.detail(id: model.id)
                }
            }
            var enriched: [RemoteModel] = []
            for await result in group {
                if let model = result {
                    enriched.append(model)
                }
            }
            return enriched
        }
    }

    private func loadCurated() async {
        guard !curatedLoaded else { return }
        let fetched = await enrich(HuggingFaceClient.curatedIDs.map { id in
            RemoteModel(id: id, downloads: 0, likes: nil, gated: nil, cardData: nil, gguf: nil, siblings: nil)
        })
        curated = fetched.filter { !($0.gated?.isGated ?? false) }
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

    @State private var resolving = false
    @State private var live: RemoteModel?

    private var displayed: RemoteModel { live ?? model }
    private var installed: Bool { store.isInstalled(id: model.id) }
    private var isDownloading: Bool { store.activeInstalls.contains(model.id) }
    private var progress: Double { store.downloading[model.id] ?? 0 }
    private var defaultSize: Int64? { displayed.defaultFile?.size }
    private var canInstall: Bool {
        displayed.defaultFile != nil || !displayed.ggufSiblings.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                Spacer()
                Text(displayed.prettyContext.isEmpty ? "" : "\(displayed.prettyContext) ctx")
                    .font(.caption)
                    .padding(4)
                    .background(Capsule().fill(.quaternary))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayed.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text("par \(displayed.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if displayed.downloads != nil {
                    Label("\(displayed.downloadCountText)", systemImage: "arrow.down.circle")
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
            } else if resolving {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Résolution…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    installDefault()
                } label: {
                    Label("Installer", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canInstall || engine.isInstallingEngine)
            }

            if let error = store.downloadError[model.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.06)))
        .task { await resolveIfNeeded() }
    }

    private func installDefault() {
        if let file = displayed.defaultFile ?? displayed.ggufSiblings.first {
            Task {
                await store.download(model, file: file)
            }
        } else {
            resolving = true
            Task {
                await resolveIfNeeded(force: true)
                resolving = false
            }
        }
    }

    private func resolveIfNeeded(force: Bool = false) async {
        guard force || displayed.ggufSiblings.isEmpty else { return }
        guard live == nil else { return }
        do {
            let detail = try await HuggingFaceClient.detail(id: model.id)
            if detail.gated?.isGated != true {
                await MainActor.run { live = detail }
            }
        } catch {
            await MainActor.run { }
        }
    }
}

private extension EngineManager {
    var isInstallingEngine: Bool {
        if case .installingEngine = state { return true }
        return false
    }
}