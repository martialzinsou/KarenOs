// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — KarenOSApp.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Racine de l'application : stores, fenêtres, navigation et fin de vie.
//    Dépend. : SwiftUI, AppKit
//  --------------------------------------------------------------------
//    KarenOSApp assemble les cinq Stores (modèles, moteur, compétences,
//    agents, runner) en environmentObject. RootView dessine la coque :
//    en-tête de marque, navigation, état du moteur, accès À propos et Aide.
//    Les fenêtres « À propos » et « Aide » portent l'auteur Martial Zinsou.
//    Au démarrage : installation du moteur + lancement des agents « au
//    lancement » ; à la fermeture : arrêt du runner et du moteur.
//  ====================================================================

import SwiftUI
import AppKit

/// Racine de l'application.
///
/// Construit les Stores partagés et les injecte dans l'environnement SwiftUI.
/// Le cycle de vie des Stores (agents, runner, moteur) est rattaché à celui
/// de cette `App`.
@main
struct KarenOSApp: App {
    @StateObject private var store = ModelStore()
    @StateObject private var engine = EngineManager()
    @StateObject private var skills = SkillStore()
    @StateObject private var agents = AgentStore()
    @StateObject private var runner = AgentRunner()
    @StateObject private var resources = ResourceGovernor.shared

    var body: some Scene {
        WindowGroup("KarenOS") {
            RootView()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(skills)
                .environmentObject(agents)
                .environmentObject(runner)
                .environmentObject(resources)
                .frame(minWidth: 1060, minHeight: 700)
                .background(
                    WindowConfigurator { window in
                        window.title = "KarenOS"
                        window.titleVisibility = .hidden
                        window.titlebarAppearsTransparent = true
                        window.isMovableByWindowBackground = false
                        WindowPlacement.ensureVisible(window)
                    }
                )
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("À propos de KarenOS") {
                    NotificationCenter.default.post(name: .karenShowAbout, object: nil)
                }
            }

            CommandGroup(replacing: .help) {
                Button("Aide KarenOS") {
                    NotificationCenter.default.post(name: .karenShowHelp, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }

            CommandMenu("Navigation") {
                Button("Mes modèles") {
                    NotificationCenter.default.post(name: .karenSelectTab, object: 0)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Boutique") {
                    NotificationCenter.default.post(name: .karenSelectTab, object: 1)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Agents") {
                    NotificationCenter.default.post(name: .karenSelectTab, object: 2)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Compétences") {
                    NotificationCenter.default.post(name: .karenSelectTab, object: 3)
                }
                .keyboardShortcut("4", modifiers: .command)
            }
        }

    }
}

/// Coque de l'application : en-tête, navigation et contenu des quatre onglets.
struct RootView: View {
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var agents: AgentStore
    @EnvironmentObject private var runner: AgentRunner
    /// Fenêtres secondaires rendues en feuille (macOS 11 ne dispose pas
    /// encore de `Window(id:)` ni de `openWindow`).
    private enum AuxiliarySheet: String, Identifiable {
        case about, help
        var id: String { rawValue }
    }

    @State private var auxiliary: AuxiliarySheet?

    @State private var tab: Int = {
        let raw = Int(ProcessInfo.processInfo.environment["KARENOS_TAB"] ?? "")
        return min(max(raw ?? 0, 0), 3)
    }()

    private struct NavItem {
        let index: Int
        let title: String
        let icon: String
    }

    private let items: [NavItem] = [
        NavItem(index: 0, title: "Mes modèles", icon: "brain.head.profile"),
        NavItem(index: 1, title: "Boutique", icon: "bag"),
        NavItem(index: 2, title: "Agents", icon: "person.3"),
        NavItem(index: 3, title: "Compétences", icon: "wand.and.stars")
    ]

    var body: some View {
        ZStack {
            KarenBackground()

            VStack(spacing: 0) {
                topBar
                content
            }
        }
        .onAppear {
            SnapshotHarness.startIfRequested()
            SmokeHarness.startIfRequested(engine: engine, store: store)
            Task {
                async let _ = engine.ensureEngine()
                runner.startAutoAgents(agentStore: agents, engine: engine, models: store)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            runner.stop()
            engine.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .karenSelectTab)) { note in
            guard let index = note.object as? Int else { return }
            select(index)
        }
        .onReceive(NotificationCenter.default.publisher(for: .karenShowAbout)) { _ in
            present(.about)
        }
        .onReceive(NotificationCenter.default.publisher(for: .karenShowHelp)) { _ in
            present(.help)
        }
        .sheet(item: $auxiliary) { sheet in
            switch sheet {
            case .about:
                AboutView()
            case .help:
                HelpView()
            }
        }
    }

    // MARK: - En-tête

    private var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                BrandMark(size: 31)
                VStack(alignment: .leading, spacing: 0) {
                    Text("KarenOS")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(KarenInfo.tagline)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 3) {
                ForEach(items, id: \.index) { item in
                    KarenNavButton(
                        title: item.title,
                        systemImage: item.icon,
                        selected: tab == item.index,
                        help: "\(item.title) (⌘\(item.index + 1))"
                    ) {
                        select(item.index)
                    }
                }
            }
            .padding(4)
            .background(Capsule().fill(Color.primary.opacity(0.035)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.8))

            Spacer(minLength: 8)

            EngineStatusBadge(engine: engine)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: 20)

            Button {
                auxiliary = .help
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(KarenIconButtonStyle(size: 30))
            .help("Aide KarenOS — Martial Zinsou")

            Button {
                auxiliary = .about
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(KarenIconButtonStyle(size: 30))
            .help("À propos de KarenOS — Martial Zinsou")
        }
        .padding(.leading, 82)
        .padding(.trailing, 18)
        .frame(height: 66)
        .background(WindowDragHandle())
        .background(Color(NSColor.windowBackgroundColor).opacity(0.30))
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Contenu

    private var content: some View {
        ZStack {
            LibraryView()
                .opacity(tab == 0 ? 1 : 0)
                .allowsHitTesting(tab == 0)
                .accessibilityHidden(tab != 0)
                .zIndex(tab == 0 ? 1 : 0)

            StoreView()
                .opacity(tab == 1 ? 1 : 0)
                .allowsHitTesting(tab == 1)
                .accessibilityHidden(tab != 1)
                .zIndex(tab == 1 ? 1 : 0)

            AgentsView()
                .opacity(tab == 2 ? 1 : 0)
                .allowsHitTesting(tab == 2)
                .accessibilityHidden(tab != 2)
                .zIndex(tab == 2 ? 1 : 0)

            SkillsView()
                .opacity(tab == 3 ? 1 : 0)
                .allowsHitTesting(tab == 3)
                .accessibilityHidden(tab != 3)
                .zIndex(tab == 3 ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Ferme la feuille en cours avant d'en présenter une autre : macOS 11
    /// ne permet pas d'empiler deux feuilles sur la même fenêtre.
    private func present(_ sheet: AuxiliarySheet) {
        if auxiliary == sheet { return }
        let hadSheet = auxiliary != nil
        auxiliary = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + (hadSheet ? 0.28 : 0)) {
            auxiliary = sheet
        }
    }

    private func select(_ index: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            tab = index
        }
    }
}

/// Badge global de la barre supérieure : état du moteur et du modèle actif.
struct EngineStatusBadge: View {
    @ObservedObject var engine: EngineManager

    var body: some View {
        HStack(spacing: 7) {
            indicator
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.10)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.16), lineWidth: 0.8))
        .help(helpText)
    }

    @ViewBuilder
    private var indicator: some View {
        switch engine.state {
        case .installingEngine(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        case .loading:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        case .ready, .running:
            StatusDot(color: KarenTheme.mint, pulsing: engine.state.isRunning)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
        case .idle:
            StatusDot(color: .secondary)
        }
    }

    private var label: String {
        switch engine.state {
        case .idle: return "Moteur à installer"
        case .installingEngine(let progress): return "Moteur \(Int(progress * 100)) %"
        case .ready: return "Moteur prêt"
        case .loading: return "Chargement…"
        case .running: return "Modèle actif"
        case .failed: return "Erreur moteur"
        }
    }

    private var tint: Color {
        switch engine.state {
        case .ready, .running: return KarenTheme.mint
        case .failed: return KarenTheme.coral
        case .loading, .installingEngine: return KarenTheme.blue
        case .idle: return .secondary
        }
    }

    private var helpText: String {
        switch engine.state {
        case .failed(let message): return message
        default: return "État du moteur llama.cpp local."
        }
    }
}

private extension EngineManager.State {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
