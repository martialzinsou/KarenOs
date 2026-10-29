// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — SkillsView.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Onglet « Compétences » : liste, détail et édition des compétences.
//    Dépend. : SwiftUI
//  --------------------------------------------------------------------
//    Volet gauche : compétences (SkillStore) avec état actif. Volet droit :
//    SkillDetail (rôle / contexte / obligations + aperçu du prompt système),
//    activation dans le chat et éditeur. SkillEditorSheet propose des
//    modèles prêts à l'emploi (Traducteur, Correcteur de code...).
//  ====================================================================

import SwiftUI

/// Onglet « Compétences » : liste et détail des compétences réutilisables.
struct SkillsView: View {
    @EnvironmentObject private var skillStore: SkillStore

    @State private var selection: Skill.ID?
    @State private var editor: SkillEditorSheet.Mode?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .sheet(item: $editor) { mode in
            SkillEditorSheet(mode: mode) { saved in
                if case .edit = mode {
                    skillStore.update(saved)
                } else {
                    skillStore.add(saved)
                }
                selection = saved.id
            }
        }
        .onChange(of: skillStore.skills.map { $0.id }) { ids in
            if let current = selection, !ids.contains(current) {
                selection = nil
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["KARENOS_OPEN_FIRST_SKILL"] == "1",
               selection == nil {
                selection = skillStore.skills.first?.id
            }
        }
    }

    // MARK: - Volet compétences

    private var sidebar: some View {
        KarenSidebar {
            VStack(spacing: 0) {
                SidebarHeader(
                    title: "Compétences",
                    subtitle: countLabel
                ) {
                    Button {
                        editor = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(KarenIconButtonStyle(size: 28))
                    .help("Créer une nouvelle compétence")
                }

                if skillStore.skills.isEmpty {
                    sidebarEmpty
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(skillStore.skills) { skill in
                                SkillRow(
                                    skill: skill,
                                    isActive: isActive(skill),
                                    selected: selection == skill.id
                                ) {
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        selection = skill.id
                                    }
                                }
                                .contextMenu {
                                    Button("Modifier") { editor = .edit(skill) }
                                    Button("Supprimer") {
                                        skillStore.delete(skill)
                                        if selection == skill.id { selection = nil }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Réutilisables avec n'importe quel modèle.")
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
                    .frame(height: 1)
            ,
            alignment: .top
        )
            }
        }
    }

    private var countLabel: String {
        let count = skillStore.skills.count
        if count == 0 { return "Aucune compétence" }
        return count == 1 ? "1 compétence" : "\(count) compétences"
    }

    private var sidebarEmpty: some View {
        VStack(spacing: 10) {
            IconTile(symbol: "wand.and.stars", tint: .secondary, size: 46)
            Text("Aucune compétence")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            Text("Créez des consignes réutilisables : un rôle, un contexte et des obligations de résultats.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
                .fixedSize(horizontal: false, vertical: true)
            Button("Créer une compétence") { editor = .create }
                .buttonStyle(KarenPrimaryButtonStyle())
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Volet détail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let skill = skillStore.skills.first(where: { $0.id == id }) {
            SkillDetail(skill: skill, isActive: isActive(skill)) { action in
                switch action {
                case .toggleActive:
                    skillStore.setActive(skill, isActive: !isActive(skill))
                case .edit:
                    editor = .edit(skill)
                case .delete:
                    skillStore.delete(skill)
                    selection = nil
                }
            }
        } else {
            EmptyStateView(
                icon: "wand.and.stars",
                title: "Façonnez votre assistant",
                message: "Une compétence ajoute un rôle, un contexte et des obligations de résultats. Activez-la ensuite dans le chat.",
                tint: KarenTheme.violet,
                actionTitle: "Créer une compétence",
                action: { editor = .create }
            )
        }
    }

    private func isActive(_ skill: Skill) -> Bool {
        skillStore.activeSkillID == skill.id
    }
}

/// Ligne de liste d'une compétence (icône, nom, extrait du prompt, active).
struct SkillRow: View {
    let skill: Skill
    let isActive: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        SelectableRow(selected: selected, action: action) {
            HStack(spacing: 10) {
                IconTile(
                    symbol: skill.iconSymbol,
                    tint: isActive ? KarenTheme.mint : KarenTheme.violet,
                    size: 34
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(skill.systemPrompt.isEmpty ? "Aucune consigne" : skill.systemPrompt)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(KarenTheme.mint)
                }
            }
        }
    }
}

/// Fiche détaillée d'une compétence : sections et aperçu du prompt.
struct SkillDetail: View {
    let skill: Skill
    let isActive: Bool
    let onAction: (Action) -> Void

    enum Action {
        case toggleActive
        case edit
        case delete
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    HStack(spacing: 6) {
                        KarenPill(text: "Rôle", systemImage: "person.text.rectangle", tint: KarenTheme.indigo)
                        Text("+")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.secondary.opacity(0.7))
                        KarenPill(text: "Contexte", systemImage: "doc.text", tint: KarenTheme.blue)
                        Text("+")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.secondary.opacity(0.7))
                        KarenPill(text: "Obligations", systemImage: "checklist", tint: KarenTheme.mint)
                        Text("→ prompt système")
                            .font(.system(size: 9.5))
                            .foregroundColor(Color.secondary.opacity(0.7))
                        Spacer()
                    }

                    section(
                        title: "Rôle",
                        icon: "person.text.rectangle",
                        tint: KarenTheme.indigo,
                        text: skill.role,
                        empty: "Aucun rôle défini."
                    )

                    section(
                        title: "Contexte",
                        icon: "doc.text",
                        tint: KarenTheme.blue,
                        text: skill.context,
                        empty: "Aucun contexte défini."
                    )

                    section(
                        title: "Obligations de résultats",
                        icon: "checklist",
                        tint: KarenTheme.mint,
                        text: skill.obligation,
                        empty: "Aucune obligation définie."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    promptPreview
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
                symbol: skill.iconSymbol,
                tint: isActive ? KarenTheme.mint : KarenTheme.violet,
                size: 52
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 9) {
                    Text(skill.name)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                    if isActive {
                        HStack(spacing: 4) {
                            StatusDot(color: KarenTheme.mint, pulsing: true)
                            Text("Active")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(KarenTheme.mint.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(KarenTheme.mint.opacity(0.16), lineWidth: 0.8))
                        .foregroundColor(KarenTheme.mint)
                    }
                }
                Text("Compétence indépendante du modèle choisi.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)
        }
    }

    private func section(
        title: String,
        icon: String,
        tint: Color,
        text: String,
        empty: String
    ) -> some View {
        KarenPanel(padding: 16, radius: 15, fill: true) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(tint)
                    SectionLabel(title)
                }
                Text(text.isEmpty ? empty : text)
                    .font(.system(size: 12.5))
                    .lineSpacing(2.5)
                    .foregroundColor(text.isEmpty ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var promptPreview: some View {
        KarenPanel(padding: 16, radius: 15, fill: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel("Aperçu du prompt système")
                    Spacer()
                    Text("\(skill.systemPrompt.count) caractères")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color.secondary.opacity(0.7))
                }

                if skill.systemPrompt.isEmpty {
                    Text("Aucune consigne définie. Modifiez la compétence pour décrire un rôle, un contexte et des obligations de résultats.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(skill.systemPrompt)
                        .font(.system(size: 10.5, design: .monospaced))
                        .lineSpacing(2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.primary.opacity(0.035))
                        )
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if isActive {
                Button(action: { onAction(.toggleActive) }) {
                    Label("Désactiver dans le chat", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(KarenSecondaryButtonStyle(tint: KarenTheme.mint))
            } else {
                Button(action: { onAction(.toggleActive) }) {
                    Label("Utiliser dans le chat", systemImage: "circle")
                }
                .buttonStyle(KarenPrimaryButtonStyle())
            }

            Button(action: { onAction(.edit) }) {
                Label("Modifier", systemImage: "pencil")
            }
            .buttonStyle(KarenSecondaryButtonStyle())

            Spacer()

            Button(action: { onAction(.delete) }) {
                Label("Supprimer", systemImage: "trash")
            }
            .buttonStyle(KarenSecondaryButtonStyle(tint: KarenTheme.coral))
        }
    }
}

/// Éditeur de compétence (rôle / contexte / obligations) avec modèles.
struct SkillEditorSheet: View {
    enum Mode: Identifiable, Equatable {
        case create
        case edit(Skill)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let skill): return skill.id.uuidString
            }
        }
    }

    let mode: Mode
    let onSave: (Skill) -> Void

    @Environment(\.presentationMode) private var presentationMode

    @State private var name = ""
    @State private var icon = ""
    @State private var role = ""
    @State private var context = ""
    @State private var obligation = ""

    private let iconChoices = [
        "sparkles", "wand.and.stars", "character.bubble", "globe",
        "pencil.and.outline", "doc.text.magnifyingglass", "textformat", "translate",
        "brain.head.profile", "chart.line.uptrend.xyaxis", "hammer", "waveform"
    ]

    private struct Template {
        let name: String
        let icon: String
        let role: String
        let context: String
        let obligation: String
    }

    private let templates: [Template] = [
        Template(
            name: "Traducteur", icon: "globe",
            role: "Traducteur professionnel FR⇄EN",
            context: "L'utilisateur est développeur et envoie du texte technique, de la documentation ou des messages.",
            obligation: "Répondre uniquement avec la traduction demandée, sans commentaire, en conservant la terminologie technique exacte."),
        Template(
            name: "Correcteur de code", icon: "hammer",
            role: "Ingénieur logiciel senior spécialisé en revue de code",
            context: "L'utilisateur soumet du code Swift ou d'autres langages et veut l'améliorer.",
            obligation: "Fournir chaque correction sous forme de code complet, expliquer chaque erreur en une phrase et proposer un test."),
        Template(
            name: "Coach d'apprentissage", icon: "brain.head.profile",
            role: "Tuteur patient et pédagogue",
            context: "L'utilisateur apprend un sujet technique et pose des questions, parfois naïves.",
            obligation: "Expliquer simplement puis avec précision, terminer chaque réponse par une question pour vérifier la compréhension."),
        Template(
            name: "Rédacteur structuré", icon: "pencil.and.outline",
            role: "Rédacteur spécialisé dans les contenus clairs",
            context: "L'utilisateur fournit un sujet et des contraintes de longueur et de ton.",
            obligation: "Rédiger avec un titre, une introduction, des sections titrées et une conclusion ; ne jamais dépasser la longueur demandée.")
    ]

    private var screenTitle: String {
        if case .edit = mode { return "Modifier la compétence" }
        return "Créer une compétence"
    }

    private var saveTitle: String {
        if case .edit = mode { return "Enregistrer" }
        return "Créer la compétence"
    }

    var body: some View {
        ZStack {
            KarenBackground()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    IconTile(symbol: icon.isEmpty ? "wand.and.stars" : icon, tint: KarenTheme.violet, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(screenTitle)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("Un rôle, un contexte, des obligations de résultats.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Menu {
                        ForEach(templates, id: \.name) { template in
                            Button(template.name) { apply(template) }
                        }
                    } label: {
                        Label("Exemples", systemImage: "text.book.closed")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Préremplir avec un modèle prêt à l'emploi")

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
                        fieldsSection
                        previewSection
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
        .frame(width: 620, height: 720)
        .onAppear {
            if case .edit(let skill) = mode {
                name = skill.name
                icon = skill.icon
                role = skill.role
                context = skill.context
                obligation = skill.obligation
            }
        }
    }

    private var identitySection: some View {
        KarenPanel(padding: 16, radius: 15) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Identité")

                styledField("Nom de la compétence", placeholder: "Ex : Traducteur FR→EN", text: $name)

                HStack(spacing: 8) {
                    styledField("Icône SF Symbol", placeholder: "Ex : globe", text: $icon)

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

    private var fieldsSection: some View {
        KarenPanel(padding: 16, radius: 15) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Consignes")

                fieldEditor(
                    title: "Rôle",
                    placeholder: "Ex : Ingénieur logiciel senior spécialisé en revue de code",
                    text: $role,
                    help: "La personnalité ou l'expertise que le modèle doit incarner."
                )
                fieldEditor(
                    title: "Contexte",
                    placeholder: "Ex : l'utilisateur est développeur et soumet son code Swift pour amélioration",
                    text: $context,
                    help: "La situation, le public et les informations nécessaires pour bien répondre."
                )
                fieldEditor(
                    title: "Obligations de résultats",
                    placeholder: "Ex : fournir du code complet, expliquer chaque correction et proposer un test",
                    text: $obligation,
                    help: "Ce que le modèle doit impérativement livrer : format, qualité, livrables attendus."
                )
            }
        }
    }

    private var previewSection: some View {
        KarenPanel(padding: 16, radius: 15) {
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel("Aperçu du prompt système")
                Text(preview)
                    .font(.system(size: 10, design: .monospaced))
                    .lineSpacing(1.5)
                    .foregroundColor(preview.isEmpty ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.035))
                    )
            }
        }
    }

    private var preview: String {
        var sections: [String] = []
        let cleanRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanObligation = obligation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanRole.isEmpty { sections.append("Rôle : \(cleanRole)") }
        if !cleanContext.isEmpty { sections.append("Contexte : \(cleanContext)") }
        if !cleanObligation.isEmpty { sections.append("Obligations de résultats : \(cleanObligation)") }
        return sections.isEmpty ? "Le prompt se construit automatiquement à partir des trois champs." : sections.joined(separator: "\n\n")
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

    private func fieldEditor(
        title: String,
        placeholder: String,
        text: Binding<String>,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
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
                .frame(minHeight: 58)
                .frame(maxHeight: 92)
            Text(help)
                .font(.system(size: 9.5))
                .foregroundColor(Color.secondary.opacity(0.7))
        }
    }

    private func apply(_ template: Template) {
        if name.isEmpty { name = template.name }
        if icon.isEmpty { icon = template.icon }
        role = template.role
        context = template.context
        obligation = template.obligation
    }

    private func save() {
        switch mode {
        case .create:
            onSave(Skill(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                icon: icon,
                role: role,
                context: context,
                obligation: obligation
            ))
        case .edit(let skill):
            var updated = skill
            updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.icon = icon
            updated.role = role
            updated.context = context
            updated.obligation = obligation
            onSave(updated)
        }
        presentationMode.wrappedValue.dismiss()
    }
}
