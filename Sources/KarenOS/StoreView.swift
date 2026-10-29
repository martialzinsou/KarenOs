// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — StoreView.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Onglet « Boutique » : sélection de modèles et recherche Hugging Face.
//    Dépend. : SwiftUI
//  --------------------------------------------------------------------
//    Affiche la sélection (curatedIDs) et les résultats de recherche (délai
//    anti-rebond de 450 ms). Les StoreCard enrichissent les fiches (contexte,
//    taille, quantifications), détectent l'installation et lancent le
//    téléchargement, et ouvrent la fiche détail (StoreDetailSheet).
//  ====================================================================

import SwiftUI

/// Onglet « Boutique » : sélection de modèles et recherche Hugging Face.
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
        [GridItem(.adaptive(minimum: 268, maximum: 360), spacing: 14)]
    }

    private var resultTitle: String {
        if let activeSearch, !activeSearch.isEmpty {
            return "Résultats pour « \(activeSearch) »"
        }
        return "Sélection KarenOS"
    }

    private var showLoading: Bool {
        if isSearching && shown.isEmpty { return true }
        return !curatedLoaded && activeSearch == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "bag",
                title: "Boutique",
                subtitle: "Des modèles ouverts, téléchargés une fois, exécutés pour toujours hors ligne.",
                tint: KarenTheme.blue
            ) {
                HStack(spacing: 6) {
                    KarenPill(text: "Hugging Face", systemImage: "network", tint: KarenTheme.blue)
                    if curatedLoaded {
                        KarenPill(
                            text: "\(shown.count) modèle\(shown.count > 1 ? "s" : "")",
                            tint: .secondary
                        )
                    }
                }
            }

            searchArea

            if let error = errorMessage {
                MessageBar(text: error, isError: true)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            if showLoading {
                loadingState
            } else if shown.isEmpty {
                emptyState
            } else {
                resultsHeader
                modelGrid
            }
        }
        .sheet(item: $selectedDetail) { detail in
            StoreDetailSheet(model: detail)
        }
        .onChange(of: query) { _ in Task { await searchChanged() } }
        .onAppear { Task { await loadCurated() } }
    }

    // MARK: - Recherche

    private var searchArea: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            TextField("Rechercher un modèle GGUF (ex : qwen, phi, llama)…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
            }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Effacer la recherche")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    private var resultsHeader: some View {
        HStack(alignment: .center) {
            SectionLabel(resultTitle)
            Spacer()
            Text("Les fichiers sont téléchargés depuis Hugging Face, puis exécutés localement.")
                .font(.system(size: 9.5))
                .foregroundColor(Color.secondary.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    // MARK: - Grille

    private var modelGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(shown) { model in
                    StoreCard(model: model)
                        .onTapGesture { selectedDetail = model }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 9))
                Text("Les modèles restent sur votre Mac après le téléchargement.")
                    .font(.system(size: 9.5))
            }
            .foregroundColor(Color.secondary.opacity(0.7))
            .padding(.bottom, 20)
        }
    }

    // MARK: - États

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
            Text(isSearching ? "Recherche sur Hugging Face…" : "Chargement de la sélection…")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "Aucun modèle trouvé",
            message: activeSearch == nil
                ? "La sélection n'a pas pu être chargée. Vérifiez votre connexion puis réessayez."
                : "Essayez un autre nom de modèle ou une quantification différente.",
            tint: KarenTheme.blue,
            actionTitle: query.isEmpty ? "Actualiser la sélection" : "Effacer la recherche",
            action: {
                if query.isEmpty {
                    curatedLoaded = false
                    Task { await loadCurated() }
                } else {
                    query = ""
                }
            }
        )
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
                .font(.system(size: 10))
                .foregroundColor(isError ? KarenTheme.amber : Color.secondary)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isError ? KarenTheme.amber.opacity(0.08) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isError ? KarenTheme.amber.opacity(0.14) : Color.primary.opacity(0.06),
                    lineWidth: 0.8
                )
        )
    }
}

/// Carte d'un modèle dans la grille de la Boutique.
struct StoreCard: View {
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager
    let model: RemoteModel

    @State private var resolving = false
    @State private var live: RemoteModel?
    @State private var hovering = false

    private var displayed: RemoteModel { live ?? model }
    private var installed: Bool { store.isInstalled(id: model.id) }
    private var isDownloading: Bool { store.activeInstalls.contains(model.id) }
    private var progress: Double { store.downloading[model.id] ?? 0 }
    private var defaultSize: Int64? { displayed.defaultFile?.size }
    private var canInstall: Bool {
        displayed.defaultFile != nil || !displayed.ggufSiblings.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 8) {
                IconTile(symbol: "cpu", tint: KarenTheme.indigo, size: 38)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 4) {
                    if !displayed.prettyContext.isEmpty {
                        KarenPill(text: "\(displayed.prettyContext) ctx", systemImage: "text.alignleft", tint: KarenTheme.violet)
                    }
                    if !displayed.licenseLabel.isEmpty {
                        KarenPill(text: displayed.licenseLabel, tint: .secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayed.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("par \(displayed.author)")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                if displayed.downloads != nil {
                    Label(displayed.downloadCountText, systemImage: "arrow.down.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                if let size = defaultSize {
                    Label(FileFormat.bytes(size), systemImage: "internaldrive")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 1)

            statusArea

            if let error = store.downloadError[model.id] {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(KarenTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 194, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.90))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    hovering ? KarenTheme.indigo.opacity(0.24) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(
            color: .black.opacity(hovering ? 0.13 : 0.05),
            radius: hovering ? 16 : 9,
            x: 0,
            y: hovering ? 9 : 5
        )
        .offset(y: hovering ? -2 : 0)
        .animation(.easeOut(duration: 0.16), value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering = $0 }
        .help("Voir les versions disponibles pour \(displayed.displayName)")
        .onAppear { Task { await resolveIfNeeded() } }
    }

    @ViewBuilder
    private var statusArea: some View {
        if installed {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundColor(KarenTheme.mint)
                Text("Installé")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(KarenTheme.mint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(KarenTheme.mint.opacity(0.09))
            )
        } else if isDownloading {
            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .accentColor(KarenTheme.indigo)
                Text("Téléchargement · \(Int(progress * 100)) %")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        } else if resolving {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.mini)
                Text("Résolution des versions…")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        } else {
            Button {
                installDefault()
            } label: {
                Label("Installer", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(KarenPrimaryButtonStyle())
            .disabled(!canInstall || engine.isInstallingEngine)
        }
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
