// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — LibraryView.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Onglet « Mes modèles » : bibliothèque locale et chat.
//    Dépend. : SwiftUI
//  --------------------------------------------------------------------
//    Volet gauche : modèles installés, recherche locale, espace disque.
//    Volet droit : ChatView du modèle sélectionné ou état d'accueil.
//    La sélection est conservée à travers la navigation de l'application.
//  ====================================================================

import SwiftUI

/// Onglet « Mes modèles » : bibliothèque des modèles installés + chat.
struct LibraryView: View {
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager

    @State private var selection: LocalModel.ID?
    @State private var query = ""

    private var filtered: [LocalModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.installed }
        return store.installed.filter {
            $0.friendlyName.localizedCaseInsensitiveContains(trimmed)
                || $0.author.localizedCaseInsensitiveContains(trimmed)
                || $0.quantLabel.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var totalSize: Int64 {
        store.installed.reduce(Int64(0)) { $0 + $1.fileSize }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["KARENOS_OPEN_FIRST_MODEL"] == "1",
               selection == nil,
               let first = store.installed.first {
                selection = first.id
            }
        }
        .onChange(of: store.installed.map { $0.id }) { ids in
            if let current = selection, !ids.contains(current) {
                selection = nil
            }
        }
    }

    // MARK: - Volet bibliothèque

    private var sidebar: some View {
        KarenSidebar {
            VStack(spacing: 0) {
                SidebarHeader(
                    title: "Mes modèles",
                    subtitle: countLabel
                ) {
                    Button {
                        openStore()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(KarenIconButtonStyle(size: 28))
                    .help("Télécharger un modèle depuis la Boutique")
                }

                if !store.installed.isEmpty {
                    KarenSearchField(placeholder: "Filtrer la bibliothèque", text: $query)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }

                if store.installed.isEmpty {
                    sidebarEmpty
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filtered) { model in
                                LibraryRow(
                                    model: model,
                                    isActive: engine.activeModelID == model.id,
                                    selected: selection == model.id
                                ) {
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        selection = model.id
                                    }
                                }
                                .contextMenu {
                                    Button("Supprimer") {
                                        remove(model)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                    }
                    .overlay(
                        Group {
                            if filtered.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                        .font(.system(size: 26))
                                        .foregroundColor(Color.secondary.opacity(0.7))
                                    Text("Aucun modèle correspondant")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    )
                }

                storageFooter
            }
        }
    }

    private var countLabel: String {
        let count = store.installed.count
        if count == 0 { return "Aucun modèle installé" }
        return count == 1 ? "1 modèle installé" : "\(count) modèles installés"
    }

    private var sidebarEmpty: some View {
        VStack(spacing: 10) {
            IconTile(symbol: "tray", tint: .secondary, size: 46)
            Text("Votre bibliothèque est vide")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            Text("Téléchargez un premier modèle GGUF pour discuter hors ligne.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 190)
                .fixedSize(horizontal: false, vertical: true)
            Button("Ouvrir la Boutique", action: openStore)
                .buttonStyle(KarenPrimaryButtonStyle())
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var storageFooter: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Stockage local")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                Text("Tout reste sur ce Mac")
                    .font(.system(size: 9))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            Spacer()
            Text(FileFormat.bytes(totalSize))
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.025))
        .overlay(
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    ,
            alignment: .top
        )
    }

    // MARK: - Volet détail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let model = store.installedModel(id: id) {
            ChatView(model: model)
                .id(id)
        } else if store.installed.isEmpty {
            EmptyStateView(
                icon: "sparkles",
                title: "Bienvenue dans KarenOS",
                message: "Votre IA générative privée. Téléchargez un modèle depuis la Boutique, puis discutez avec lui sans aucune connexion.",
                actionTitle: "Explorer la Boutique",
                action: openStore
            )
        } else {
            EmptyStateView(
                icon: "brain.head.profile",
                title: "Sélectionnez un modèle",
                message: "Choisissez un modèle installé dans la bibliothèque pour démarrer une conversation 100 % locale.",
                tint: KarenTheme.violet
            )
        }
    }

    // MARK: - Actions

    private func openStore() {
        NotificationCenter.default.post(name: .karenSelectTab, object: 1)
    }

    private func remove(_ model: LocalModel) {
        if engine.activeModelID == model.id {
            engine.stop()
        }
        store.remove(model)
        if selection == model.id { selection = nil }
    }
}

/// Ligne de liste d'un modèle installé.
struct LibraryRow: View {
    let model: LocalModel
    let isActive: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        SelectableRow(selected: selected, action: action) {
            HStack(spacing: 10) {
                IconTile(
                    symbol: "brain.head.profile",
                    tint: isActive ? KarenTheme.mint : KarenTheme.indigo,
                    size: 34
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.friendlyName)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("\(model.author) · \(model.sizeLabel)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isActive {
                    HStack(spacing: 3) {
                        StatusDot(color: KarenTheme.mint, pulsing: true)
                        Text("Actif")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(KarenTheme.mint)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(KarenTheme.mint.opacity(0.12)))
                }
            }
        }
    }
}
