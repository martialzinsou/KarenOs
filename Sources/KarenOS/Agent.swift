//  ====================================================================
//    KarenOS — Agent.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Modèle de données des agents autonomes et leur persistance.
//    Dépend. : Foundation, SwiftUI
//  --------------------------------------------------------------------
//    Agent = mission + modèle + déclencheur + boucle + conditions de fin.
//    AgentTrigger : manuel, au lancement, ou intervalle en secondes.
//    AgentEndCondition : max d'itérations, durée maximale, mot-clé de
//    réussite. AgentStore persiste les agents dans agents.json (lecture
//    tolérante aux champs absents).
//  ====================================================================

import Foundation
import SwiftUI

/// Quand l'agent se déclenche : manuellement, au lancement de l'app ou
    /// à intervalle régulier (en secondes).
    ///
    /// Codable fidèle au schéma JSON `{"kind": "...", "seconds": n}`.
    enum AgentTrigger: Codable, Hashable {
    case manual
    case onLaunch
    case interval(seconds: Int)

    enum Kind: String, Codable {
        case manual, onLaunch, interval
    }

    enum CodingKeys: String, CodingKey {
        case kind, seconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .manual: self = .manual
        case .onLaunch: self = .onLaunch
        case .interval:
            self = .interval(seconds: try c.decodeIfPresent(Int.self, forKey: .seconds) ?? 60)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manual:
            try c.encode(Kind.manual, forKey: .kind)
        case .onLaunch:
            try c.encode(Kind.onLaunch, forKey: .kind)
        case .interval(let seconds):
            try c.encode(Kind.interval, forKey: .kind)
            try c.encode(seconds, forKey: .seconds)
        }
    }

    var label: String {
        switch self {
        case .manual: return "Manuel"
        case .onLaunch: return "Au lancement"
        case .interval(let seconds): return "Toutes les \(seconds)s"
        }
    }
}

/// Condition qui termine une mission : nombre maximal d'itérations, durée
    /// maximale (minutes) ou mot-clé présent dans la réponse de l'agent.
    ///
    /// Codable fidèle au schéma JSON `{"kind": "...", "value": ...}`.
    enum AgentEndCondition: Codable, Hashable, Identifiable {
    case maxIterations(Int)
    case maxDuration(minutes: Int)
    case successKeyword(String)

    var id: String {
        switch self {
        case .maxIterations: return "maxIterations"
        case .maxDuration: return "maxDuration"
        case .successKeyword: return "successKeyword"
        }
    }

    enum Kind: String, Codable {
        case maxIterations, maxDuration, successKeyword
    }

    var kind: Kind {
        switch self {
        case .maxIterations: return .maxIterations
        case .maxDuration: return .maxDuration
        case .successKeyword: return .successKeyword
        }
    }

    enum CodingKeys: String, CodingKey {
        case kind, value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .maxIterations:
            self = .maxIterations(try c.decodeIfPresent(Int.self, forKey: .value) ?? 5)
        case .maxDuration:
            self = .maxDuration(minutes: try c.decodeIfPresent(Int.self, forKey: .value) ?? 10)
        case .successKeyword:
            self = .successKeyword(try c.decodeIfPresent(String.self, forKey: .value) ?? "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .maxIterations(let n): try c.encode(n, forKey: .value)
        case .maxDuration(let minutes): try c.encode(minutes, forKey: .value)
        case .successKeyword(let keyword): try c.encode(keyword, forKey: .value)
        }
    }

    var label: String {
        switch self {
        case .maxIterations(let n): return "Arrêt après \(n) itérations"
        case .maxDuration(let minutes): return "Durée max \(minutes) min"
        case .successKeyword(let keyword): return "Réussite si contient « \(keyword) »"
        }
    }
}

/// Un agent autonome : une mission exécutée par un modèle choisi.
///
/// - `mission` est le prompt système de la mission ;
/// - `modelID` identifie le modèle installé qui exécutera la mission ;
/// - `trigger` commande le lancement (manuel, app, intervalle) ;
/// - `loopForever` relance la mission en continu à défaut de condition de fin ;
/// - `endConditions` arrêtent la mission (itérations, durée, mot-clé).
///
/// Les propriétés `iconSymbol`, `systemPrompt` et `isReady` exposent des
/// formes « utilisées par l'interface » du modèle.
struct Agent: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var mission: String
    var modelID: String
    var trigger: AgentTrigger
    var loopForever: Bool
    var endConditions: [AgentEndCondition]
    var allowsShell: Bool
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         icon: String = "person.3",
         mission: String = "",
         modelID: String = "",
         trigger: AgentTrigger = .manual,
         loopForever: Bool = false,
         endConditions: [AgentEndCondition] = [],
         allowsShell: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.mission = mission
        self.modelID = modelID
        self.trigger = trigger
        self.loopForever = loopForever
        self.endConditions = endConditions
        self.allowsShell = allowsShell
        self.createdAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, mission, modelID, trigger, loopForever, endConditions, allowsShell, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "person.3"
        mission = try c.decodeIfPresent(String.self, forKey: .mission) ?? ""
        modelID = try c.decodeIfPresent(String.self, forKey: .modelID) ?? ""
        trigger = try c.decodeIfPresent(AgentTrigger.self, forKey: .trigger) ?? .manual
        loopForever = try c.decodeIfPresent(Bool.self, forKey: .loopForever) ?? false
        endConditions = try c.decodeIfPresent([AgentEndCondition].self, forKey: .endConditions) ?? []
        allowsShell = try c.decodeIfPresent(Bool.self, forKey: .allowsShell) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon)
        try c.encode(mission, forKey: .mission)
        try c.encode(modelID, forKey: .modelID)
        try c.encode(trigger, forKey: .trigger)
        try c.encode(loopForever, forKey: .loopForever)
        try c.encode(endConditions, forKey: .endConditions)
        try c.encode(allowsShell, forKey: .allowsShell)
        try c.encode(createdAt, forKey: .createdAt)
    }

    var iconSymbol: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "person.3" : trimmed
    }

    var systemPrompt: String {
        mission.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isReady: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !systemPrompt.isEmpty
            && !modelID.isEmpty
    }
}

/// Registre des agents, persistés dans `agents.json` (écriture atomique,
    /// lecture tolérante aux champs absents).
    @MainActor
    final class AgentStore: ObservableObject {
    @Published private(set) var agents: [Agent] = []

    private let fileURL = AppPaths.agentsURL

    init() {
        AppPaths.ensure()
        load()
    }

    func agent(_ id: UUID) -> Agent? {
        agents.first { $0.id == id }
    }

    func add(_ agent: Agent) {
        agents.insert(agent, at: 0)
        persist()
    }

    func update(_ agent: Agent) {
        guard let index = agents.firstIndex(where: { $0.id == agent.id }) else { return }
        agents[index] = agent
        persist()
    }

    func delete(_ agent: Agent) {
        agents.removeAll { $0.id == agent.id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoded = try? JSONDecoder().decode(AgentsFile.self, from: data)
        agents = decoded?.agents ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(AgentsFile(agents: agents)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private struct AgentsFile: Codable {
    var agents: [Agent]
}