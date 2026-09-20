//  KarenOS
//  Par Martial Zinsou

import Foundation

enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("KarenOS", isDirectory: true)
    }()

    static let modelsDir: URL = support.appendingPathComponent("Models", isDirectory: true)
    static let engineDir: URL = support.appendingPathComponent("Engine", isDirectory: true)
    static let registryURL: URL = support.appendingPathComponent("models.json")
    static let skillsURL: URL = support.appendingPathComponent("skills.json")
    static let agentsURL: URL = support.appendingPathComponent("agents.json")
    static let serverLogURL: URL = support.appendingPathComponent("server.log")

    static func ensure() {
        for dir in [support, modelsDir, engineDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

enum FileFormat {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}