// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — StoreDetailSheet.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Fiche détail d'un modèle de la Boutique : versions et installation.
//    Dépend. : SwiftUI
//  --------------------------------------------------------------------
//    Présente les métadonnées du modèle (téléchargements, contexte, taille
//    totale), la liste des fichiers GGUF avec sélection de la quantification,
//    et le bouton Installer avec progression. Résout les détails manquants
//    via l'API Hugging Face au besoin.
//  ====================================================================

import SwiftUI

/// Fiche détaillée d'un modèle : statistiques, versions GGUF et installation.
    ///
    /// Ouverte depuis une `StoreCard`, elle présente les métadonnées, la
    /// liste des fichiers de quantification (sélection de la version à
    /// télécharger) et le bouton Installer avec progression. Elle complète
    /// les données manquantes via l'API (`live`) si la carte n'était pas
    /// résolue.
    struct StoreDetailSheet: View {
    let model: RemoteModel

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ModelStore

    @State private var selectedFile: RemoteModel.Sibling?
    @State private var errorMessage: String?
    @State private var live: RemoteModel?

    private var displayed: RemoteModel { live ?? model }
    private var installed: Bool { store.isInstalled(id: model.id) }
    private var isDownloading: Bool { store.activeInstalls.contains(model.id) }
    private var progress: Double { store.downloading[model.id] ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: "cpu")
                    .font(.system(size: 28))
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayed.displayName)
                        .font(.title2).bold()
                    Text("par \(displayed.author)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(displayed.licenseLabel)
                    .font(.caption)
                    .padding(5)
                    .background(Capsule().fill(.quaternary))
            }

            HStack(spacing: 16) {
                statItem(value: "\(displayed.downloadCountText)", label: "téléchargements")
                statItem(value: displayed.prettyContext, label: "contexte (tokens)")
                if let total = displayed.totalSize {
                    statItem(value: FileFormat.bytes(total), label: "taille totale")
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            if displayed.ggufSiblings.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Chargement des versions disponibles…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Version à télécharger")
                        .font(.headline)
                    fileList
                }
            }

            if let error = store.downloadError[model.id] ?? errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Button("Fermer") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                installButton
            }
        }
        .padding(20)
        .frame(width: 480, height: 540)
        .onAppear {
            if selectedFile == nil {
                selectedFile = displayed.defaultFile ?? displayed.ggufSiblings.first
            }
            resolveIfNeeded()
        }
    }

    private func resolveIfNeeded() {
        guard live == nil, displayed.ggufSiblings.isEmpty else { return }
        Task {
            do {
                let detail = try await HuggingFaceClient.detail(id: model.id)
                await MainActor.run { live = detail }
                if selectedFile == nil {
                    selectedFile = detail.defaultFile ?? detail.ggufSiblings.first
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private var fileList: some View {
        VStack(spacing: 6) {
            ForEach(displayed.ggufSiblings) { file in
                Button {
                    selectedFile = file
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selectedFile?.id == file.id ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(.indigo)
                        Text(file.rfilename)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(file.size.map(FileFormat.bytes) ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedFile?.id == file.id ? Color.indigo.opacity(0.1) : Color.clear)
                )
            }
        }
    }

    private var installButton: some View {
        Group {
            if installed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Installé")
                }
            } else if isDownloading {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: progress)
                        .frame(width: 150)
                    Text("\(Int(progress * 100)) %")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    install()
                } label: {
                    Label("Installer", systemImage: "arrow.down.circle")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFile == nil)
            }
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3).bold()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func install() {
        guard let file = selectedFile else { return }
        Task {
            await store.download(displayed, file: file)
            errorMessage = nil
        }
    }
}