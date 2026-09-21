// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — ActionRunner.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Exécution de commandes et lancement de logiciels (agent).
//    Dépend. : Foundation
//  --------------------------------------------------------------------
//    Exécute une commande shell / lance un logiciel (via `open`) demandée
//    par un agent, avec lecture complète de stdout/stderr, code de sortie
//    et garde-fou temporel (terminaison au-delà du délai).
//  ====================================================================

@preconcurrency import Foundation
import Foundation

/// Résultat d'une exécution : sortie standard, erreurs et code de sortie.
struct ShellResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

/// Exécute une commande dans le shell de l'utilisateur (`/bin/zsh -lc`).
///
/// - Le shell de connexion est utilisé pour que les commandes « installées »
///   (PATH complet : Homebrew, /usr/local…) soient trouvées.
/// - La sortie est lue à la fois sur stdout et stderr (lus en parallèle pour
///   éviter tout blocage de tuyau).
/// - Après `timeout` secondes, le processus est terminé ; `exitCode` vaut
///   alors 137 (SIGKILL) en pratique.
enum ActionRunner {
    static func run(_ command: String, timeout: TimeInterval = 30) async -> ShellResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ShellResult(
                    stdout: "",
                    stderr: "Impossible de lancer la commande : \(error.localizedDescription)",
                    exitCode: -1
                ))
                return
            }

            DispatchQueue.global().async {
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: ShellResult(
                    stdout: String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    stderr: String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    exitCode: process.terminationStatus
                ))
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}