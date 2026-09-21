//  ====================================================================
//    KarenOS — KarenOSApp.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Racine de l'application : stores, fenêtre, onglets et fin de vie.
//    Dépend. : SwiftUI, AppKit
//  --------------------------------------------------------------------
//    KarenOSApp assemble les cinq Stores (modèles, moteur, compétences,
//    agents, runner) en environmentObject. ContentView expose les 4 onglets :
//    Mes modèles, Boutique, Agents, Compétences, plus le badge d'état moteur.
//    Au démarrage : installation du moteur + lancement des agents « au
//    lancement » ; à la fermeture : arrêt du runner et du moteur.
//  ====================================================================

import SwiftUI
import AppKit

/// Racine de l'application.
///
/// Construit les shares Stores et les injecte dans l'environnement SwiftUI.
/// Le cycle de vie des Stores (agents, runner, moteur) est rattaché à celui
/// de cette `App`.
@main
struct KarenOSApp: App {
    @StateObject private var store = ModelStore()
    @StateObject private var engine = EngineManager()
    @StateObject private var skills = SkillStore()
    @StateObject private var agents = AgentStore()
    @StateObject private var runner = AgentRunner()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(skills)
                .environmentObject(agents)
                .environmentObject(runner)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Le `TabView` central : les 4 volets de l'application.
///
/// `KARENOS_TAB` (variable d'environnement, outillage de capture) permet de
/// forcer l'onglet initial ; le moteur est installé au démarrage et les
/// agents « au lancement » sont déclenchés. À la fermeture de l'app, le
/// runner et le moteur sont arrêtés proprement.
struct ContentView: View {
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var agents: AgentStore
    @EnvironmentObject private var runner: AgentRunner

    @State private var tab: Int = {
        let raw = Int(ProcessInfo.processInfo.environment["KARENOS_TAB"] ?? "")
        return raw ?? 0
    }()

    var body: some View {
        TabView(selection: $tab) {
            LibraryView()
                .tabItem { Label("Mes modèles", systemImage: "brain.head.profile") }
                .tag(0)

            StoreView()
                .tabItem { Label("Boutique", systemImage: "storefront") }
                .tag(1)

            AgentsView()
                .tabItem { Label("Agents", systemImage: "person.3") }
                .tag(2)

            SkillsView()
                .tabItem { Label("Compétences", systemImage: "wand.and.stars") }
                .tag(3)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EngineStatusBadge(engine: engine)
            }
        }
        .task {
            async let _ = engine.ensureEngine()
            runner.startAutoAgents(agentStore: agents, engine: engine, models: store)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            runner.stop()
            engine.stop()
        }
    }
}

/// Badge global de la barre d'outils : état du moteur et du modèle actif.
    struct EngineStatusBadge: View {
    @ObservedObject var engine: EngineManager

    var body: some View {
        switch engine.state {
        case .idle:
            Text("Moteur à installer").foregroundStyle(.secondary)
        case .installingEngine(let p):
            HStack(spacing: 6) {
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .frame(width: 70)
                Text("Moteur \(Int(p * 100)) %")
            }
        case .ready:
            Label("Moteur prêt", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Chargement du modèle…")
            }
        case .running:
            Label("Modèle actif", systemImage: "play.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Erreur", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}