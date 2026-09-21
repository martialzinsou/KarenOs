//  ====================================================================
//    KarenOS — ChatView.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Interface de discussion avec un modèle (chat + multimodal).
//    Dépend. : SwiftUI
//  --------------------------------------------------------------------
//    Charge le modèle à l'apparition, pilote les phases, maintient
//    l'historique en streaming, offre le menu de compétences, le statut et
//    la barre d'entrée : trombone (pièces jointes), micro (dictée), champ
//    texte, bouton envoyer/arrêter. MessageBubble, AttachmentThumb,
//    AttachmentChip et ModelMissingView sont les vues auxiliaires.
//  ====================================================================

import SwiftUI

/// Fenêtre de discussion avec un modèle : historique, streaming et entrées
    /// multimodal (pièces jointes + dictée vocale).
    ///
    /// Déroulé du cycle de vie : vérification de la présence du fichier
    /// (`modelMissing`), chargement (`start`), affichage des phases, puis
    /// état `.loaded` où la barre d'entrée est active. La génération remplit
    /// le message assistant bulle par bulle via `ChatService.streamReply`.
    struct ChatView: View {
    let model: LocalModel

    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var skillStore: SkillStore

    /// Phase de chargement d'un modèle, observée par l'interface du chat.
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isGenerating = false
    @State private var phase: Phase = .loading
    @State private var modelMissing = false
    @State private var pendingFiles: [ChatAttachment] = []
    @StateObject private var speech = SpeechInputController()

    private let emptyID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                if modelMissing {
                    ModelMissingView(model: model)
                } else {
                    switch phase {
                    case .loading:
                        loadingView
                    case .failed(let message):
                        failureView(message)
                    case .loaded:
                        conversation
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !modelMissing && phase != .loading {
                Divider()
                inputBar
            }
        }
        .onAppear { modelMissing = !model.existsOnDisk }
        .task { await start() }
        .onAppear {
            speech.onFinalText = { text in
                self.input.append(contentsOf: (self.input.isEmpty ? "" : " ") + text)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.friendlyName)
                    .font(.headline)
                Text("\(model.quantLabel) · \(model.sizeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            skillMenu
            statusPill
        }
        .padding()
        .background(.bar)
    }

    private var skillMenu: some View {
        Menu {
            Button {
                skillStore.setActive(skillStore.activeSkill, isActive: false)
            } label: {
                Label("Aucune", systemImage: skillStore.activeSkillID == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(skillStore.skills) { skill in
                Button {
                    skillStore.setActive(skill, isActive: skillStore.activeSkillID != skill.id)
                } label: {
                    Label(skill.name, systemImage: skillStore.activeSkillID == skill.id ? "checkmark" : "circle")
                }
            }
            if skillStore.skills.isEmpty {
                Text("Crée une compétence dans l'onglet Compétences.")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: skillStore.activeSkill?.iconSymbol ?? "wand.and.stars")
                Text(skillStore.activeSkill?.name ?? "Compétence")
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.indigo.opacity(0.14)))
            .foregroundStyle(.indigo)
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private var statusPill: some View {
        switch phase {
        case .loading:
            Label("Chargement", systemImage: "hourglass")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.quaternary))
        case .loaded:
            Label("Prêt", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Label("Erreur", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Chargement du modèle en mémoire…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Le premier chargement peut être plus long.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Impossible de charger le modèle")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Réessayer") {
                Task { await start() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: 400)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if messages.isEmpty {
                        emptyState
                            .id(emptyID)
                    }
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.last?.content ?? "") { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(messages.last?.id ?? emptyID, anchor: .bottom)
                }
            }
            .onChange(of: messages.count) { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(messages.last?.id ?? emptyID, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("Discute avec \(model.friendlyName)")
                .font(.title3).bold()
            Text("Tout est traité en local sur ton Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let active = skillStore.activeSkill, !active.systemPrompt.isEmpty {
                Label("Compétence active : \(active.name)", systemImage: active.iconSymbol)
                    .font(.caption)
                    .foregroundStyle(.indigo)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var visionWarning: String? {
        guard !engine.hasVision,
              pendingFiles.contains(where: { $0.kind == .image })
              || messages.contains(where: { $0.role == "user" && $0.attachments.contains(where: { $0.kind == .image }) })
        else { return nil }
        return "Le modèle actif ne supporte pas les images : elles sont affichées mais ne seront pas analysées. Utilise un modèle vision (fichier .mmproj) pour l'analyse d'images."
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if let warning = visionWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 4)
            }
            if !pendingFiles.isEmpty {
                pendingFilesRow
            }
            if speech.isListening {
                liveDictationRow
            }
            HStack(spacing: 10) {
                attachMenu
                micButton
                TextField("Écris ton message…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
                    .lineLimit(1...6)
                    .onSubmit { submit() }

                Button(action: submit) {
                    Image(systemName: isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(12)
    }

    private var attachMenu: some View {
        Menu {
            Button { addFiles(.image) } label: { Label("Image…", systemImage: "photo") }
            Button { addFiles(.video) } label: { Label("Vidéo…", systemImage: "film") }
            Button { addFiles(.audio) } label: { Label("Audio…", systemImage: "waveform") }
            Button { addFiles(.file) } label: { Label("Fichier…", systemImage: "doc") }
        } label: {
            Image(systemName: "paperclip")
                .padding(4)
        }
        .menuStyle(.borderlessButton)
        .disabled(isGenerating)
        .help("Joindre des fichiers : image, vidéo, audio ou tout autre fichier.")
    }

    private var micButton: some View {
        Button(action: toggleSpeech) {
            Image(systemName: speech.isListening ? "mic.fill" : "mic")
                .foregroundStyle(speech.isListening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .padding(4)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
        .help("Dicter ton message à l'application (reconnaissance vocale locale).")
    }

    private var pendingFilesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingFiles) { file in
                    AttachmentChip(file: file) {
                        pendingFiles.removeAll { $0.id == file.id }
                    }
                }
            }
        }
    }

    private var liveDictationRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text(speech.liveText.isEmpty ? "À l'écoute… parle pour dicter ton message." : speech.liveText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                speech.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var canSend: Bool {
        phase == .loaded && !isGenerating
            && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingFiles.isEmpty)
    }

    // MARK: - Actions

    private func start() async {
        guard !modelMissing else { return }
        phase = .loading
        let ok = await engine.load(model: model)
        phase = ok ? .loaded : .failed(engine.state.errorMessage ?? "Erreur inconnue.")
    }

    private func submit() {
        if isGenerating {
            cancelGeneration()
            return
        }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingFiles.isEmpty else { return }
        let files = pendingFiles
        input = ""
        pendingFiles = []
        messages.append(.user(text, files: files))
        let assistant = ChatMessage.assistant()
        messages.append(assistant)
        isGenerating = true
        Task { await generate(into: assistant) }
    }

    private func addFiles(_ kind: ChatAttachment.Kind) {
        let urls = AttachmentPanel.pick(kind: kind)
        pendingFiles.append(contentsOf: urls.map(ChatAttachment.init(url:)))
    }

    private func toggleSpeech() {
        if speech.isListening {
            speech.stop()
        } else {
            speech.start()
        }
    }

    private func generate(into assistant: ChatMessage) async {
        guard let baseURL = engine.chatURL else {
            isGenerating = false
            phase = .failed("Le moteur ne répond pas.")
            return
        }
        var history = Array(messages.dropLast())
        if let active = skillStore.activeSkill, !active.systemPrompt.isEmpty {
            history.insert(.system(active.systemPrompt), at: 0)
        }
        var accumulated = ""
        do {
            for try await piece in ChatService.streamReply(history, baseURL: baseURL, vision: engine.hasVision) {
                accumulated += piece
                if let idx = messages.firstIndex(where: { $0.id == assistant.id }) {
                    messages[idx].content = accumulated
                }
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistant.id }) {
                messages[idx].content = accumulated + "\n\n— (Erreur : \(error.localizedDescription))"
            }
        }
        isGenerating = false
    }

    private func cancelGeneration() {
        isGenerating = false
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !message.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.attachments) { file in
                            AttachmentThumb(file: file)
                        }
                    }
                }
                Text(message.content.isEmpty ? "…" : message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isUser ? AnyShapeStyle(Color.indigo) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
                    )
                    .foregroundStyle(isUser ? .white : .primary)
            }
            if !isUser { Spacer(minLength: 60) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct AttachmentThumb: View {
    let file: ChatAttachment

    var body: some View {
        Group {
            if file.kind == .image, let image = NSImage(contentsOf: file.fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 240, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: iconName)
                        .font(.system(size: 22))
                    Text(file.fileName)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .padding(8)
                .frame(width: 110)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
        .contextMenu {
            Button("Révéler dans le Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.fileURL])
            }
        }
    }

    private var iconName: String {
        switch file.kind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .file: return "doc"
        }
    }
}

private struct AttachmentChip: View {
    let file: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption)
            Text(file.fileName)
                .font(.caption)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var iconName: String {
        switch file.kind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .file: return "doc"
        }
    }
}

private struct ModelMissingView: View {
    let model: LocalModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Modèle introuvable sur le disque")
            Text("Re-télécharge \(model.friendlyName) depuis la Boutique.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

extension EngineManager.State {
    var errorMessage: String? {
        switch self {
        case .failed(let message): return message
        default: return nil
        }
    }
}