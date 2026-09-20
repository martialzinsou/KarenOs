import Foundation
import SwiftUI

struct Skill: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var role: String
    var context: String
    var obligation: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, icon: String = "sparkles",
         role: String = "", context: String = "", obligation: String = "") {
        self.id = id
        self.name = name
        self.icon = icon
        self.role = role
        self.context = context
        self.obligation = obligation
        self.createdAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, role, context, obligation, createdAt
        case instructions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "sparkles"
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
        obligation = try c.decodeIfPresent(String.self, forKey: .obligation) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        if let legacy = try c.decodeIfPresent(String.self, forKey: .instructions),
           !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           role.isEmpty, context.isEmpty, obligation.isEmpty {
            context = legacy
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon)
        try c.encode(role, forKey: .role)
        try c.encode(context, forKey: .context)
        try c.encode(obligation, forKey: .obligation)
        try c.encode(createdAt, forKey: .createdAt)
    }

    var iconSymbol: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "sparkles" : trimmed
    }

    var isComplete: Bool { !role.isEmpty && !context.isEmpty && !obligation.isEmpty }

    var systemPrompt: String {
        var sections: [String] = []
        let cleanRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanObligation = obligation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanRole.isEmpty { sections.append("Rôle : \(cleanRole)") }
        if !cleanContext.isEmpty { sections.append("Contexte : \(cleanContext)") }
        if !cleanObligation.isEmpty { sections.append("Obligations de résultats : \(cleanObligation)") }
        return sections.joined(separator: "\n\n")
    }
}

@MainActor
final class SkillStore: ObservableObject {
    @Published private(set) var skills: [Skill] = []
    @Published var activeSkillID: UUID?

    private let fileURL = AppPaths.skillsURL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        load()
    }

    var activeSkill: Skill? {
        guard let id = activeSkillID else { return nil }
        return skills.first { $0.id == id }
    }

    // MARK: - CRUD

    func add(_ skill: Skill) {
        skills.insert(skill, at: 0)
        persist()
    }

    func update(_ skill: Skill) {
        guard let index = skills.firstIndex(where: { $0.id == skill.id }) else { return }
        skills[index] = skill
        persist()
    }

    func delete(_ skill: Skill) {
        skills.removeAll { $0.id == skill.id }
        if activeSkillID == skill.id {
            activeSkillID = nil
        }
        persist()
    }

    func setActive(_ skill: Skill?, isActive: Bool) {
        activeSkillID = isActive ? skill?.id : nil
        persist()
    }

    // MARK: - Persistance

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let file = try? decoder.decode(SkillsFile.self, from: data) else { return }
        skills = file.skills
        activeSkillID = file.activeSkillID
    }

    private func persist() {
        let file = SkillsFile(skills: skills, activeSkillID: activeSkillID)
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private struct SkillsFile: Codable {
    var skills: [Skill]
    var activeSkillID: UUID?
}