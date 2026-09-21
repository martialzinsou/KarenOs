//  ====================================================================
//    KarenOS — Errors.swift
//    Application macOS d'IA en local · 100 % Swift/SwiftUI · llama.cpp
//  --------------------------------------------------------------------
//    Auteur  : Martial Zinsou
//    Rôle    : Erreurs applicatives localisées et compréhensibles pour l'utilisateur.
//    Dépend. : Foundation
//  --------------------------------------------------------------------
//    AppError traduit les échecs connus (HTTP 401 = modèle restreint,
//    429 = limite atteinte, autres codes) en messages prêts à afficher
//    dans l'interface via `LocalizedError.errorDescription`.
//  ====================================================================

import Foundation

/// Erreur applicative prête à afficher dans l'interface.
    ///
    /// Les codes HTTP connus (401 modèle restreint, 429 limite de
    /// téléchargements) reçoivent un message explicatif en français.
    enum AppError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            if code == 401 {
                return "Accès refusé (401) : ce modèle est restreint et demande un compte Hugging Face."
            }
            if code == 429 {
                return "Limite de téléchargements atteinte (429). Réessaie dans quelques instants."
            }
            return "Réponse du serveur : \(code)."
        }
    }
}