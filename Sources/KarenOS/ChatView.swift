// KarenOS — auteur : Martial Zinsou
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
struct ChatView: View {
    let model: LocalModel

    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var skillStore: SkillStore
    @EnvironmentObject private var resources: ResourceGovernor

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
    @State private var generationTask: Task<Void, Never>?
    @StateObject private var speech = SpeechInputController()

    private let emptyID = UUID()

    private let suggestions: [(text: String, icon: String)] = [
        ("Explique-moi un concept simplement", "lightbulb"),
        ("Résume ce texte en 5 points", "list.bullet"),
        ("Écris une fonction Swift propre", "curlybraces"),
        ("Traduis ce message en anglais", "globe")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

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
                composer
            }
        }
        .onAppear { modelMissing = !model.existsOnDisk }
        .onAppear { Task { await start() } }
        .onAppear {
            speech.onFinalText = { text in
                self.input.append(contentsOf: (self.input.isEmpty ? "" : " ") + text)
            }
        }
        .onDisappear {
            generationTask?.cancel()
            if speech.isListening { speech.stop() }
        }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: 12) {
            IconTile(
                symbol: "sparkles",
                tint: phase.isReady ? KarenTheme.indigo : .secondary,
                size: 38
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(model.friendlyName)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    KarenPill(text: model.quantLabel, tint: KarenTheme.indigo)
                    KarenPill(text: model.sizeLabel)
                    Text("exécution locale")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color.secondary.opacity(0.7))
                }
            }

            Spacer(minLength: 10)

            if !messages.isEmpty {
                Button {
                    clearConversation()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(KarenIconButtonStyle(size: 29))
                .disabled(isGenerating)
                .help("Effacer la conversation")
            }

            skillMenu
            statusPill
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.30))
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1),
            alignment: .bottom
        )
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
                    .font(.system(size: 10.5, weight: .semibold))
                Text(skillStore.activeSkill?.name ?? "Compétence")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .foregroundColor(KarenTheme.indigo)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(KarenTheme.indigo.opacity(0.09)))
            .overlay(Capsule().strokeBorder(KarenTheme.indigo.opacity(0.14), lineWidth: 0.8))
        }
        .menuStyle(.borderlessButton)
        .help("Choisir une compétence pour cette conversation")
    }

    @ViewBuilder
    private var statusPill: some View {
        if resources.isActive {
            statusCapsule("Pleine puissance", tint: KarenTheme.coral) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
            }
            .help("\(engine.resourceSummary)\nInférence et restitution à priorité maximale : ni veille ni App Nap. Le Neural Engine (NPU) n'est pas exposé aux processus tiers et reste réservé à macOS.")
        } else {
            switch phase {
            case .loading:
                statusCapsule("Chargement", tint: KarenTheme.blue) {
                    ProgressView()
                        .controlSize(.mini)
                }
            case .loaded:
                statusCapsule("Prêt", tint: KarenTheme.mint) {
                    StatusDot(color: KarenTheme.mint, pulsing: true)
                }
            case .failed:
                statusCapsule("Erreur", tint: KarenTheme.amber) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                }
            }
        }
    }

    private func statusCapsule<Indicator: View>(
        _ text: String,
        tint: Color,
        @ViewBuilder indicator: () -> Indicator
    ) -> some View {
        HStack(spacing: 5) {
            indicator()
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.09)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.14), lineWidth: 0.8))
    }

    // MARK: - États

    private var loadingView: some View {
        VStack(spacing: 16) {
            BrandMark(size: 58)
            ProgressView()
                .controlSize(.small)
            VStack(spacing: 4) {
                Text("Chargement du modèle en mémoire…")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Le premier chargement peut être plus long.")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
        }
        .padding(40)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(KarenTheme.amber.opacity(0.10))
                    .frame(width: 88, height: 88)
                IconTile(symbol: "exclamationmark.triangle", tint: KarenTheme.amber, size: 52)
            }
            Text("Impossible de charger le modèle")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
            Button("Réessayer") {
                Task { await start() }
            }
            .buttonStyle(KarenPrimaryButtonStyle())
        }
        .padding(40)
        .frame(maxWidth: 460)
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if messages.isEmpty {
                        emptyState
                            .id(emptyID)
                    }
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: messages.last?.content ?? "") { _ in
                scroll(proxy)
            }
            .onChange(of: messages.count) { _ in
                scroll(proxy)
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(messages.last?.id ?? emptyID, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(KarenTheme.indigo.opacity(0.10))
                    .frame(width: 124, height: 124)
                    .blur(radius: 22)
                BrandMark(size: 70)
            }

            VStack(spacing: 6) {
                Text("Bonjour, je suis \(model.friendlyName)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Une conversation privée, exécutée entièrement sur votre Mac.")
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let active = skillStore.activeSkill, !active.systemPrompt.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: active.iconSymbol)
                        .font(.system(size: 10, weight: .semibold))
                    Text("Compétence active : \(active.name)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundColor(KarenTheme.violet)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(KarenTheme.violet.opacity(0.09)))
                .overlay(Capsule().strokeBorder(KarenTheme.violet.opacity(0.14), lineWidth: 0.8))
            }

            VStack(spacing: 8) {
                SectionLabel("Pour commencer")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(0..<suggestions.count, id: \.self) { index in
                        let suggestion = suggestions[index]
                        Button {
                            input = suggestion.text
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: suggestion.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(KarenTheme.indigo)
                                Text(suggestion.text)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.72))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 470)

            Text("Aucune donnée ne quitte votre Mac.")
                .font(.system(size: 9.5))
                .foregroundColor(Color.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 42)
        .padding(.bottom, 20)
    }

    // MARK: - Composeur

    private var visionWarning: String? {
        guard !engine.hasVision,
              pendingFiles.contains(where: { $0.kind == .image })
              || messages.contains(where: { $0.role == "user" && $0.attachments.contains(where: { $0.kind == .image }) })
        else { return nil }
        return "Le modèle actif ne supporte pas les images : elles sont affichées mais ne seront pas analysées. Utilise un modèle vision (fichier .mmproj) pour l'analyse d'images."
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let warning = visionWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(KarenTheme.amber)
                        .padding(.top, 1)
                    Text(warning)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KarenTheme.amber.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(KarenTheme.amber.opacity(0.14), lineWidth: 0.8)
                )
            }

            if !pendingFiles.isEmpty {
                pendingFilesRow
            }

            if speech.isListening {
                liveDictationRow
            }

            HStack(alignment: .bottom, spacing: 9) {
                attachMenu
                micButton

                TextField("Écrivez votre message…", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
                    )
                    .lineLimit(1)

                sendButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    private var attachMenu: some View {
        Menu {
            Button { addFiles(.image) } label: { Label("Image…", systemImage: "photo") }
            Button { addFiles(.video) } label: { Label("Vidéo…", systemImage: "film") }
            Button { addFiles(.audio) } label: { Label("Audio…", systemImage: "waveform") }
            Button { addFiles(.file) } label: { Label("Fichier…", systemImage: "doc") }
        } label: {
            Image(systemName: "paperclip")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 30, height: 30)
        .background(Circle().fill(Color.primary.opacity(0.055)))
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
        .disabled(isGenerating)
        .help("Joindre des fichiers : image, vidéo, audio ou tout autre fichier.")
    }

    private var micButton: some View {
        Button(action: toggleSpeech) {
            Image(systemName: speech.isListening ? "mic.fill" : "mic")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(speech.isListening ? KarenTheme.coral : Color.secondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(
                        speech.isListening
                            ? KarenTheme.coral.opacity(0.12)
                            : Color.primary.opacity(0.055)
                    )
                )
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
        .help("Dicter votre message (reconnaissance vocale locale).")
    }

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(sendFill)
                )
                .shadow(
                    color: isGenerating ? KarenTheme.coral.opacity(0.24) : KarenTheme.indigo.opacity(canSend ? 0.28 : 0),
                    radius: 7,
                    x: 0,
                    y: 3
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend && !isGenerating)
        .keyboardShortcut(.return, modifiers: [.command])
        .help(isGenerating ? "Arrêter la génération" : "Envoyer le message (⌘↩)")
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
            StatusDot(color: KarenTheme.coral, pulsing: true)
            Text(speech.liveText.isEmpty ? "À l'écoute… parlez pour dicter votre message." : speech.liveText)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                speech.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(KarenIconButtonStyle(size: 24, tint: KarenTheme.coral))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KarenTheme.coral.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(KarenTheme.coral.opacity(0.12), lineWidth: 0.8)
        )
    }

    private var canSend: Bool {
        phase == .loaded && !isGenerating
            && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingFiles.isEmpty)
    }

    private var sendFill: LinearGradient {
        if canSend && !isGenerating { return KarenTheme.brand }
        let base = isGenerating ? KarenTheme.coral : Color.secondary.opacity(0.35)
        return LinearGradient(
            colors: [base, base],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
        generationTask = Task { await generate(into: assistant) }
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
        // De l'inférence à la restitution : verrou de ressources (veille,
        // App Nap, priorité) relâché quoi qu'il arrive (fin, erreur, arrêt).
        resources.begin()
        defer { resources.end() }

        var history = Array(messages.dropLast())
        if let active = skillStore.activeSkill, !active.systemPrompt.isEmpty {
            history.insert(.system(active.systemPrompt), at: 0)
        }
        var accumulated = ""
        do {
            for try await piece in ChatService.streamReply(history, baseURL: baseURL, vision: engine.hasVision) {
                if Task.isCancelled { break }
                accumulated += piece
                if let idx = messages.firstIndex(where: { $0.id == assistant.id }) {
                    messages[idx].content = accumulated
                }
            }
        } catch {
            if !Task.isCancelled,
               let idx = messages.firstIndex(where: { $0.id == assistant.id }) {
                messages[idx].content = accumulated + "\n\n— (Erreur : \(error.localizedDescription))"
            }
        }
        isGenerating = false
        generationTask = nil
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func clearConversation() {
        cancelGeneration()
        withAnimation(.easeInOut(duration: 0.15)) {
            messages.removeAll()
        }
    }
}

// MARK: - Bulles

private struct MessageBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 70) }

            if !isUser {
                BrandMark(size: 26)
                    .padding(.top, 2)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !message.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.attachments) { file in
                            AttachmentThumb(file: file)
                        }
                    }
                }

                if isUser {
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .foregroundColor(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(KarenTheme.brand)
                            )
                            .shadow(color: KarenTheme.indigo.opacity(0.18), radius: 8, x: 0, y: 4)
                    }
                } else {
                    Group {
                        if message.content.isEmpty {
                            TypingDots()
                                .padding(.vertical, 3)
                        } else {
                            Text(message.content)
                                .font(.system(size: 13))
                                .lineSpacing(2.5)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.86))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                    )
                }
            }
            .frame(maxWidth: 680, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 70) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

// MARK: - Pièces jointes

private struct AttachmentThumb: View {
    let file: ChatAttachment

    var body: some View {
        Group {
            if file.kind == .image, let image = NSImage(contentsOf: file.fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 240, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            } else {
                VStack(spacing: 5) {
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(KarenTheme.indigo)
                    Text(file.fileName)
                        .font(.system(size: 9.5))
                        .lineLimit(1)
                }
                .padding(9)
                .frame(width: 116)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                )
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
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(KarenTheme.indigo)
            Text(file.fileName)
                .font(.system(size: 10.5))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.055)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
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

// MARK: - Modèle manquant

private struct ModelMissingView: View {
    let model: LocalModel

    var body: some View {
        EmptyStateView(
            icon: "tray.and.arrow.down",
            title: "Modèle introuvable sur le disque",
            message: "Re-téléchargez \(model.friendlyName) depuis la Boutique pour reprendre la conversation.",
            tint: KarenTheme.amber,
            actionTitle: "Ouvrir la Boutique",
            action: {
                NotificationCenter.default.post(name: .karenSelectTab, object: 1)
            }
        )
    }
}

// MARK: - Aides

private extension ChatView.Phase {
    var isReady: Bool {
        if case .loaded = self { return true }
        return false
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
