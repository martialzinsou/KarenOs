import Foundation

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