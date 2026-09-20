import Foundation
import SwiftUI

struct Skill: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var instructions: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, icon: String = "sparkles", instructions: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self.instructions = instructions
        self.createdAt = Date()
    }

    var systemPrompt: String {
        instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var iconSymbol: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "sparkles" : trimmed
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