//  KarenOS
//  Par Martial Zinsou

import SwiftUI
import AppKit

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

struct ContentView: View {
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var agents: AgentStore
    @EnvironmentObject private var runner: AgentRunner

    @State private var tab: Int = 0

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