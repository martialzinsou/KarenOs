// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — AgentsView.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Onglet « Agents » : liste, fiche, contrôle et édition des agents.
//    Dépend. : SwiftUI
//  --------------------------------------------------------------------
//    Volet gauche : agents (AgentStore) avec état d'exécution. Volet droit :
//    AgentDetail (mission, exécution, journal, contrôles). AgentEditorSheet
//    est l'éditeur complet : nom, icône, mission, modèle, déclencheur,
//    boucle infinie et conditions de fin. StatusBadge colore l'état du run.
//  ====================================================================

import SwiftUI

/// Onglet « Agents » : liste des agents et fiche d'exécution.
struct AgentsView: View {
    @EnvironmentObject private var agentStore: AgentStore
    @EnvironmentObject private var runner: AgentRunner
    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var models: ModelStore

    @State private var selection: Agent.ID?
    @State private var editor: AgentEditorSheet.Mode?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
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
        .onChange(of: agentStore.agents.map { $0.id }) { ids in
            if let current = selection, !ids.contains(current) {
                selection = nil
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["KARENOS_OPEN_FIRST_AGENT"] == "1",
               selection == nil {
                selection = agentStore.agents.first?.id
            }
        }
    }

    // MARK: - Volet agents

    private var sidebar: some View {
        KarenSidebar {
            VStack(spacing: 0) {
                SidebarHeader(
                    title: "Agents",
                    subtitle: countLabel
                ) {
                    Button {
                        editor = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(KarenIconButtonStyle(size: 28))
                    .help("Créer un nouvel agent")
                }

                if agentStore.agents.isEmpty {
                    sidebarEmpty
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(agentStore.agents) { agent in
                                AgentRow(
                                    agent: agent,
                                    modelName: modelLabel(agent.modelID),
                                    isActive: isRunning(agent),
                                    selected: selection == agent.id
                                ) {
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        selection = agent.id
                                    }
                                }
                                .contextMenu {
                                    Button("Modifier") { editor = .edit(agent) }
                                    Button("Supprimer") {
                                        agentStore.delete(agent)
                                        if selection == agent.id { selection = nil }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Les agents utilisent vos modèles locaux.")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color.secondary.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.025))
                .overlay(
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1),
                    alignment: .top
                )
            }
        }
    }

    private var countLabel: String {
        let count = agentStore.agents.count
        if count == 0 { return "Aucun agent" }
        return count == 1 ? "1 agent configuré" : "\(count) agents configurés"
    }

    private var sidebarEmpty: some View {
        VStack(spacing: 10) {
            IconTile(symbol: "person.3", tint: .secondary, size: 46)
            Text("Aucun agent")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            Text("Créez un agent autonome avec une mission, un modèle et des conditions de fin.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
                .fixedSize(horizontal: false, vertical: true)
            Button("Créer un agent") { editor = .create }
                .buttonStyle(KarenPrimaryButtonStyle())
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Volet détail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let agent = agentStore.agent(id) {
            AgentDetail(
                agent: agent,
                modelName: modelLabel(agent.modelID),
                run: run(for: agent)
            ) { action in
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
            EmptyStateView(
                icon: "person.3",
                title: "Pilotez vos agents",
                message: "Donnez une mission à un modèle local, choisissez un déclencheur et suivez chaque itération dans le journal d'exécution.",
                tint: KarenTheme.mint,
                actionTitle: "Créer un agent",
                action: { editor = .create }
            )
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
}

/// Ligne de liste d'un agent (icône, nom, modèle, déclencheur, état).
struct AgentRow: View {
    let agent: Agent
    let modelName: String
    let isActive: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        SelectableRow(selected: selected, action: action) {
            HStack(spacing: 10) {
                IconTile(
                    symbol: agent.iconSymbol,
                    tint: isActive ? KarenTheme.mint : KarenTheme.indigo,
                    size: 34
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("\(modelName) · \(agent.trigger.label)\(agent.loopForever ? " · ∞" : "")")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isActive {
                    StatusDot(color: KarenTheme.mint, pulsing: true)
                }
            }
        }
    }
}

/// Fiche d'un agent : mission, configuration, journal et contrôles d'exécution.
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

    private var isRunning: Bool {
        run?.status == .running || run?.status == .paused
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    KarenPanel(padding: 16, radius: 15, fill: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("Mission")
                            Text(agent.systemPrompt.isEmpty ? "Aucune mission définie." : agent.systemPrompt)
                                .font(.system(size: 12.5))
                                .lineSpacing(2.5)
                                .foregroundColor(agent.systemPrompt.isEmpty ? Color.secondary : Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    KarenPanel(padding: 16, radius: 15, fill: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Exécution")
                            infoGrid
                        }
                    }

                    if let run {
                        runLog(run)
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(24)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)

            controls
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.28))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(
                symbol: agent.iconSymbol,
                tint: isRunning ? KarenTheme.mint : KarenTheme.indigo,
                size: 52
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Text(agent.name)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                    if let run {
                        StatusBadge(status: run.status)
                    }
                }
                HStack(spacing: 6) {
                    KarenPill(text: modelName, systemImage: "cpu", tint: KarenTheme.indigo)
                    KarenPill(text: agent.trigger.label, systemImage: "clock", tint: .secondary)
                    if agent.loopForever {
                        KarenPill(text: "Boucle infinie", systemImage: "repeat", tint: KarenTheme.violet)
                    }
                }
            }

            Spacer(minLength: 8)
        }
    }

    private var infoGrid: some View {
        VStack(alignment: .leading, spacing: 7) {
            infoRow("Déclencheur", agent.trigger.label)
            infoRow("Boucle", agent.loopForever ? "Infinie (tourne en continu)" : "Unique (une seule exécution)")
            infoRow("Actions (shell)", agent.allowsShell ? "Autorisées (logiciels + commandes)" : "Non autorisées")
            infoRow(
                "Conditions de fin",
                agent.endConditions.isEmpty ? "Aucune" : agent.endConditions.map { $0.label }.joined(separator: " · ")
            )
        }
        .font(.system(size: 11.5))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 132, alignment: .leading)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func runLog(_ run: AgentRun) -> some View {
        KarenPanel(padding: 14, radius: 15, fill: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel("Journal d'exécution")
                    Spacer()
                    Text("\(run.iteration) itérations · depuis \(Self.time(run.startedAt))")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color.secondary.opacity(0.7))
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(run.entries.enumerated()), id: \.element.id) { _, entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.time(entry.date))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Color.secondary.opacity(0.7))
                                Text(entry.text)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 190)
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if isRunning {
            HStack(spacing: 10) {
                Button(action: { onAction(run?.status == .paused ? .resume : .pause) }) {
                    Label(run?.status == .paused ? "Reprendre" : "Pause",
                          systemImage: run?.status == .paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(KarenPrimaryButtonStyle())

                Button(action: { onAction(.stop) }) {
                    Label("Arrêter", systemImage: "stop.fill")
                }
                .buttonStyle(KarenSecondaryButtonStyle(tint: KarenTheme.coral))

                Button(action: { onAction(.edit) }) {
                    Label("Modifier", systemImage: "pencil")
                }
                .buttonStyle(KarenSecondaryButtonStyle())

                Spacer()
            }
        } else {
            HStack(spacing: 10) {
                Button(action: { onAction(.launch) }) {
                    Label("Lancer la mission", systemImage: "play.fill")
                }
                .buttonStyle(KarenPrimaryButtonStyle())
                .disabled(!agent.isReady)

                Button(action: { onAction(.edit) }) {
                    Label("Modifier", systemImage: "pencil")
                }
                .buttonStyle(KarenSecondaryButtonStyle())

                Spacer()

                if run != nil {
                    Button(action: { onAction(.clearLog) }) {
                        Label("Effacer le journal", systemImage: "trash")
                    }
                    .buttonStyle(KarenSecondaryButtonStyle())
                }

                Button(action: { onAction(.delete) }) {
                    Label("Supprimer", systemImage: "trash")
                }
                .buttonStyle(KarenSecondaryButtonStyle(tint: KarenTheme.coral))
            }
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
            StatusDot(color: color, pulsing: status == .running)
            Text(title)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.10)))
        .overlay(Capsule().strokeBorder(color.opacity(0.16), lineWidth: 0.8))
        .foregroundColor(color)
    }

    private var color: Color {
        switch status {
        case .running: return KarenTheme.mint
        case .paused: return KarenTheme.amber
        case .finished: return KarenTheme.blue
        case .stopped: return .gray
        case .failed: return KarenTheme.coral
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
    @Environment(\.presentationMode) private var presentationMode

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

    private var screenTitle: String {
        if case .edit = mode { return "Modifier l'agent" }
        return "Créer un agent"
    }

    private var saveTitle: String {
        if case .edit = mode { return "Enregistrer" }
        return "Créer l'agent"
    }

    var body: some View {
        ZStack {
            KarenBackground()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    IconTile(symbol: icon.isEmpty ? "person.3" : icon, tint: KarenTheme.indigo, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(screenTitle)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("Mission, modèle, déclencheur et conditions d'arrêt.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(KarenIconButtonStyle(size: 26))
                    .help("Fermer")
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 14)

                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        identitySection
                        missionSection
                        modelSection
                        triggerSection
                        permissionsSection
                        endConditionsEditor
                    }
                    .padding(22)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)

                HStack {
                    Spacer()
                    Button("Annuler") { presentationMode.wrappedValue.dismiss() }
                        .buttonStyle(KarenSecondaryButtonStyle())
                    Button(action: save) {
                        Text(saveTitle)
                    }
                    .buttonStyle(KarenPrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 660, height: 740)
        .onAppear(perform: hydrate)
    }

    // MARK: - Sections

    private var identitySection: some View {
        KarenPanel(padding: 16, radius: 15) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Identité")

                styledField("Nom de l'agent", placeholder: "Ex : Correcteur de code", text: $name)

                HStack(spacing: 8) {
                    styledField("Icône SF Symbol", placeholder: "Ex : hammer", text: $icon)

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
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 34, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                            )
                    }
                    .menuStyle(.borderlessButton)
                    .help("Choisir une icône")
                }
            }
        }
    }

    private var missionSection: some View {
        KarenPanel(padding: 16, radius: 15) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Mission")
                fieldEditor(
                    title: "La mission de l'agent",
                    placeholder: "Décrivez la mission en détail : objectif, méthode, livrables, interdits…",
                    text: $mission
                )
            }
        }
    }

    private var modelSection: some View {
        KarenPanel(padding: 16, radius: 15) {
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel("Modèle utilisé")

                Menu {
                    ForEach(models.installed) { model in
                        Button {
                            modelID = model.id
                        } label: {
                            Label(model.friendlyName, systemImage: modelID == model.id ? "checkmark" : "circle")
                        }
                    }
                    if models.installed.isEmpty {
                        Text("Aucun modèle installé — allez dans la Boutique.")
                    }
                } label: {
                    HStack {
                        Text(modelLabel)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                    )
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    private var triggerSection: some View {
        KarenPanel(padding: 16, radius: 15) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Déclencheur & boucle")

                Picker("", selection: $triggerKind) {
                    Text("Manuel").tag(AgentTrigger.Kind.manual)
                    Text("Au lancement").tag(AgentTrigger.Kind.onLaunch)
                    Text("Intervalle").tag(AgentTrigger.Kind.interval)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if triggerKind == .interval {
                    HStack {
                        Text("Période")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                        Spacer()
                        Stepper("\(intervalSeconds) secondes", value: $intervalSeconds, in: 5...3600, step: 5)
                            .font(.system(size: 11.5))
                    }
                }

                Toggle(isOn: $loopForever) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Boucle infinie")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("L'agent tourne en continu jusqu'à une condition de fin.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    private var permissionsSection: some View {
        KarenPanel(padding: 16, radius: 15) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Autorisations")

                Toggle(isOn: $allowsShell) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lancer des logiciels et exécuter des commandes")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("L'agent peut demander des actions (open, shell…) via « ACTION: », avec résultats renvoyés. Surveillez le journal d'exécution.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    private var endConditionsEditor: some View {
        KarenPanel(padding: 16, radius: 15) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Conditions de fin")

                VStack(spacing: 8) {
                    conditionRow(isOn: $useMaxIterations, label: "Arrêter après") {
                        Stepper("\(maxIterations) itérations", value: $maxIterations, in: 1...1000)
                            .disabled(!useMaxIterations)
                    }

                    conditionRow(isOn: $useMaxDuration, label: "Durée maximale") {
                        Stepper("\(maxDurationMinutes) min", value: $maxDurationMinutes, in: 1...1440)
                            .disabled(!useMaxDuration)
                    }

                    HStack(spacing: 8) {
                        Toggle("", isOn: $useSuccessKeyword)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        Text("Arrêter si la réponse contient")
                            .font(.system(size: 11.5))
                        TextField("ex : TERMINÉ", text: $successKeyword)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                            )
                            .frame(width: 150)
                            .disabled(!useSuccessKeyword)
                        Spacer()
                    }
                }
            }
        }
    }

    private func conditionRow<Accessory: View>(
        isOn: Binding<Bool>,
        label: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
            Text(label)
                .font(.system(size: 11.5))
            accessory()
            Spacer()
        }
    }

    private func styledField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                )
        }
    }

    private func fieldEditor(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TextEditor(text: text)
                .font(.system(size: 12))
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                )
                .frame(minHeight: 82)
                .frame(maxHeight: 120)
            Text(placeholder)
                .font(.system(size: 9.5))
                .foregroundColor(Color.secondary.opacity(0.7))
        }
    }

    private var modelLabel: String {
        if modelID.isEmpty { return "Choisir un modèle" }
        return models.installedModel(id: modelID)?.friendlyName ?? modelID
    }

    // MARK: - Données

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
        presentationMode.wrappedValue.dismiss()
    }
}
