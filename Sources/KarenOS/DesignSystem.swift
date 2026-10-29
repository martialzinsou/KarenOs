// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — DesignSystem.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Langage visuel partagé : couleurs, fonds, cartes, contrôles.
//    Dépend. : SwiftUI, AppKit
//  --------------------------------------------------------------------
//    Centralise l'identité graphique de KarenOS : palette indigo/violet,
//    fond lumineux adaptatif, cartes en verre dépoli, boutons, pastilles,
//    tuiles d'icônes, états vides et lignes sélectionnables. Les vues de
//    l'application ne redéfinissent plus leur propre style.
//  ====================================================================

import SwiftUI
import AppKit
import Combine

// MARK: - Palette

enum KarenTheme {
    static let indigo = Color(red: 0.37, green: 0.35, blue: 0.89)
    static let violet = Color(red: 0.58, green: 0.37, blue: 0.96)
    static let blue   = Color(red: 0.22, green: 0.52, blue: 0.96)
    static let mint   = Color(red: 0.16, green: 0.74, blue: 0.62)
    static let amber  = Color(red: 0.95, green: 0.63, blue: 0.22)
    static let coral  = Color(red: 0.94, green: 0.36, blue: 0.42)

    static let brand = LinearGradient(
        colors: [indigo, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandSoft = LinearGradient(
        colors: [indigo.opacity(0.20), violet.opacity(0.12)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cool = LinearGradient(
        colors: [blue, mint],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Identité

enum KarenInfo {
    static let author = "Martial Zinsou"
    static let appName = "KarenOS"
    static let tagline = "IA générative 100 % locale"

    static let website = URL(string: "https://martialzinsou.fr")!
    static let github = URL(string: "https://github.com/martialzinsou")!
    static let repository = URL(string: "https://github.com/martialzinsou/KarenOs")!
    static let documentation = URL(string: "https://github.com/martialzinsou/KarenOs/blob/main/docs/DOCUMENTATION.md")!
    static let issues = URL(string: "https://github.com/martialzinsou/KarenOs/issues")!

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Fond

/// Fond de fenêtre : base système + deux halos colorés très diffus.
struct KarenBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)

            GeometryReader { proxy in
                Circle()
                    .fill(KarenTheme.violet.opacity(scheme == .dark ? 0.20 : 0.12))
                    .frame(width: proxy.size.width * 0.62)
                    .blur(radius: 140)
                    .offset(x: proxy.size.width * 0.66, y: -proxy.size.height * 0.38)

                Circle()
                    .fill(KarenTheme.blue.opacity(scheme == .dark ? 0.14 : 0.09))
                    .frame(width: proxy.size.width * 0.52)
                    .blur(radius: 150)
                    .offset(x: -proxy.size.width * 0.12, y: proxy.size.height * 0.62)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Marque

/// Logo KarenOS (ressource du bundle) ou monogramme dégradé de secours.
struct BrandMark: View {
    var size: CGFloat = 30

    private static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "KarenOS-logo", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let logo = Self.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .fill(KarenTheme.brand)
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
        )
        .shadow(color: KarenTheme.indigo.opacity(0.30), radius: size * 0.16, x: 0, y: size * 0.08)
    }
}

/// Pastille carrée d'icône, teintée, utilisée dans les listes et en-têtes.
struct IconTile: View {
    let symbol: String
    var tint: Color = KarenTheme.indigo
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(tint.opacity(0.13))
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(tint.opacity(0.17), lineWidth: 0.8)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(tint)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Cartes

struct KarenCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    var padding: CGFloat = 16
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(scheme == .dark ? 0.68 : 0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(scheme == .dark ? 0.10 : 0.60),
                                Color.primary.opacity(scheme == .dark ? 0.10 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.24 : 0.06), radius: 14, x: 0, y: 7)
    }
}

extension View {
    func karenCard(padding: CGFloat = 16, radius: CGFloat = 16) -> some View {
        modifier(KarenCardModifier(padding: padding, radius: radius))
    }
}

/// Panneau titré et paddé, brique de base des fiches de détail.
struct KarenPanel<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = 16
    var fill: Bool = false
    private let content: Content

    init(padding: CGFloat = 16, radius: CGFloat = 16, fill: Bool = false, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        if fill {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .karenCard(padding: padding, radius: radius)
        } else {
            content.karenCard(padding: padding, radius: radius)
        }
    }
}

// MARK: - Typographie et pastilles

struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.9)
            .foregroundColor(.secondary)
    }
}

struct KarenPill: View {
    var text: String
    var systemImage: String? = nil
    var tint: Color = .secondary
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(filled ? 0.16 : 0.08)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.14), lineWidth: 0.8))
    }
}

struct StatusDot: View {
    let color: Color
    var pulsing: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(pulsing ? 0.8 : 0), radius: pulsing ? 4 : 0)
    }
}

// MARK: - Boutons

struct KarenPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(KarenTheme.brand)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            )
            .shadow(color: KarenTheme.indigo.opacity(configuration.isPressed ? 0.10 : 0.30), radius: 9, x: 0, y: 4)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct KarenSecondaryButtonStyle: ButtonStyle {
    var tint: Color = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.11 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct KarenGhostButtonStyle: ButtonStyle {
    var tint: Color = .secondary
    var selected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundColor(selected ? .white : tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    selected
                        ? KarenTheme.brand
                        : LinearGradient(
                            colors: [Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    selected ? Color.white.opacity(0.18) : Color.primary.opacity(0.08),
                    lineWidth: 0.8
                )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct KarenIconButtonStyle: ButtonStyle {
    var size: CGFloat = 30
    var tint: Color = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(
                Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.11 : 0.055))
            )
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Navigation

struct KarenNavButton: View {
    let title: String
    let systemImage: String
    let selected: Bool
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(selected ? Color.white : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    selected
                        ? KarenTheme.brand
                        : LinearGradient(
                            colors: [hovering ? Color.primary.opacity(0.06) : Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    selected ? Color.white.opacity(0.16) : Color.clear,
                    lineWidth: 0.8
                )
            )
            .shadow(color: selected ? KarenTheme.indigo.opacity(0.28) : .clear, radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Barre latérale

struct KarenSidebar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: 300)
            .background(Color(NSColor.underPageBackgroundColor).opacity(0.55))
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 1),
                alignment: .trailing
            )
    }
}

struct SidebarHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    private let accessory: Accessory

    init(title: String, subtitle: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

extension SidebarHeader where Accessory == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Ligne de liste sélectionnable, avec survol et fond dégradé.
struct SelectableRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    private let content: Content

    @State private var hovering = false

    init(selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            selected
                                ? KarenTheme.brandSoft
                                : LinearGradient(
                                    colors: [hovering ? Color.primary.opacity(0.045) : Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            selected ? KarenTheme.indigo.opacity(0.22) : Color.clear,
                            lineWidth: 0.8
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hovering = value }
        }
    }
}

// MARK: - Champs et en-têtes

struct KarenSearchField: View {
    let placeholder: String
    @Binding var text: String
    var large: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: large ? 13 : 11.5, weight: .semibold))
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: large ? 13 : 12.5))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, large ? 13 : 10)
        .padding(.vertical, large ? 10 : 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        )
    }
}

struct PageHeader<Accessory: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color = KarenTheme.indigo
    private let accessory: Accessory

    init(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color = KarenTheme.indigo,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: icon, tint: tint, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

extension PageHeader where Accessory == EmptyView {
    init(icon: String, title: String, subtitle: String, tint: Color = KarenTheme.indigo) {
        self.init(icon: icon, title: title, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

// MARK: - États vides

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = KarenTheme.indigo
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.10))
                    .frame(width: 104, height: 104)
                    .blur(radius: 18)
                IconTile(symbol: icon, tint: tint, size: 62)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(KarenPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - Indicateur de saisie

struct TypingDots: View {
    @State private var phase = 0
    private let ticker = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(index == phase ? 0.85 : 0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .onReceive(ticker) { _ in phase = (phase + 1) % 3 }
    }
}

// MARK: - Liens

struct KarenLinkChip: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundColor(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.055)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fenêtre

/// Zone de glissement de la fenêtre, placée derrière l'en-tête.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggingView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Petit accessoire AppKit pour la fenêtre sans barre de titre.
struct WindowConfigurator: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let karenSelectTab = Notification.Name("KarenOS.selectTab")
    static let karenShowAbout = Notification.Name("KarenOS.showAbout")
    static let karenShowHelp = Notification.Name("KarenOS.showHelp")
}

/// Replace une fenêtre dans l'écran visible si sa géométrie restaurée
    /// pointe hors de tous les écrans (débranchement d'un moniteur, etc.).
enum WindowPlacement {
    static func ensureVisible(_ window: NSWindow) {
        let intersectsAnyScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        guard !intersectsAnyScreen else { return }
        window.center()
    }
}
