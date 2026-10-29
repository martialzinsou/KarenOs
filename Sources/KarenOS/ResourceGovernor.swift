// KarenOS — auteur : Martial Zinsou
//  ====================================================================
//    KarenOS — ResourceGovernor.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Verrou de ressources pendant l'inférence et la restitution.
//    Dépend. : Foundation
//  --------------------------------------------------------------------
//    De l'envoi du prompt jusqu'au dernier fragment affiché, KarenOS :
//    - interdit la mise en veille du système et de l'écran ;
//    - empêche App Nap de ralentir le processus ;
//    - signale à macOS une activité utilisateur critique ;
//    - maintient un compteur pour les générations simultanées (chat + agent).
//    Les limites matérielles (GPU, Neural Engine) sont documentées dans
//    EngineManager : le backend llama.cpp décide de ce qui est réellement
//    exploitable.
//  ====================================================================

import Foundation

/// Gouverneur des ressources de la machine pendant une génération.
///
/// Le moteur `llama-server` est lancé avec tous les cœurs CPU, une priorité
/// haute et le modèle verrouillé en RAM (voir `EngineManager`). Ce gouverneur
/// couvre la seconde moitié du contrat : tant qu'une inférence est en cours,
/// macOS ne doit ni endormir la machine, ni geler l'application, ni réduire
/// sa priorité d'ordonnancement.
@MainActor
final class ResourceGovernor: ObservableObject {
    static let shared = ResourceGovernor()

    /// `true` entre le début de l'inférence et la fin de la restitution.
    @Published private(set) var isActive = false
    /// Horodatage du début de la génération en cours (nil si inactive).
    @Published private(set) var startedAt: Date?

    private var activity: NSObjectProtocol?
    private var depth = 0

    /// Nombre de cœurs logiques que le moteur est autorisé à utiliser.
    var cpuCount: Int { ProcessInfo.processInfo.activeProcessorCount }

    /// Mémoire physique de la machine, arrondie au Go.
    var memoryGB: Int {
        max(1, Int(Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0))
    }

    /// Prend le verrou de performance. Les appels imbriqués sont comptés :
    /// le verrou n'est réellement posé qu'au premier `begin` et relâché
    /// qu'au dernier `end`.
    func begin() {
        depth += 1
        guard depth == 1 else { return }

        isActive = true
        startedAt = Date()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: "KarenOS — inférence locale à pleine puissance"
        )
    }

    /// Relâche le verrou. Sans effet si aucun verrou n'est posé.
    func end() {
        guard depth > 0 else { return }
        depth -= 1
        guard depth == 0 else { return }

        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        startedAt = nil
        isActive = false
    }
}
