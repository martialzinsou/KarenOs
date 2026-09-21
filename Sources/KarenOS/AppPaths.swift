//  ====================================================================
//    KarenOS — AppPaths.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Chemins du système et fichiers supports de KarenOS.
//    Dépend. : Foundation
//  --------------------------------------------------------------------
//    Centralise l'emplacement Application Support de l'app
//    (~/Library/Application Support/KarenOS/) et les URLs des fichiers
//    d'état (models.json, skills.json, agents.json, server.log).
//    `ensure()` crée les dossiers au démarrage. Fournit aussi FileFormat.bytes
//    pour l'affichage lisible des tailles de fichiers.
//  ====================================================================

import Foundation

/// Chemins d'accès centraux de KarenOS.
///
/// Le dossier Application Support (`~/Library/Application Support/KarenOS/`)
/// contient les modèles, le moteur et les fichiers d'état du programme.
/// `ensure()` est appelé au démarrage des stores.
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