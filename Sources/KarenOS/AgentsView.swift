// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — AgentsView.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Onglet « Agents » : liste, fiche, contrôle et édition des agents.
//    Dépend. : SwiftUI
//  --------------------------------------------------------------------
//    NavigationSplitView des agents (AgentStore) adossé au run en cours
//    (AgentRunner). AgentDetail montre la mission, l'exécution, le journal
//    et les contrôles (lancer/pause/reprendre/arrêter/effacer).
//    AgentEditorSheet est l'éditeur complet : nom, icône, mission, modèle,
//    déclencheur, boucle infinie et conditions de fin. StatusBadge colore
//    l'état du run.
//  ====================================================================

import SwiftUI

/// Onglet « Agents » : liste des agents et fiche d'exécution.
    ///
    /// Adossé à `AgentStore` (liste) et `AgentRunner` (run en cours). Le détail
    /// présente la mission, l'exécution, le journal et les contrôles ; la
    /// feuille `AgentEditorSheet` crée/édite un agent.
    struct AgentsView: View {
    @EnvironmentObject private var agentStore: AgentStore
    @EnvironmentObject private var runner: AgentRunner
    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var models: ModelStore

    @State private var selection: Agent.ID?
    @State private var editor: AgentEditorSheet.Mode?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(agentStore.agents) { agent in
                    AgentRow(agent: agent,
                             modelName: modelLabel(agent.modelID),
                             isActive: isRunning(agent))
                        .tag(agent.id)
                        .contextMenu {
                            Button("Modifier") { editor = .edit(agent) }
                            Button("Supprimer", role: .destructive) { agentStore.delete(agent) }
                        }
                }
            }
            .navigationTitle("Agents")
            .overlay {
                if agentStore.agents.isEmpty {
                    ContentUnavailableAgentsPlaceholder(onCreate: { editor = .create })
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .create
                    } label: {
                        Label("Nouvel agent", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let id = selection, let agent = agentStore.agent(id) {
                AgentDetail(agent: agent,
                            modelName: modelLabel(agent.modelID),
                            run: run(for: agent)) { action in
                    switch action {
                    case .launch:
                        runner.start(agent, engine: engine, models: models)
                    case .pause:
                        runner.pause()
                    case .resume:
                        runner.resume()
                    case .stop:
                        runner.stop()
                    case .clearLog:
                        runner.clearLog()
                    case .edit:
                        editor = .edit(agent)
                    case .delete:
                        agentStore.delete(agent)
                        selection = nil
                    }
                }
            } else {
                placeholderDetail
            }
        }
        .sheet(item: $editor) { mode in
            AgentEditorSheet(mode: mode) { saved in
                if case .edit = mode {
                    agentStore.update(saved)
                } else {
                    agentStore.add(saved)
                }
                runner.refreshAssignedAgent(agentStore: agentStore)
                selection = saved.id
            }
        }
    }

    private func isRunning(_ agent: Agent) -> Bool {
        runner.assignedAgent?.id == agent.id
    }

    private func run(for agent: Agent) -> AgentRun? {
        runner.assignedAgent?.id == agent.id ? runner.activeRun : nil
    }

    private func modelLabel(_ modelID: String) -> String {
        guard let model = models.installedModel(id: modelID) else { return modelID }
        return model.friendlyName
    }

    private var placeholderDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.system(size: 46))
                .foregroundStyle(.indigo)
            Text("Sélectionne un agent")
                .font(.title3).bold()
            Text("Crée des agents autonomes : mission, modèle, déclencheur, boucle et conditions de fin.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Ligne de liste d'un agent (icône, nom, modèle, déclencheur, état).
    struct AgentRow: View {
    let agent: Agent
    let modelName: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: agent.iconSymbol)
                .font(.title3)
                .foregroundStyle(isActive ? AnyShapeStyle(.indigo) : AnyShapeStyle(Color.accentColor))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(modelName) · \(agent.trigger.label)\(agent.loopForever ? " · boucle ∞" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isActive {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Fiche d'un agent : mission, configuration, journal et contrôles d'exécution.
    ///
    /// La même vue pilote le lancement (contrôles ad hoc selon l'état du run)
    /// via le callout `onAction`, et affiche le `AgentRun` en direct.
    struct AgentDetail: View {
    let agent: Agent
    let modelName: String
    let run: AgentRun?
    let onAction: (Action) -> Void

    enum Action {
        case launch
        case pause
        case resume
        case stop
        case clearLog
        case edit
        case delete
    }

    @EnvironmentObject private var models: ModelStore

    private var isRunning: Bool {
        run?.status == .running || run?.status == .paused
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: agent.iconSymbol)
                    .font(.system(size: 40))
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(agent.name)
                            .font(.title2).bold()
                        if isRunning {
                            StatusBadge(status: run?.status ?? .running)
                        }
                    }
                    Text("Modèle : \(modelName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                section(title: "Mission") {
                    Text(agent.systemPrompt.isEmpty ? "Aucune mission définie." : agent.systemPrompt)
                        .foregroundStyle(agent.systemPrompt.isEmpty ? .secondary : .primary)
                }
                section(title: "Exécution") {
                    infoGrid
                }
                if let run {
                    runLog(run)
                }
            }

            Spacer()

            controls
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var infoGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Déclencheur").foregroundStyle(.secondary)
                Text(agent.trigger.label)
            }
            GridRow {
                Text("Boucle").foregroundStyle(.secondary)
                Text(agent.loopForever ? "Infinie (tourne en continu)" : "Unique (une seule exécution)")
            }
            GridRow {
                Text("Actions (shell)").foregroundStyle(.secondary)
                Text(agent.allowsShell ? "Autorisées (logiciels + commandes)" : "Non autorisées")
            }
            GridRow {
                Text("Conditions de fin").foregroundStyle(.secondary)
                Text(agent.endConditions.isEmpty ? "Aucune" : agent.endConditions.map { $0.label }.joined(separator: " · "))
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var controls: some View {
        if isRunning {
            HStack(spacing: 12) {
                Button(action: { onAction(run?.status == .paused ? .resume : .pause) }) {
                    Label(run?.status == .paused ? "Reprendre" : "Pause", systemImage: run?.status == .paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive, action: { onAction(.stop) }) {
                    Label("Arrêter", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        } else {
            HStack(spacing: 12) {
                Button(action: { onAction(.launch) }) {
                    Label("Lancer la mission", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!agent.isReady || (models.installedModel(id: agent.modelID) == nil))

                Button(action: { onAction(.edit) }) {
                    Label("Modifier", systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                Spacer()

                if run != nil {
                    Button(action: { onAction(.clearLog) }) {
                        Label("Effacer le journal", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive, action: { onAction(.delete) }) {
                    Label("Supprimer", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func runLog(_ run: AgentRun) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Journal d'exécution")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(run.iteration) itérations · depuis \(Self.time(run.startedAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(run.entries.enumerated()), id: \.element.id) { _, entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(Self.time(entry.date))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                            Text(entry.text)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// Pastille colorée de l'état d'un run (en cours, pause, terminé…).
    struct StatusBadge: View {
    let status: AgentRunStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.15)))
        .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .running: return .green
        case .paused: return .orange
        case .finished: return .blue
        case .stopped: return .gray
        case .failed: return .red
        }
    }

    private var title: String {
        switch status {
        case .running: return "En cours"
        case .paused: return "En pause"
        case .finished: return "Terminé"
        case .stopped: return "Arrêté"
        case .failed: return "Échec"
        }
    }
}

/// Éditeur d'agent : mission, modèle, déclencheur, boucle et conditions de fin.
    ///
    /// Mode `.create` ou `.edit(Agent)` (pré-rempli via `hydrate`). Les
    /// conditions de fin (max itérations, durée, mot-clé) sont activables
    /// indépendamment puis réunies par `buildEndConditions`.
    struct AgentEditorSheet: View {
    enum Mode: Identifiable, Equatable {
        case create
        case edit(Agent)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let agent): return agent.id.uuidString
            }
        }
    }

    let mode: Mode
    let onSave: (Agent) -> Void

    @EnvironmentObject private var models: ModelStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var icon = ""
    @State private var mission = ""
    @State private var modelID = ""

    @State private var triggerKind: AgentTrigger.Kind = .manual
    @State private var intervalSeconds = 60

    @State private var loopForever = false

    @State private var allowsShell = false

    @State private var useMaxIterations = false
    @State private var maxIterations = 5
    @State private var useMaxDuration = false
    @State private var maxDurationMinutes = 10
    @State private var useSuccessKeyword = false
    @State private var successKeyword = ""

    private let iconChoices = [
        "person.3", "robot", "hammer", "wand.and.stars", "brain.head.profile",
        "globe", "chart.line.uptrend.xyaxis", "doc.text.magnifyingglass", "shield.lefthalf.filled",
        "paperplane", "cross.case", "camera.macro", "leaf", "bolt.fill"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(mode.title)
                    .font(.headline)
                Spacer()
            }

            TextField("Nom (ex : Correcteur de code)", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                TextField("Icône SF Symbol", text: $icon)
                    .textFieldStyle(.roundedBorder)
                Menu {
                    ForEach(iconChoices, id: \.self) { symbol in
                        Button {
                            icon = symbol
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                } label: {
                    Image(systemName: icon.isEmpty ? "square.grid.2x2" : icon)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .help("Choisir une icône")
            }

            fieldEditor(title: "La mission de l'agent",
                        placeholder: "Décris la mission en détail : objectif, méthode, livrables, interdits…",
                        text: $mission)

            VStack(alignment: .leading, spacing: 4) {
                Text("Modèle utilisé")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Menu {
                    ForEach(models.installed) { model in
                        Button {
                            modelID = model.id
                        } label: {
                            Label(model.friendlyName, systemImage: modelID == model.id ? "checkmark" : "circle")
                        }
                    }
                    if models.installed.isEmpty {
                        Text("Aucun modèle installé — va dans la Boutique.")
                    }
                } label: {
                    HStack {
                        Text(modelLabel)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }
                .menuStyle(.borderlessButton)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Déclencheur")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $triggerKind) {
                    Text("Manuel (bouton Lancer)").tag(AgentTrigger.Kind.manual)
                    Text("Au lancement de l'app").tag(AgentTrigger.Kind.onLaunch)
                    Text("Toutes les X secondes").tag(AgentTrigger.Kind.interval)
                }
                .pickerStyle(.segmented)
                if triggerKind == .interval {
                    HStack {
                        Text("Période :")
                        Stepper("\(intervalSeconds) s", value: $intervalSeconds, in: 5...3600, step: 5)
                    }
                    .font(.callout)
                }
            }

            Toggle("Boucle infinie (tourne en continu jusqu'à une condition de fin)", isOn: $loopForever)
                .font(.callout)

            Toggle(isOn: $allowsShell) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lancer des logiciels et exécuter des commandes")
                        .font(.callout)
                    Text("L'agent pourra demander des actions (open, shell…) via « ACTION: », avec résultats renvoyés. Surveille le journal d'exécution.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            endConditionsEditor

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .buttonStyle(.bordered)
                Button(action: save) {
                    Text(mode.title)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 760)
        .onAppear(perform: hydrate)
    }

    private var modelLabel: String {
        if modelID.isEmpty { return "Choisir un modèle" }
        return models.installedModel(id: modelID)?.friendlyName ?? modelID
    }

    private var endConditionsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Conditions de fin")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                HStack {
                    Toggle("", isOn: $useMaxIterations).labelsHidden()
                    Text("Arrêter après")
                    Stepper("\(maxIterations) itérations", value: $maxIterations, in: 1...1000)
                        .disabled(!useMaxIterations)
                    Spacer()
                }
                HStack {
                    Toggle("", isOn: $useMaxDuration).labelsHidden()
                    Text("Durée maximale")
                    Stepper("\(maxDurationMinutes) min", value: $maxDurationMinutes, in: 1...1440)
                        .disabled(!useMaxDuration)
                    Spacer()
                }
                HStack {
                    Toggle("", isOn: $useSuccessKeyword).labelsHidden()
                    Text("Arrêter si la réponse contient le mot-clé")
                    TextField("ex : TERMINÉ", text: $successKeyword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .disabled(!useSuccessKeyword)
                }
            }
            .font(.callout)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    private func fieldEditor(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                .frame(minHeight: 70)
                .frame(maxHeight: 110)
            Text(placeholder)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func hydrate() {
        if case .edit(let agent) = mode {
            name = agent.name
            icon = agent.icon
            mission = agent.mission
            modelID = agent.modelID
            loopForever = agent.loopForever
            allowsShell = agent.allowsShell
            switch agent.trigger {
            case .manual: triggerKind = .manual
            case .onLaunch: triggerKind = .onLaunch
            case .interval(let seconds): triggerKind = .interval; intervalSeconds = seconds
            }
            useMaxIterations = false
            useMaxDuration = false
            useSuccessKeyword = false
            for condition in agent.endConditions {
                switch condition {
                case .maxIterations(let n): useMaxIterations = true; maxIterations = n
                case .maxDuration(let minutes): useMaxDuration = true; maxDurationMinutes = minutes
                case .successKeyword(let keyword): useSuccessKeyword = true; successKeyword = keyword
                }
            }
        }
    }

    private func buildEndConditions() -> [AgentEndCondition] {
        var conditions: [AgentEndCondition] = []
        if useMaxIterations { conditions.append(.maxIterations(maxIterations)) }
        if useMaxDuration { conditions.append(.maxDuration(minutes: maxDurationMinutes)) }
        if useSuccessKeyword {
            let keyword = successKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !keyword.isEmpty { conditions.append(.successKeyword(keyword)) }
        }
        return conditions
    }

    private func trigger() -> AgentTrigger {
        switch triggerKind {
        case .manual: return .manual
        case .onLaunch: return .onLaunch
        case .interval: return .interval(seconds: intervalSeconds)
        }
    }

    private func save() {
        let newAgent = Agent(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon,
            mission: mission,
            modelID: modelID,
            trigger: trigger(),
            loopForever: loopForever,
            endConditions: buildEndConditions(),
            allowsShell: allowsShell
        )
        switch mode {
        case .create:
            onSave(newAgent)
        case .edit(let agent):
            var updated = newAgent
            updated.id = agent.id
            updated.createdAt = agent.createdAt
            onSave(updated)
        }
        dismiss()
    }
}

private extension AgentEditorSheet.Mode {
    var title: String {
        switch self {
        case .create: return "Créer"
        case .edit: return "Enregistrer"
        }
    }
}

private struct ContentUnavailableAgentsPlaceholder: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3")
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)
            Text("Aucun agent")
                .font(.headline)
            Text("Crée des agents autonomes : donne-leur une mission, un modèle, un déclencheur et des conditions de fin.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button("Nouvel agent", action: onCreate)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}