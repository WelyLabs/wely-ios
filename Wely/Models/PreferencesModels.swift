import SwiftUI

/// The theme a user picks, kept with the account by wely-users (`/profile/preferences`) so it
/// follows them from the web to the phone.
enum ThemePreference: String, Codable, CaseIterable, Sendable {
    case light = "LIGHT"
    case dark = "DARK"
    case system = "SYSTEM"

    /// Unknown values from a newer backend read as the default.
    init(from decoder: Decoder) throws {
        self = ThemePreference(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .system
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    var label: String {
        switch self {
        case .light: "Clair"
        case .dark: "Sombre"
        case .system: "Système"
        }
    }

    var systemImage: String {
        switch self {
        case .light: "sun.max"
        case .dark: "moon"
        case .system: "circle.lefthalf.filled"
        }
    }

    /// The last theme chosen on this phone, so the app opens in it before the account answers.
    static var stored: ThemePreference {
        get { UserDefaults.standard.string(forKey: "wely.theme").flatMap(ThemePreference.init(rawValue:)) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "wely.theme") }
    }
}

struct UserPreferences: Codable, Hashable, Sendable {
    var theme: ThemePreference
}

struct DeletionEligibility: Codable, Sendable {
    let allowed: Bool
}

/// How asking wely-users to delete the account ended.
enum AccountDeletionOutcome: Equatable {
    case deleted
    /// The sign-in is older than five minutes: sign in again, then retry.
    case reauthenticationRequired
    /// A demo account, which cannot be deleted.
    case protected
    /// Switched off on this deployment.
    case unavailable
    case failed(String)

    /// What a refused `DELETE /profile` means. A 410 USR-BUS-012 is an account already gone.
    init(refusal error: Error) {
        let api = error as? APIError
        switch (api?.status, api?.code) {
        case (410, "USR-BUS-012"): self = .deleted
        case (403, "USR-BUS-011"): self = .protected
        case (403, "USR-BUS-014"): self = .unavailable
        case (403, "USR-BUS-010"): self = .reauthenticationRequired
        default: self = .failed("La suppression n'a pas abouti. Réessayez dans un instant.")
        }
    }

    /// What deleting the account does, as wely-web lists it.
    static let consequences = [
        "Votre profil, votre photo, vos amis, vos notifications et vos réglages sont effacés. Votre pseudo ne sera jamais réattribué.",
        "Vos messages et les photos envoyées restent visibles dans les discussions, signés « Utilisateur supprimé ».",
        "Vos conversations privées restent lisibles par l'autre personne, mais plus personne ne pourra y écrire.",
        "Les événements que vous organisez passent au participant inscrit depuis le plus longtemps ; ceux dont vous êtes le seul participant sont supprimés.",
        "Vous quittez les événements à venir et vos votes sur les sondages en cours sont retirés.",
        "Les dépenses restent dans les comptes de leurs événements, sans vos justificatifs.",
        "Dans vos communautés, un autre membre devient administrateur ; une communauté dont vous êtes le seul membre est supprimée.",
    ]
}
