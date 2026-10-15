import SwiftUI

/// Every screen one can push from anywhere.
enum Route: Hashable {
    case event(FeedEvent)
    case eventId(String)
    case person(String)
    case community(String)
    case conversation(String)
    case directChat(friendId: String)
    case eventChat(eventId: String, title: String)
    case expenses(FeedEvent)
    case invitation(String)
    case notifications

    init(_ destination: AppDestination) {
        switch destination {
        case .event(let id): self = .eventId(id)
        case .conversation(let id): self = .conversation(id)
        case .person(let id): self = .person(id)
        case .community(let id): self = .community(id)
        case .invitation(let token): self = .invitation(token)
        }
    }
}

extension View {
    /// Registers every `Route` on a navigation stack.
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .event(let event): EventDetailView(eventId: event.id, initial: event)
            case .eventId(let id): EventDetailView(eventId: id, initial: nil)
            case .person(let id): PersonView(userId: id)
            case .community(let id): CommunityDetailView(communityId: id)
            case .conversation(let id): ChatView(target: .conversation(id))
            case .directChat(let friendId): ChatView(target: .friend(friendId))
            case .eventChat(let eventId, let title): ChatView(target: .event(eventId, title: title))
            case .expenses(let event): ExpensesView(event: event)
            case .invitation(let token): InvitationView(token: token)
            case .notifications: NotificationsView()
            }
        }
    }

    /// A bell with the unread count, opening the notification center.
    func notificationsToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) { NotificationBell() }
        }
    }
}

struct NotificationBell: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationLink(value: Route.notifications) {
            Image(systemName: app.notifications.unread > 0 ? "bell.badge" : "bell")
                .symbolRenderingMode(app.notifications.unread > 0 ? .multicolor : .monochrome)
        }
        .accessibilityLabel(app.notifications.unread > 0 ? "Notifications, \(app.notifications.unread) non lues" : "Notifications")
    }
}

/// Opens the screen a notification or a link asked for, on this tab's stack.
struct PendingDestinationHandler: ViewModifier {
    @Environment(AppModel.self) private var app
    let tab: AppTab
    @Binding var path: NavigationPath

    func body(content: Content) -> some View {
        content.onChange(of: app.pendingDestination, initial: true) { _, destination in
            guard let destination, app.selectedTab == tab else { return }
            path.append(Route(destination))
            app.pendingDestination = nil
        }
    }
}

extension View {
    func handlesDestinations(on tab: AppTab, path: Binding<NavigationPath>) -> some View {
        modifier(PendingDestinationHandler(tab: tab, path: path))
    }
}
