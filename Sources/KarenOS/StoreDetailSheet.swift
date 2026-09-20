import SwiftUI

struct StoreDetailSheet: View {
    let model: RemoteModel

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ModelStore

    @State private var selectedFile: RemoteModel.Sibling?
    @State private var errorMessage: String?

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
                    Text(model.displayName)
                        .font(.title2).bold()
                    Text("par \(model.author)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.licenseLabel)
                    .font(.caption)
                    .padding(5)
                    .background(Capsule().fill(.quaternary))
            }

            HStack(spacing: 16) {
                statItem(value: "\(model.downloadCountText)", label: "téléchargements")
                statItem(value: model.prettyContext, label: "contexte (tokens)")
                if let total = model.totalSize {
                    statItem(value: FileFormat.bytes(total), label: "taille totale")
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            if !model.ggufSiblings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Version à télécharger")
                        .font(.headline)
                    fileList
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
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
                selectedFile = model.defaultFile ?? model.ggufSiblings.first
            }
        }
    }

    private var fileList: some View {
        VStack(spacing: 6) {
            ForEach(model.ggufSiblings) { file in
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
            await store.download(model, file: file)
            errorMessage = nil
        }
    }
}