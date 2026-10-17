import Foundation
import LocalAuthentication
import Observation

/// Proves the phone's owner is holding it: Face ID, Touch ID, or the passcode as a fallback.
protocol OwnerCheck {
    /// "Face ID", "Touch ID", or nil when the phone has neither (the passcode still works).
    var biometryName: String? { get }
    /// Whether the phone can check its owner at all (no passcode set: no).
    var isAvailable: Bool { get }
    func verify(reason: String) async -> Bool
}

/// The system's check, through LocalAuthentication.
struct DeviceOwnerCheck: OwnerCheck {
    var biometryName: String? {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: nil
        }
    }

    var isAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    func verify(reason: String) async -> Bool {
        // deviceOwnerAuthentication: biometrics first, the passcode if they fail or are off.
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Locks Wely behind Face ID when it comes back after a while, the way banking apps do.
///
/// A gate in front of the screens, not around the tokens: the session stays in the Keychain and
/// keeps working in the background (a call answered from the lock screen, notifications), only
/// the screens wait for the owner. The choice belongs to this phone, not to the account.
@Observable
final class AppLock {
    /// How long Wely may stay in the background before asking again.
    static let grace: Duration = .seconds(60)
    static let enabledKey = "wely.appLock.enabled"
    static let offeredKey = "wely.appLock.offered"

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    /// Wely is not on screen: its content is covered, so the app switcher shows nothing.
    private(set) var isHidden = false

    @ObservationIgnored private let check: OwnerCheck
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var leftAt: Date?
    @ObservationIgnored private var verifying = false

    init(check: OwnerCheck = DeviceOwnerCheck(), defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.check = check
        self.defaults = defaults
        self.now = now
        let enabled = defaults.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        // A cold start counts as coming back after a while.
        isLocked = enabled
    }

    /// Proposed once per iPhone, after signing in, when the phone can check its owner.
    var shouldOffer: Bool {
        !isEnabled && check.isAvailable && !defaults.bool(forKey: Self.offeredKey)
    }

    func markOffered() {
        defaults.set(true, forKey: Self.offeredKey)
    }

    /// The screens are behind the lock screen, locked or only out of sight.
    var isCovering: Bool { isEnabled && (isLocked || isHidden) }

    var biometryName: String? { check.biometryName }
    var isAvailable: Bool { check.isAvailable }

    /// Turns the lock on only once the owner proved it works for them.
    @discardableResult
    func enable() async -> Bool {
        guard await check.verify(reason: "Activer le verrouillage de Wely") else { return false }
        isEnabled = true
        defaults.set(true, forKey: Self.enabledKey)
        return true
    }

    func disable() {
        isEnabled = false
        isLocked = false
        defaults.set(false, forKey: Self.enabledKey)
    }

    /// Covered as soon as Wely stops being active: the app switcher, or a system prompt (Face ID's
    /// own included, which is why the timer only starts in the background).
    func didResignActive() {
        isHidden = true
    }

    func didEnterBackground() {
        isHidden = true
        if leftAt == nil { leftAt = now() }
    }

    func didBecomeActive() {
        isHidden = false
        if isEnabled, let leftAt, now().timeIntervalSince(leftAt) >= Double(Self.grace.components.seconds) {
            isLocked = true
        }
        leftAt = nil
    }

    /// Asks for Face ID; the lock stays when it fails or is cancelled.
    func unlock() async {
        guard isLocked, !verifying else { return }
        verifying = true
        defer { verifying = false }
        if await check.verify(reason: "Déverrouiller Wely") { isLocked = false }
    }

    /// Signing out leaves nothing to protect, and the next account starts unlocked.
    func reset() {
        isLocked = false
        leftAt = nil
    }
}
