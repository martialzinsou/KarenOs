import SwiftUI

struct ChatView: View {
    let model: LocalModel

    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var skillStore: SkillStore

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

    private var inputBar: some View {
        HStack(spacing: 10) {
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
        .padding(12)
    }

    private var canSend: Bool {
        phase == .loaded && !isGenerating && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func start() async {
        guard !modelMissing else { return }
        phase = .loading
        let ok = await engine.load(model: model)
        phase = ok ? .loaded : .failed(engine.state.errorMessage ?? "Erreur inconnue.")
    }

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            if isGenerating { cancelGeneration() }
            return
        }
        input = ""
        messages.append(.user(text))
        let assistant = ChatMessage.assistant()
        messages.append(assistant)
        isGenerating = true
        Task { await generate(into: assistant) }
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
            for try await piece in ChatService.streamReply(history, baseURL: baseURL) {
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
            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
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