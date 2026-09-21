//  ====================================================================
//    KarenOS — LibraryView.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Onglet « Mes modèles » : liste des modèles installés et chat.
//    Dépend. : SwiftUI
//  --------------------------------------------------------------------
//    NavigationSplitView : liste des modèles installés à gauche (modèle
//    actif mis en évidence), ChatView à droite pour le modèle sélectionné.
//    Placeholder si aucun modèle, suppression contextuelle qui arrête le
//    moteur lorsque le modèle supprimé était actif.
//  ====================================================================

import SwiftUI

/// Onglet « Mes modèles » : bibliothèque des modèles installés + chat.
///
/// La liste affiche chaque `LocalModel` (avec indicateur du modèle actif)
/// et un menu contextuel de suppression ; le détail est le `ChatView` du
/// modèle sélectionné. `KARENOS_OPEN_FIRST_MODEL=1` auto-sélectionne le
/// premier modèle (outillage de capture d'écran).
struct LibraryView: View {
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager

    @State private var selection: LocalModel.ID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.installed) { model in
                    LibraryRow(model: model, isActive: engine.activeModelID == model.id)
                        .tag(model.id)
                        .contextMenu {
                            Button("Supprimer", role: .destructive) {
                                remove(model)
                            }
                        }
                }
            }
            .navigationTitle("Mes modèles")
            .overlay {
                if store.installed.isEmpty {
                    ContentUnavailablePlaceholder()
                }
            }
        } detail: {
            if let id = selection, let model = store.installedModel(id: id) {
                ChatView(model: model)
                    .id(id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 46))
                        .foregroundStyle(.indigo)
                    Text("Sélectionne un modèle pour discuter")
                        .font(.title3).bold()
                    Text("Télécharge d'abord des modèles depuis la Boutique.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["KARENOS_OPEN_FIRST_MODEL"] == "1",
               selection == nil,
               let first = store.installed.first {
                selection = first.id
            }
        }
    }

    private func remove(_ model: LocalModel) {
        if engine.activeModelID == model.id {
            engine.stop()
        }
        store.remove(model)
        if selection == model.id { selection = nil }
    }
}

/// Ligne de liste d'un modèle installé (icône, nom, auteur/taille, actif).
    struct LibraryRow: View {
    let model: LocalModel
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.indigo)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.friendlyName)
                    .font(.headline)
                Text("\(model.author) · \(model.sizeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "waveform")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ContentUnavailablePlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Aucun modèle installé")
                .font(.headline)
            Text("Rends-toi dans la Boutique pour télécharger des IA.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .padding()
    }
}