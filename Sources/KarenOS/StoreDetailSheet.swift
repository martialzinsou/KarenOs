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
struct StoreDetailSheet: View {
    let model: RemoteModel

    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var store: ModelStore

    @State private var selectedFile: RemoteModel.Sibling?
    @State private var errorMessage: String?
    @State private var live: RemoteModel?

    private var displayed: RemoteModel { live ?? model }
    private var installed: Bool { store.isInstalled(id: model.id) }
    private var isDownloading: Bool { store.activeInstalls.contains(model.id) }
    private var progress: Double { store.downloading[model.id] ?? 0 }

    var body: some View {
        ZStack {
            KarenBackground()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 22)
                    .padding(.bottom, 16)

                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        statsPanel
                        versionsSection

                        if let error = store.downloadError[model.id] ?? errorMessage {
                            HStack(spacing: 7) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(KarenTheme.coral)
                                Text(error)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(KarenTheme.coral)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(KarenTheme.coral.opacity(0.07))
                            )
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 9))
                            Text("Téléchargement depuis Hugging Face, exécution 100 % locale ensuite.")
                                .font(.system(size: 9.5))
                        }
                        .foregroundColor(Color.secondary.opacity(0.7))
                    }
                    .padding(22)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)

                bottomBar
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: 560, height: 650)
        .onAppear {
            if selectedFile == nil {
                selectedFile = displayed.defaultFile ?? displayed.ggufSiblings.first
            }
            resolveIfNeeded()
        }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: "cpu", tint: KarenTheme.indigo, size: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayed.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text("par \(displayed.author)")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if !displayed.licenseLabel.isEmpty {
                    KarenPill(text: displayed.licenseLabel, systemImage: "doc.text", tint: KarenTheme.violet)
                        .lineLimit(1)
                }
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(KarenIconButtonStyle(size: 26))
                .help("Fermer")
            }
        }
    }

    // MARK: - Statistiques

    private var statsPanel: some View {
        HStack(spacing: 0) {
            statTile(
                value: displayed.downloadCountText.isEmpty ? "—" : displayed.downloadCountText,
                label: "téléchargements",
                icon: "arrow.down.circle"
            )
            statDivider
            statTile(
                value: displayed.prettyContext.isEmpty ? "—" : "\(displayed.prettyContext) k",
                label: "contexte",
                icon: "text.alignleft"
            )
            statDivider
            statTile(
                value: displayed.totalSize.map(FileFormat.bytes) ?? "—",
                label: "taille totale",
                icon: "internaldrive"
            )
        }
        .karenCard(padding: 14, radius: 14)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(width: 1, height: 30)
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(Color.secondary.opacity(0.7))
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Versions

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Version à télécharger")

            if displayed.ggufSiblings.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Chargement des versions disponibles…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
            } else {
                VStack(spacing: 3) {
                    ForEach(displayed.ggufSiblings) { file in
                        fileRow(file)
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
                )
            }
        }
    }

    private func fileRow(_ file: RemoteModel.Sibling) -> some View {
        let isSelected = selectedFile?.id == file.id
        return Button {
            selectedFile = file
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? KarenTheme.indigo : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(file.rfilename)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(displayed.quantLabel(from: file).uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color.secondary.opacity(0.7))
                }

                Spacer(minLength: 6)

                Text(file.size.map(FileFormat.bytes) ?? "—")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? KarenTheme.indigo.opacity(0.08) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Barre d'action

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Fermer") { presentationMode.wrappedValue.dismiss() }
                .buttonStyle(KarenSecondaryButtonStyle())

            Spacer()

            installButton
        }
    }

    @ViewBuilder
    private var installButton: some View {
        if installed {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundColor(KarenTheme.mint)
                Text("Déjà installé")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(KarenTheme.mint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(KarenTheme.mint.opacity(0.09)))
            .overlay(Capsule().strokeBorder(KarenTheme.mint.opacity(0.16), lineWidth: 0.8))
        } else if isDownloading {
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView(value: progress)
                    .accentColor(KarenTheme.indigo)
                    .frame(width: 160)
                Text("Téléchargement · \(Int(progress * 100)) %")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
        } else {
            Button {
                install()
            } label: {
                Label("Installer cette version", systemImage: "arrow.down.circle")
            }
            .buttonStyle(KarenPrimaryButtonStyle())
            .disabled(selectedFile == nil)
        }
    }

    // MARK: - Actions

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

    private func install() {
        guard let file = selectedFile else { return }
        Task {
            await store.download(displayed, file: file)
            errorMessage = nil
        }
    }
}
