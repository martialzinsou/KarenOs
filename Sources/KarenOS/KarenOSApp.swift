import SwiftUI
import AppKit

@main
struct KarenOSApp: App {
    @StateObject private var store = ModelStore()
    @StateObject private var engine = EngineManager()
    @StateObject private var skills = SkillStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(skills)
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Mes modèles", systemImage: "brain.head.profile") }

            StoreView()
                .tabItem { Label("Boutique", systemImage: "storefront") }

            SkillsView()
                .tabItem { Label("Compétences", systemImage: "wand.and.stars") }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EngineStatusBadge(engine: engine)
            }
        }
        .task {
            async let _ = engine.ensureEngine()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
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