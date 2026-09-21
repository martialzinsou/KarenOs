// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — SkillsView.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Onglet « Compétences » : liste, détail et édition des compétences.
//    Dépend. : SwiftUI
//  --------------------------------------------------------------------
//    NavigationSplitView des compétences (SkillStore) : liste avec état
//    actif, détail (rôle / contexte / obligations + aperçu du prompt
//    système), activation dans le chat et éditeur. SkillEditorSheet propose
//    des modèles prêts à l'emploi (Traducteur, Correcteur de code...).
//  ====================================================================

import SwiftUI

/// Onglet « Compétences » : liste et détail des compétences réutilisables.
    ///
    /// Alimenté par `SkillStore`. Le détail montre rôle / contexte /
    /// obligations + aperçu du prompt système, avec activation directe dans
    /// le chat. La feuille `SkillEditorSheet` crée/édite une compétence.
    struct SkillsView: View {
    @EnvironmentObject private var skillStore: SkillStore

    @State private var selection: Skill.ID?
    @State private var editor: SkillEditorSheet.Mode?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(skillStore.skills) { skill in
                    SkillRow(skill: skill, isActive: isActive(skill))
                        .tag(skill.id)
                        .contextMenu {
                            Button("Modifier") { editor = .edit(skill) }
                            Button("Supprimer", role: .destructive) { skillStore.delete(skill) }
                        }
                }
            }
            .navigationTitle("Compétences")
            .overlay {
                if skillStore.skills.isEmpty {
                    ContentUnavailableSkillsPlaceholder(onCreate: { editor = .create })
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .create
                    } label: {
                        Label("Nouvelle compétence", systemImage: "plus")
                    }
                }
            }
        } detail: {
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
                VStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 46))
                        .foregroundStyle(.indigo)
                    Text("Sélectionne une compétence")
                        .font(.title3).bold()
                    Text("Les compétences sont réutilisables avec n'importe quel modèle.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(item: $editor) { mode in
            SkillEditorSheet(mode: mode) { saved in
                if case .edit = mode {
                    skillStore.update(saved)
                } else {
                    skillStore.add(saved)
                }
            }
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: skill.iconSymbol)
                .foregroundStyle(isActive ? AnyShapeStyle(.indigo) : AnyShapeStyle(Color.accentColor))
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.headline)
                    .lineLimit(1)
                if !skill.systemPrompt.isEmpty {
                    Text(skill.systemPrompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.indigo)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Fiche détaillée d'une compétence : sections et aperçu du prompt.
    ///
    /// Propose l'activation/désactivation dans le chat (compétence unique
    /// active), l'édition et la suppression.
    struct SkillDetail: View {
    let skill: Skill
    let isActive: Bool
    let onAction: (Action) -> Void

    enum Action {
        case toggleActive
        case edit
        case delete
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: skill.iconSymbol)
                    .font(.system(size: 40))
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(skill.name)
                            .font(.title2).bold()
                        if isActive {
                            Text("Active")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.indigo.opacity(0.15)))
                        }
                    }
                    Text("Compétence indépendante du modèle choisi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                if !skill.role.isEmpty {
                    section(title: "Rôle") {
                        Text(skill.role)
                    }
                }
                if !skill.context.isEmpty {
                    section(title: "Contexte") {
                        Text(skill.context)
                    }
                }
                if !skill.obligation.isEmpty {
                    section(title: "Obligations de résultats") {
                        Text(skill.obligation)
                    }
                }
                if skill.systemPrompt.isEmpty {
                    section(title: "Compétence") {
                        Text("Aucune consigne définie. Modifie-la pour décrire un rôle, un contexte et des obligations de résultats.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    section(title: "Aperçu du prompt système") {
                        Text(skill.systemPrompt)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: { onAction(.toggleActive) }) {
                    Label(isActive ? "Désactiver dans le chat" : "Utiliser dans le chat",
                          systemImage: isActive ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .gray : .indigo)

                Button(action: { onAction(.edit) }) {
                    Label("Modifier", systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive, action: { onAction(.delete) }) {
                    Label("Supprimer", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Éditeur de compétence (rôle / contexte / obligations) avec modèles.
    ///
    /// `templates` propose des exemples prêts à l'emploi (Traducteur,
    /// Correcteur de code…) appliqués via `apply(_:)`. Le mode `.edit` est
    /// pré-rempli au premier rendu.
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

    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(mode.title)
                    .font(.headline)
                Spacer()
                if !templates.isEmpty {
                    Menu {
                        ForEach(templates, id: \.name) { t in
                            Button(t.name) { apply(t) }
                        }
                    } label: {
                        Label("Exemples", systemImage: "text.book.closed")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Préremplir avec un modèle prêt à l'emploi")
                }
            }

            TextField("Nom (ex : Traducteur FR→EN)", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                TextField("Icône SF Symbol (ex : globe)", text: $icon)
                    .textFieldStyle(.roundedBorder)
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
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .help("Choisir une icône")
            }

            fieldEditor(title: "Rôle",
                        placeholder: "Ex : Ingénieur logiciel senior spécialisé en revue de code",
                        text: $role,
                        help: "La personnalité ou l'expertise que le modèle doit incarner.")
            fieldEditor(title: "Contexte",
                        placeholder: "Ex : l'utilisateur est développeur et soumet son code Swift pour amélioration",
                        text: $context,
                        help: "La situation, le public et les informations nécessaires pour bien répondre.")
            fieldEditor(title: "Obligations de résultats",
                        placeholder: "Ex : fournir du code complet, expliquer chaque correction et proposer un test",
                        text: $obligation,
                        help: "Ce que le modèle doit impérativement livrer : format, qualité, livrables attendus.")

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .buttonStyle(.bordered)
                Button(action: save) {
                    Text(mode.title)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 640)
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

    private func fieldEditor(title: String, placeholder: String, text: Binding<String>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                .frame(minHeight: 52)
                .frame(maxHeight: 84)
            Text(help)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func apply(_ t: Template) {
        if name.isEmpty { name = t.name }
        if icon.isEmpty { icon = t.icon }
        role = t.role
        context = t.context
        obligation = t.obligation
    }

    private func save() {
        switch mode {
        case .create:
            onSave(Skill(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                         icon: icon, role: role, context: context, obligation: obligation))
        case .edit(let skill):
            var updated = skill
            updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.icon = icon
            updated.role = role
            updated.context = context
            updated.obligation = obligation
            onSave(updated)
        }
        dismiss()
    }
}

private extension SkillEditorSheet.Mode {
    var title: String {
        switch self {
        case .create: return "Créer"
        case .edit: return "Enregistrer"
        }
    }
}

private struct ContentUnavailableSkillsPlaceholder: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)
            Text("Aucune compétence")
                .font(.headline)
            Text("Crée tes consignes réutilisables avec n'importe quel modèle.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            Button("Nouvelle compétence", action: onCreate)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}