import Observation
import UIKit
import UserNotifications

/// The iPhone's notifications: the permission, the APNs token wely-notifications pushes to, and
/// a local notification for what arrives live while Wely is in the background.
///
/// APNs needs the `aps-environment` entitlement, which only a paid Apple Developer team can sign:
/// without it, registering fails, `remoteAvailable` turns false, and the user is still told of
/// what arrives while the app runs.
@Observable
final class DevicePush: NSObject {
    enum Permission { case unknown, notDetermined, denied, allowed }

    /// Where the app delegate hands the APNs callbacks.
    nonisolated(unsafe) static weak var current: DevicePush?

    private(set) var permission = Permission.unknown
    /// False once iOS refused to register for remote notifications (no entitlement).
    private(set) var remoteAvailable = true

    @ObservationIgnored private let service: NotificationService
    @ObservationIgnored private var token: String?
    /// Opens what a tapped notification points to.
    @ObservationIgnored var onOpen: ((AppDestination) -> Void)?

    #if DEBUG
    static let environment = ApnsEnvironment.sandbox
    #else
    static let environment = ApnsEnvironment.production
    #endif

    init(service: NotificationService) {
        self.service = service
        super.init()
        Self.current = self
        UNUserNotificationCenter.current().delegate = self
    }

    /// Reads the permission; registers the device at once when it is already granted.
    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permission = switch settings.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed
        }
        if permission == .allowed { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Asks for the permission, on the user's tap.
    func enable() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        permission = granted ? .allowed : .denied
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Stops this iPhone receiving the account's pushes, before signing out.
    func unregister() async {
        guard let token else { return }
        try? await service.unregisterDevice(token: token)
        self.token = nil
    }

    func didRegister(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.token = token
        remoteAvailable = true
        Task { try? await service.registerDevice(ApnsDeviceRequest(token: token, environment: Self.environment)) }
    }

    func didFailToRegister() {
        remoteAvailable = false
    }

    /// A notification that arrived on the live stream while Wely is not on screen.
    func showLocally(_ notification: AppNotification) {
        guard permission == .allowed, UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.groupKey ?? notification.type
        if let link = notification.link { content.userInfo = ["link": link] }
        // The same group replaces its previous one, as the push would.
        let id = notification.groupKey.map { "\(notification.type)-\($0)" } ?? notification.id
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

extension DevicePush: UNUserNotificationCenterDelegate {
    /// On screen, the in-app banner already tells: nothing from the system.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let link = response.notification.request.content.userInfo["link"] as? String else { return }
        await MainActor.run {
            if let destination = AppDestination(webPath: link) { onOpen?(destination) }
        }
    }
}

/// Hands iOS's APNs registration callbacks to `DevicePush`.
final class WelyAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        DevicePush.current?.didRegister(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DevicePush.current?.didFailToRegister()
    }
}
