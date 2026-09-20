import SwiftUI

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Consignes")
                    .font(.headline)
                Text(skill.systemPrompt.isEmpty ? "Aucune consigne définie." : skill.systemPrompt)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
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
    @State private var instructions = ""

    private let iconChoices = [
        "sparkles", "wand.and.stars", "character.bubble", "globe",
        "pencil.and.outline", "doc.text.magnifyingglass", "textformat", "translate",
        "brain.head.profile", "chart.line.uptrend.xyaxis", "hammer", "waveform"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.headline)

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

            VStack(alignment: .leading, spacing: 4) {
                Text("Consignes — envoyées au modèle avant chaque échange")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $instructions)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    .frame(minHeight: 160)
            }

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
        .frame(width: 460)
        .onAppear {
            if case .edit(let skill) = mode {
                name = skill.name
                icon = skill.icon
                instructions = skill.instructions
            }
        }
    }

    private func save() {
        switch mode {
        case .create:
            onSave(Skill(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                         icon: icon, instructions: instructions))
        case .edit(let skill):
            var updated = skill
            updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.icon = icon
            updated.instructions = instructions
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