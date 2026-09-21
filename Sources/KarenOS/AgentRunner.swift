//  ====================================================================
//    KarenOS — AgentRunner.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Moteur d'exécution des missions autonomes (boucle, contrôle, fin).
//    Dépend. : Foundation, SwiftUI
//  --------------------------------------------------------------------
//    Lance la mission avec le modèle de l'agent (chargement automatique puis
//    restauration du modèle précédent), exécute les itérations en streaming
//    en réinjectant le résultat précédent, honore pause/reprise/arrêt et les
//    conditions de fin, et journalise chaque itération dans AgentRun.
//  ====================================================================

import Foundation
import SwiftUI

/// État courant d'un run d'agent, affiché par la fiche agent.
enum AgentRunStatus: Equatable {
    case running
    case paused
    case finished
    case stopped
    case failed(String)
}

/// Entrée du journal d'exécution (une ligne horodatée).
struct AgentRunEntry: Identifiable {
    let id = UUID()
    var text: String
    var date = Date()
}

/// Enregistrement d'une mission : itérations, statut, journal et sorties.
struct AgentRun: Identifiable {
    let id = UUID()
    let agentID: UUID
    var iteration: Int = 0
    var status: AgentRunStatus = .running
    var lastOutput: String = ""
    var entries: [AgentRunEntry] = []
    var startedAt = Date()
}

/// Exécute les missions autonomes : boucle, conditions de fin, contrôle.
///
/// `start` charge le modèle de l'agent (et sauvegarde le modèle précédent),
/// puis lance la boucle de mission. À la fin (condition de fin, arrêt manuel
/// ou échec), `restorePreviousModel` revient au modèle utilisé avant.
@MainActor
final class AgentRunner: ObservableObject {
    @Published private(set) var activeRun: AgentRun?
    @Published private(set) var assignedAgent: Agent?

    private weak var engine: EngineManager?
    private var models: ModelStore?
    private var worker: Task<Void, Never>?
    private var previousModelID: String?
    private var pendingActionResults: String?
    private var actionsExecuted = 0
    private let maxActionsPerRun = 30

    var isRunning: Bool { activeRun != nil }

    // MARK: - Contrôle

    /// Démarre la mission d'un agent.
    ///
    /// - Vérifie que le modèle de l'agent est installé (sinon le run échoue
    ///   immédiatement avec un message explicite).
    /// - Mémorise le modèle actif (`previousModelID`) avant de basculer.
    /// - Un run terminé (`finished`, `stopped`, `failed`) est remplacé par la
    ///   nouvelle mission : un agent reste relançable autant que voulu.
    func start(_ agent: Agent, engine: EngineManager, models: ModelStore) {
        if let run = activeRun, run.status == .running || run.status == .paused { return }
        guard models.isInstalled(id: agent.modelID) else {
            beginRun(agent)
            log("Modèle « \(agent.modelID) » absent. Installe-le dans la Boutique.", iteration: 0)
            activeRun?.status = .failed("Modèle non installé : \(agent.modelID)")
            return
        }

        self.engine = engine
        self.models = models
        pendingActionResults = nil
        actionsExecuted = 0
        beginRun(agent)
        previousModelID = engine.activeModelID
        log("Mission lancée avec le modèle \(agent.modelID).", iteration: 0)

        let target = activeRun
        worker = Task { [weak self] in
            await self?.runLoop(agent, run: target)
        }
    }

    /// Lance automatiquement le premier agent prêt avec le déclencheur
    /// `.onLaunch` (appelé une fois au démarrage de l'application).
    func startAutoAgents(agentStore: AgentStore, engine: EngineManager, models: ModelStore) {
        guard activeRun == nil else { return }
        guard let agent = agentStore.agents.first(where: { $0.trigger == .onLaunch && $0.isReady }) else { return }
        start(agent, engine: engine, models: models)
    }

    func pause() {
        guard activeRun != nil, activeRun?.status == .running else { return }
        activeRun?.status = .paused
        log("Mission en pause.", iteration: activeRun?.iteration ?? 0)
    }

    func resume() {
        guard activeRun != nil, activeRun?.status == .paused else { return }
        activeRun?.status = .running
        log("Mission reprise.", iteration: activeRun?.iteration ?? 0)
    }

    /// Arrête la mission manuellement, journalise l'arrêt et restaure le
    /// modèle précédent.
    func stop() {
        worker?.cancel()
        worker = nil
        guard let run = activeRun else { return }
        activeRun?.status = .stopped
        log("Mission arrêtée manuellement.", iteration: run.iteration)
        restorePreviousModel()
    }

    func clearLog() {
        activeRun?.entries = []
    }

    func refreshAssignedAgent(agentStore: AgentStore) {
        guard let id = assignedAgent?.id else { return }
        assignedAgent = agentStore.agent(id)
    }

    // MARK: - Boucle d'exécution

    /// Boucle principale de la mission.
    ///
    /// À chaque itération : vérifie la pause, exécute l'appel au modèle,
    /// journalise le résultat, teste les conditions de fin, puis soit s'arrête
    /// (boucle désactivée) soit respecte la période intervalle avant de
    /// recommencer. Les suspendus/cancellations sont vérifiés à chaque pas.
    private func runLoop(_ agent: Agent, run: AgentRun?) async {
        await ensureAgentModel(agent)

        while !Task.isCancelled {
            guard isActiveRun(run) else { break }
            if activeRun?.status == .paused {
                while activeRun?.status == .paused && !Task.isCancelled {
                    guard isActiveRun(run) else { break }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                continue
            }

            guard let baseURL = engine?.chatURL else {
                fail("Le moteur ne répond pas pendant la mission.")
                return
            }

            let iteration = (activeRun?.iteration ?? 0) + 1
            let output: String
            do {
                output = try await executeIteration(agent, baseURL: baseURL)
            } catch {
                if Task.isCancelled || !isActiveRun(run) { return }
                fail("Échec de l'itération \(iteration) : \(error.localizedDescription)")
                return
            }
            guard isActiveRun(run) else { return }
            if Task.isCancelled { break }

            activeRun?.iteration = iteration
            activeRun?.lastOutput = String(output.prefix(2000))
            log(outputLog(for: output), iteration: iteration)

            if let reason = stopReason(agent, iteration: iteration, output: output) {
                activeRun?.status = .finished
                log("Condition de fin atteinte (\(reason)).", iteration: iteration)
                break
            }

            if agent.allowsShell {
                let actions = extractActions(from: output)
                if !actions.isEmpty {
                    if actionsExecuted >= maxActionsPerRun {
                        activeRun?.status = .finished
                        log("Cap d'actions atteint (\(maxActionsPerRun)) — mission terminée.", iteration: iteration)
                        break
                    }
                    var feed = "Résultats de l'exécution des commandes que tu as demandées :"
                    for command in actions {
                        actionsExecuted += 1
                        log("Exécution de la commande : \(command)", iteration: iteration)
                        let result = await ActionRunner.run(command)
                        let out = result.stdout.isEmpty ? "(aucune sortie)" : result.stdout
                        let err = result.stderr.isEmpty ? "" : "\nErreurs : \(result.stderr)"
                        feed += "\n- Commande : \(command)\n  Code de sortie : \(result.exitCode)\n  Sortie : \(out)\(err)"
                        if actionsExecuted >= maxActionsPerRun {
                            feed += "\nCap d'actions atteint (\(maxActionsPerRun)), la mission doit conclure."
                            break
                        }
                    }
                    pendingActionResults = feed
                    continue
                }
            }

            if !agent.loopForever {
                activeRun?.status = .finished
                log("Mission terminée (boucle désactivée).", iteration: iteration)
                break
            }
            if case .interval(let seconds) = agent.trigger {
                log("Prochaine itération dans \(max(1, seconds)) s…", iteration: iteration)
                await waitForInterval(seconds, run: run)
            }
        }

        finishRun()
    }

    /// Une itération : prompt système (mission) + rappel du résultat précédent,
    /// réponse lue en streaming, texte accumulé rendu en sortie.
    private func executeIteration(_ agent: Agent, baseURL: URL) async throws -> String {
        var messages: [ChatMessage] = [.system(systemPrompt(for: agent))]
        if let previous = activeRun?.lastOutput, !previous.isEmpty {
            messages.append(.user("Poursuis ta mission. Ton dernier résultat :\n\(previous)"))
        }
        if let feed = pendingActionResults, !feed.isEmpty {
            messages.append(.user(feed))
            pendingActionResults = nil
        }
        var accumulated = ""
        for try await piece in ChatService.streamReply(messages, baseURL: baseURL, vision: engine?.hasVision ?? false) {
            try Task.checkCancellation()
            accumulated += piece
        }
        return accumulated
    }

    /// Prompt système de la mission, complété par la capacité « actions » si
    /// elle est activée : le modèle sait alors demander l'exécution d'un
    /// logiciel (via `open`) ou d'une commande shell avec la ligne `ACTION:`.
    private func systemPrompt(for agent: Agent) -> String {
        var prompt = agent.systemPrompt
        if agent.allowsShell {
            prompt += """
            \n\n[Capacité système active]
            Tu peux lancer des logiciels et exécuter des commandes installées sur cet ordinateur.
            Pour demander une exécution, écris une seule ligne commençant par « ACTION: » suivie de la commande, par exemple :
            ACTION: open -a Safari
            ACTION: open https://mail.google.com
            ACTION: ls ~/Documents
            ACTION: ps aux | head -5
            Chaque ACTION est exécutée et le résultat (code de sortie + sortie) t'est renvoyé aussitôt :
            continue ta mission en t'appuyant sur ces résultats. Évite les commandes interactives ou bloquantes.
            """
        }
        return prompt
    }

    /// Repère dans une réponse les lignes de demande d'exécution `ACTION: <commande>`.
    private func extractActions(from output: String) -> [String] {
        var commands: [String] = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.prefix(7).caseInsensitiveCompare("ACTION:") == .orderedSame else { continue }
            var command = String(line.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            if command.hasPrefix("`") { command = String(command.dropFirst()) }
            if command.hasSuffix("`") { command = String(command.dropLast()) }
            if !command.isEmpty { commands.append(command) }
        }
        return commands
    }

    /// Charge le modèle de l'agent s'il n'est pas déjà actif sur le moteur.
    private func ensureAgentModel(_ agent: Agent) async {
        guard let models, let model = models.installedModel(id: agent.modelID) else { return }
        if engine?.activeModelID != agent.modelID {
            let ok = await engine?.load(model: model) ?? false
            if !ok {
                fail("Impossible de charger le modèle \(agent.modelID).")
            }
        }
    }

    // MARK: - Prédicats

    private func shouldStop(_ agent: Agent, iteration: Int, output: String) -> Bool {
        stopReason(agent, iteration: iteration, output: output) != nil
    }

    /// Évalue les conditions de fin (nombre d'itérations, durée maximale,
    /// mot-clé de réussite). Retourne la description de la première condition
    /// atteinte, ou `nil` si aucune n'est satisfaite.
    private func stopReason(_ agent: Agent, iteration: Int, output: String) -> String? {
        for condition in agent.endConditions {
            switch condition {
            case .maxIterations(let n):
                if iteration >= n { return "max \(n) itérations" }
            case .maxDuration(let minutes):
                if let run = activeRun, Date() >= run.startedAt.addingTimeInterval(TimeInterval(minutes * 60)) {
                    return "durée max \(minutes) min"
                }
            case .successKeyword(let keyword):
                if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   output.localizedCaseInsensitiveContains(keyword) {
                    return "mot-clé « \(keyword) » trouvé"
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func beginRun(_ agent: Agent) {
        assignedAgent = agent
        activeRun = AgentRun(agentID: agent.id)
    }

    private func log(_ text: String, iteration: Int) {
        guard activeRun != nil else { return }
        let prefix = iteration > 0 ? "Itération \(iteration) — " : ""
        activeRun?.entries.append(AgentRunEntry(text: prefix + text))
    }

    private func outputLog(for output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Réponse vide." }
        let maxCount = 800
        if trimmed.count <= maxCount { return trimmed }
        return String(trimmed.prefix(maxCount)) + "…"
    }

    private func fail(_ message: String) {
        log(message, iteration: activeRun?.iteration ?? 0)
        activeRun?.status = .failed(message)
        restorePreviousModel()
    }

    private func finishRun() {
        if Task.isCancelled, activeRun?.status == .running || activeRun?.status == .paused {
            activeRun?.status = .stopped
        }
        restorePreviousModel()
    }

    private func isActiveRun(_ run: AgentRun?) -> Bool {
        guard let run else { return activeRun == nil }
        return activeRun?.id == run.id
    }

    private func waitForInterval(_ seconds: Int, run: AgentRun?) async {
        let safe = max(1, seconds)
        var waited: Int = 0
        while waited < safe && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 1
            guard isActiveRun(run) else { return }
        }
    }

    /// Après une mission : revient au modèle utilisé avant (si la mission en
    /// avait chargé un autre) ou arrête le moteur si aucun n'était actif.
    private func restorePreviousModel() {
        guard let engine else { return }
        let prev = previousModelID
        previousModelID = nil

        if let prev, prev != assignedAgent?.modelID, let models, let model = models.installedModel(id: prev) {
            log("Retour au modèle précédent \(prev).", iteration: activeRun?.iteration ?? 0)
            Task {
                await engine.load(model: model)
            }
        } else if prev == nil || assignedAgent == nil {
            engine.stop()
        }
    }
}