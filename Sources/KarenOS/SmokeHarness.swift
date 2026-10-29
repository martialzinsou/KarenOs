// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — SmokeHarness.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Test de bout en bout du moteur, sans interaction humaine.
//    Dépend. : Foundation, AppKit
//  --------------------------------------------------------------------
//    Outil de développement, inactif par défaut. Si `KARENOS_SMOKE_MODEL`
//    contient l'identifiant d'un modèle installé, l'app :
//      1. charge ce modèle via le vrai `EngineManager` (donc le moteur
//         embarqué s'il est présent) ;
//      2. envoie un prompt via le vrai `ChatService` ;
//      3. écrit un rapport (chemin du binaire, chargement, réponse, durée)
//         dans `KARENOS_SMOKE_OUT`, puis quitte.
//    Aucun effet en usage normal.
//  ====================================================================

import AppKit
import Foundation

@MainActor
enum SmokeHarness {
    static func startIfRequested(engine: EngineManager, store: ModelStore) {
        guard let wanted = ProcessInfo.processInfo.environment["KARENOS_SMOKE_MODEL"],
              !wanted.isEmpty else { return }

        let reportURL = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["KARENOS_SMOKE_OUT"]
                ?? NSTemporaryDirectory() + "karenos-smoke.txt"
        )
        var report = "KarenOS — smoke test\n"

        Task {
            defer {
                try? report.write(to: reportURL, atomically: true, encoding: .utf8)
                print("[smoke] rapport : \(reportURL.path)")
                NSApp.terminate(nil)
            }

            guard let model = store.installedModel(id: wanted)
                ?? store.installed.first(where: { $0.id.localizedCaseInsensitiveContains(wanted) })
                ?? store.installed.first(where: { $0.friendlyName.localizedCaseInsensitiveContains(wanted) }) else {
                report += "ÉCHEC : modèle introuvable (\(wanted))\n"
                return
            }

            report += "modèle          : \(model.id) — \(model.fileName)\n"
            report += "moteur          : \(engine.engineExe.path)\n"

            let loadStart = Date()
            let loaded = await engine.load(model: model)
            report += "chargement      : \(loaded ? "OK" : "ÉCHEC") en \(Self.seconds(since: loadStart))\n"
            report += "état            : \(engine.state)\n"
            guard loaded, let baseURL = engine.chatURL else {
                report += "ÉCHEC : moteur non disponible\n"
                return
            }

            let history = [
                ChatMessage.system("Tu es KarenOS, un assistant local concis."),
                ChatMessage.user("Dis bonjour en une phrase courte.")
            ]
            var answer = ""
            let chatStart = Date()
            var firstChunk: Date?
            do {
                for try await piece in ChatService.streamReply(history, baseURL: baseURL, vision: engine.hasVision) {
                    if firstChunk == nil { firstChunk = Date() }
                    answer += piece
                }
            } catch {
                report += "ÉCHEC du flux  : \(error.localizedDescription)\n"
                return
            }
            let ttft = firstChunk.map { String(format: "%.2f s", $0.timeIntervalSince(chatStart)) } ?? "—"
            report += "premier fragment: \(ttft)\n"
            report += "durée totale    : \(Self.seconds(since: chatStart))\n"
            report += "réponse         : \(answer)\n"

            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                report += "ÉCHEC : réponse vide\n"
            } else if trimmed.count <= 3 || trimmed.hasSuffix("C'est") || trimmed.hasSuffix("c'est") {
                report += "ÉCHEC : réponse tronquée (bug de streaming)\n"
            } else {
                report += "RÉSULTAT        : OK\n"
            }
        }
    }

    private static func seconds(since date: Date) -> String {
        String(format: "%.2f s", Date().timeIntervalSince(date))
    }
}
