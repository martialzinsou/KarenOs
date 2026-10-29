// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — SupportViews.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Fenêtres « À propos de KarenOS » et « Aide KarenOS ».
//    Dépend. : SwiftUI, AppKit
//  --------------------------------------------------------------------
//    AboutView présente l'application, sa version, sa stack et son auteur
//    Martial Zinsou. HelpView est un centre d'aide en deux volets : prise
//    en main, onglets, astuces et raccourcis, confidentialité, auteur.
//  ====================================================================

import SwiftUI
import AppKit

// MARK: - À propos

struct AboutView: View {
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            KarenBackground()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(KarenIconButtonStyle(size: 26))
                    .help("Fermer")
                }
                .padding(.top, 12)
                .padding(.trailing, 14)

                VStack(spacing: 18) {
                    BrandMark(size: 84)

                    VStack(spacing: 6) {
                        Text("KarenOS")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text(KarenInfo.tagline)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(.secondary)
                        KarenPill(
                            text: "Version \(KarenInfo.version)",
                            systemImage: "tag",
                            tint: KarenTheme.indigo,
                            filled: true
                        )
                        .padding(.top, 2)
                    }

                    Text("Votre assistant privé, puissant et hors ligne. Modèles GGUF, agents autonomes et compétences réutilisables, exécutés directement sur votre Mac.")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380)

                    authorCard

                    HStack(spacing: 6) {
                        KarenPill(text: "Swift", systemImage: "swift", tint: KarenTheme.amber)
                        KarenPill(text: "SwiftUI", systemImage: "square.stack.3d.up", tint: KarenTheme.blue)
                        KarenPill(text: "llama.cpp", systemImage: "cpu", tint: KarenTheme.indigo)
                        KarenPill(text: "GGUF", systemImage: "shippingbox", tint: KarenTheme.mint)
                    }

                    HStack(spacing: 7) {
                        KarenLinkChip(title: "martialzinsou.fr", systemImage: "globe", url: KarenInfo.website)
                        KarenLinkChip(title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: KarenInfo.github)
                        KarenLinkChip(title: "Documentation", systemImage: "book", url: KarenInfo.documentation)
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 3) {
                        Text("Conçu et développé par Martial Zinsou")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Text("© 2026 Martial Zinsou — Tous droits réservés.")
                            .font(.system(size: 9.5))
                            .foregroundColor(Color.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 472, height: 650)
    }

    private var authorCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(KarenTheme.brand)
                Text("MZ")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(width: 54, height: 54)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            .shadow(color: KarenTheme.indigo.opacity(0.30), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(KarenInfo.author)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                Text("Créateur & développeur de KarenOS")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("DSI / CTO · Swift, Rust, macOS")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }

            Spacer(minLength: 8)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 15))
                .foregroundColor(KarenTheme.indigo)
                .help("Auteur de KarenOS")
        }
        .frame(maxWidth: 380)
        .karenCard(padding: 15, radius: 15)
    }
}

// MARK: - Aide

struct HelpView: View {
    private enum Chapter: String, CaseIterable, Identifiable {
        case demarrage, onglets, astuces, confidentialite, auteur

        var id: String { rawValue }

        var title: String {
            switch self {
            case .demarrage: return "Démarrage rapide"
            case .onglets: return "Les quatre espaces"
            case .astuces: return "Astuces & raccourcis"
            case .confidentialite: return "Confidentialité"
            case .auteur: return "À propos de l'auteur"
            }
        }

        var icon: String {
            switch self {
            case .demarrage: return "bolt.fill"
            case .onglets: return "square.grid.2x2"
            case .astuces: return "keyboard"
            case .confidentialite: return "lock.shield"
            case .auteur: return "person.crop.circle"
            }
        }

        var tint: Color {
            switch self {
            case .demarrage: return KarenTheme.blue
            case .onglets: return KarenTheme.indigo
            case .astuces: return KarenTheme.amber
            case .confidentialite: return KarenTheme.mint
            case .auteur: return KarenTheme.violet
            }
        }
    }

    @State private var chapter: Chapter = .demarrage

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(width: 900, height: 660)
        .background(KarenBackground())
    }

    // MARK: Volet de navigation

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Centre d'aide")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("KarenOS · version \(KarenInfo.version)")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 18)

            VStack(spacing: 3) {
                ForEach(Chapter.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { chapter = item }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11.5, weight: .semibold))
                                .frame(width: 16)
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            if chapter == item {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color.secondary.opacity(0.7))
                            }
                        }
                        .foregroundColor(chapter == item ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(chapter == item ? Color.primary.opacity(0.07) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 9) {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)

                HStack(spacing: 9) {
                    ZStack {
                        Circle().fill(KarenTheme.brand)
                        Text("MZ")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(KarenInfo.author)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        Text("Créateur de KarenOS")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 238)
        .background(Color(NSColor.underPageBackgroundColor).opacity(0.55))
        .overlay(
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(width: 1)
    ,
            alignment: .trailing
        )
    }

    // MARK: Contenu

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageTitle

                switch chapter {
                case .demarrage: demarrage
                case .onglets: onglets
                case .astuces: astuces
                case .confidentialite: confidentialite
                case .auteur: auteur
                }

                Text("Aide KarenOS · conçue par Martial Zinsou")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pageTitle: some View {
        HStack(spacing: 13) {
            IconTile(symbol: chapter.icon, tint: chapter.tint, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 2)
    }

    private var subtitle: String {
        switch chapter {
        case .demarrage: return "Quatre étapes pour votre première conversation locale."
        case .onglets: return "Chaque espace de KarenOS, en un coup d'œil."
        case .astuces: return "Gagnez du temps au clavier et dans le chat."
        case .confidentialite: return "Tout reste sur votre Mac, sans compte ni cloud."
        case .auteur: return "Derrière KarenOS, une exigence : une IA locale, utile et durable."
        }
    }

    // MARK: Chapitres

    private var demarrage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpStep(number: 1, icon: "arrow.down.circle", tint: KarenTheme.blue,
                     title: "Installez un modèle",
                     text: "Ouvrez la Boutique, choisissez un modèle GGUF adapté à votre Mac, puis cliquez sur Installer. Le téléchargement se fait une seule fois.")
            HelpStep(number: 2, icon: "bubble.left.and.bubble.right", tint: KarenTheme.indigo,
                     title: "Discutez en local",
                     text: "Dans Mes modèles, sélectionnez le modèle installé. Le moteur llama.cpp le charge en mémoire et la conversation démarre, sans réseau.")
            HelpStep(number: 3, icon: "wand.and.stars", tint: KarenTheme.violet,
                     title: "Activez une compétence",
                     text: "Une compétence ajoute un rôle, un contexte et des obligations de résultats. Activez-la depuis l'onglet Compétences ou le menu du chat.")
            HelpStep(number: 4, icon: "person.3", tint: KarenTheme.mint,
                     title: "Lancez un agent",
                     text: "Créez un agent, donnez-lui une mission et un déclencheur, puis laissez-le travailler. Son journal d'exécution reste consultable.")

            callout(
                icon: "lightbulb",
                tint: KarenTheme.amber,
                title: "Conseil",
                text: "Commencez par un petit modèle (0,5 à 3 milliards de paramètres) pour valider votre configuration, puis montez en taille selon votre mémoire unifiée."
            )
        }
    }

    private var onglets: some View {
        VStack(spacing: 10) {
            HelpFeature(icon: "brain.head.profile", tint: KarenTheme.indigo,
                        title: "Mes modèles",
                        text: "La bibliothèque locale et le chat. Le modèle actif est signalé par une onde verte ; un clic droit permet de le supprimer.")
            HelpFeature(icon: "bag", tint: KarenTheme.blue,
                        title: "Boutique",
                        text: "Une sélection de modèles GGUF et une recherche Hugging Face. Chaque fiche détaille le contexte, la taille et les quantifications.")
            HelpFeature(icon: "person.3", tint: KarenTheme.mint,
                        title: "Agents",
                        text: "Des assistants autonomes avec mission, modèle, déclencheur, boucle et conditions de fin. Vous gardez la main sur chaque exécution.")
            HelpFeature(icon: "wand.and.stars", tint: KarenTheme.violet,
                        title: "Compétences",
                        text: "Des consignes réutilisables avec n'importe quel modèle : traduction, revue de code, pédagogie, rédaction structurée.")
        }
    }

    private var astuces: some View {
        VStack(alignment: .leading, spacing: 14) {
            KarenPanel(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Raccourcis clavier")
                    shortcutRow("⌘ 1", "Mes modèles")
                    shortcutRow("⌘ 2", "Boutique")
                    shortcutRow("⌘ 3", "Agents")
                    shortcutRow("⌘ 4", "Compétences")
                    shortcutRow("⌘ ?", "Cette aide")
                    shortcutRow("⌘ ↩", "Envoyer le message")
                }
            }

            KarenPanel(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Dans le chat")
                    bullet("Joignez une image, une vidéo, un audio ou un fichier avec le trombone.")
                    bullet("Dictez votre message avec le micro : la reconnaissance vocale reste locale.")
                    bullet("Activez un modèle vision (fichier .mmproj) pour analyser les images.")
                    bullet("La compétence active s'applique à tous les messages envoyés.")
                }
            }

            callout(
                icon: "speedometer",
                tint: KarenTheme.blue,
                title: "Performance",
                text: "Pendant l'inférence et la restitution, KarenOS élève la priorité du moteur, utilise tous les cœurs CPU et verrouille le modèle en RAM (aucun échange disque). L'écran et la veille système restent éveillés. Le GPU est exploité lorsque le backend llama.cpp expose Metal ; sur les Mac Intel, le binaire officiel x64 ne fournit que BLAS/Accelerate. Le Neural Engine (NPU) reste réservé à macOS et n'est pas accessible aux processus tiers."
            )
        }
    }

    private var confidentialite: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpFeature(icon: "lock.shield", tint: KarenTheme.mint,
                        title: "Aucune donnée envoyée",
                        text: "Les prompts, les réponses et les fichiers joints sont traités sur votre Mac. KarenOS ne contacte aucun service d'IA distant.")

            HelpFeature(icon: "arrow.down.circle", tint: KarenTheme.blue,
                        title: "Réseau uniquement pour les modèles",
                        text: "La connexion sert à télécharger un modèle GGUF depuis Hugging Face, à votre demande. Ensuite, tout fonctionne hors ligne.")

            HelpFeature(icon: "internaldrive", tint: KarenTheme.indigo,
                        title: "Vos fichiers restent chez vous",
                        text: "Les modèles, compétences et agents sont stockés dans ~/Library/Application Support/KarenOS. Supprimez un modèle depuis l'application pour libérer l'espace.")

            callout(
                icon: "hand.raised",
                tint: KarenTheme.violet,
                title: "Vie privée par conception",
                text: "Pas de compte, pas de télémétrie, pas de cloud. KarenOS est une application locale, point."
            )
        }
    }

    private var auteur: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(KarenTheme.brand)
                    Text("MZ")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: 72, height: 72)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                .shadow(color: KarenTheme.indigo.opacity(0.30), radius: 10, x: 0, y: 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(KarenInfo.author)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Créateur & développeur de KarenOS")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("DSI / CTO · Swift, Rust, macOS")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color.secondary.opacity(0.7))
                }
                Spacer()
            }
            .karenCard(padding: 18)

            KarenPanel(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Le projet")
                    Text("KarenOS est conçu, développé et maintenu par Martial Zinsou. L'objectif : rendre l'IA générative réellement privée, durable et agréable sur macOS, sans dépendre d'un service en ligne.")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 7) {
                KarenLinkChip(title: "martialzinsou.fr", systemImage: "globe", url: KarenInfo.website)
                KarenLinkChip(title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: KarenInfo.github)
                KarenLinkChip(title: "Signaler un problème", systemImage: "exclamationmark.bubble", url: KarenInfo.issues)
            }

            HStack {
                Button("À propos de KarenOS") {
                    NotificationCenter.default.post(name: .karenShowAbout, object: nil)
                }
                .buttonStyle(KarenSecondaryButtonStyle())

                Spacer()

                Text("© 2026 Martial Zinsou — Tous droits réservés.")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .padding(.top, 4)
        }
    }

    // MARK: Composants

    private func shortcutRow(_ keys: String, _ label: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.055)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(KarenTheme.indigo)
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func callout(icon: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            IconTile(symbol: icon, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(tint.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 0.8)
        )
    }
}

private struct HelpStep: View {
    let number: Int
    let icon: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.13))
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(tint.opacity(0.18), lineWidth: 0.8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tint)
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                }
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .karenCard(padding: 14, radius: 13)
    }
}

private struct HelpFeature: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: icon, tint: tint, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .karenCard(padding: 14, radius: 13)
    }
}
