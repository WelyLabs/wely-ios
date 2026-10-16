import Foundation

/// The backend's business codes worth a sentence of their own, as wely-web words them.
nonisolated enum ErrorMessages {
    static func text(for code: String) -> String? {
        switch code {
        case "SCL-BUS-010": "Cette communauté n'existe pas ou n'est pas visible pour vous."
        case "SCL-BUS-011": "Seuls les administrateurs de la communauté peuvent faire cela."
        case "SCL-BUS-012": "Le nom doit faire 3 à 60 caractères, la description 500 au plus, et 5 centres d'intérêt au maximum."
        case "SCL-BUS-013": "Cette invitation n'existe pas, a déjà été utilisée ou révoquée, ou ne vous est pas destinée."
        case "SCL-BUS-014": "Cette invitation a expiré : elle était valable 3 jours. Demandez-en une nouvelle à un administrateur."
        case "SCL-BUS-015": "Vous ne pouvez inviter que vos amis qui ne sont pas encore membres."
        case "SCL-BUS-016": "Vous êtes le seul membre : quitter la communauté la supprimera."
        case "SCL-BUS-017": "La communauté doit garder au moins un administrateur : nommez-en un autre d'abord."
        case "SCL-BUS-018": "Cette personne n'est pas membre de la communauté."
        case "SCL-BUS-019": "Réservé aux membres : rejoignez la communauté pour voir son contenu."
        case "EVT-BUS-024": "Seuls les membres de la communauté peuvent voir et publier ses événements."
        case "USR-BUS-010": "Pour supprimer votre compte, confirmez d'abord votre mot de passe."
        case "USR-BUS-011": "Le compte de démonstration ne peut pas être supprimé."
        case "USR-BUS-014": "La suppression du compte est indisponible pour le moment."
        case "CHT-BUS-007": "Cette photo ne peut plus être retirée."
        default: nil
        }
    }
}
