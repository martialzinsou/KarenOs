import SwiftUI

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
    }

    private func remove(_ model: LocalModel) {
        if engine.activeModelID == model.id {
            engine.stop()
        }
        store.remove(model)
        if selection == model.id { selection = nil }
    }
}

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

extension EngineManager {
    var activeModelID: String? {
        if case .running(let id) = state { return id }
        return nil
    }
}