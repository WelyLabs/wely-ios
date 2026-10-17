import Foundation
import Observation
import SwiftUI

/// Everything the screens share: the services, who is who, the live connections.
@Observable
final class AppModel {
    let session: AuthSession
    let isDemo: Bool

    @ObservationIgnored let api: APIClient
    @ObservationIgnored let events: EventService
    @ObservationIgnored let social: SocialService
    @ObservationIgnored let users: UserService
    @ObservationIgnored let chat: ChatService
    @ObservationIgnored let notificationService: NotificationService

    let people: PeopleStore
    let notifications: NotificationCenterModel
    let chatSocket: ChatSocket
    let calls: CallController
    let push: DevicePush

    /// Bumped after a change elsewhere (an event joined, created...) so lists reload.
    var eventsVersion = 0
    /// A screen to open from outside the tab (a notification, a shared link).
    var pendingDestination: AppDestination?
    var selectedTab: AppTab = .calendar
    /// How many open screens want the tab bar out of the way (a conversation, with its composer).
    var tabBarHiders = 0
    /// The theme kept with the account; this phone's last choice until the account answers.
    var theme = ThemePreference.stored {
        didSet { ThemePreference.stored = theme }
    }

    init(session: AuthSession, http: HTTPTransport = URLSession.shared, isDemo: Bool = false) {
        self.session = session
        self.isDemo = isDemo
        let api = APIClient(session: session, http: http)
        self.api = api
        events = EventService(api: api)
        social = SocialService(api: api)
        users = UserService(api: api)
        chat = ChatService(api: api)
        notificationService = NotificationService(api: api)
        people = PeopleStore(users: users, social: social)
        notifications = NotificationCenterModel(service: notificationService, session: session, live: !isDemo)
        let socket = ChatSocket(session: session, enabled: !isDemo)
        chatSocket = socket
        let people = people
        calls = CallController(service: CallService(api: api), socket: socket, myId: { people.myId })
        push = DevicePush(service: notificationService)
        push.onOpen = { [weak self] destination in self?.open(destination) }
        notifications.onArrival = { [weak self] notification in self?.push.showLocally(notification) }
    }

    /// What signing in starts: who I am, who I know, the notification stream.
    func start() async {
        if let preferences = try? await users.preferences() { theme = preferences.theme }
        await people.loadMe()
        await people.loadDirectory()
        notifications.start()
        if !isDemo {
            calls.listen()
            await push.refresh()
        }
    }

    /// Signs out, after telling wely-notifications to stop pushing this account to this iPhone.
    func signOut() async {
        await push.unregister()
        await session.signOut()
    }

    func stop() {
        notifications.stop()
        calls.stopListening()
        chatSocket.disconnect()
        people.reset()
    }

    func eventsChanged() { eventsVersion += 1 }

    /// Applies the theme at once, then keeps it with the account; a refused save puts the
    /// previous one back and throws for the screen to say so.
    func chooseTheme(_ choice: ThemePreference) async throws {
        let previous = theme
        theme = choice
        do {
            theme = try await users.savePreferences(UserPreferences(theme: choice)).theme
        } catch {
            theme = previous
            throw error
        }
    }

    func open(_ destination: AppDestination) {
        switch destination {
        case .call(let id):
            // A call is not a screen of a tab: it opens over all of them.
            Task { await calls.join(id) }
            return
        case .conversation: selectedTab = .messages
        case .person, .community, .invitation: selectedTab = .social
        case .preferences: selectedTab = .profile
        case .event: break
        }
        pendingDestination = destination
    }

    #if DEBUG
    static func demo() -> AppModel {
        let tokens = TokenSet(accessToken: "demo", refreshToken: nil, idToken: nil, expiresAt: .distantFuture)
        return AppModel(session: AuthSession(store: InMemoryTokenStore(tokens)), http: DemoTransport(), isDemo: true)
    }
    #endif
}

enum AppTab: Hashable, CaseIterable {
    case calendar, feed, messages, social, profile
}

/// Names and pictures by user id, for every screen that only has ids.
@Observable
final class PeopleStore {
    private(set) var me: UserProfile?
    private(set) var directory: [String: Person] = [:]
    private(set) var pictures: [String: URL] = [:]

    @ObservationIgnored private let users: UserService
    @ObservationIgnored private let social: SocialService
    @ObservationIgnored private var requested: Set<String> = []

    init(users: UserService, social: SocialService) {
        self.users = users
        self.social = social
    }

    var myId: String? { me?.id }

    func loadMe() async {
        if let me = try? await users.me() {
            self.me = me
            remember([Person(id: me.id, name: me.userName, hashtag: me.hashtag, pictureURL: me.profilePicUrl)])
        }
    }

    /// Every user the caller can see, with their relation: names for ids.
    func loadDirectory() async {
        guard let users = try? await social.users() else { return }
        remember(users.map(\.person))
    }

    func remember(_ people: [Person]) {
        for person in people {
            directory[person.id] = person
        }
    }

    func setMe(_ profile: UserProfile) {
        me = profile
        remember([Person(id: profile.id, name: profile.userName, hashtag: profile.hashtag, pictureURL: profile.profilePicUrl)])
    }

    func person(_ id: String) -> Person {
        directory[id] ?? Person(id: id, name: id == myId ? (me?.userName ?? "Moi") : "Membre")
    }

    func name(_ id: String) -> String {
        id == myId ? "Vous" : person(id).name
    }

    /// The signed picture of a user, fetched in batches as screens ask for them.
    func picture(_ id: String) -> URL? {
        if let url = pictures[id] { return url }
        if !requested.contains(id) {
            requested.insert(id)
            Task { await fetchPictures() }
        }
        return nil
    }

    func invalidatePicture(_ id: String) {
        pictures.removeValue(forKey: id)
        requested.remove(id)
    }

    func reset() {
        me = nil
        directory = [:]
        pictures = [:]
        requested = []
    }

    private func fetchPictures() async {
        // Let the other avatars on screen join the batch.
        try? await Task.sleep(for: .milliseconds(50))
        let ids = requested.filter { pictures[$0] == nil }
        guard !ids.isEmpty else { return }
        for batch in Array(ids).chunked(into: 50) {
            guard let urls = try? await users.avatars(of: batch) else { continue }
            for (id, url) in urls { pictures[id] = URL(string: url) }
        }
    }
}

/// The notification center: the latest notifications, the unread count, live arrivals.
@Observable
final class NotificationCenterModel {
    private(set) var items: [AppNotification] = []
    private(set) var unread = 0
    private(set) var hasMore = true
    private(set) var isLoading = false
    /// The last notification that arrived live, for a banner.
    var arrival: AppNotification?
    /// Each live arrival, for the system notification shown while the app is in the background.
    @ObservationIgnored var onArrival: ((AppNotification) -> Void)?

    @ObservationIgnored private let service: NotificationService
    @ObservationIgnored private let session: AuthSession
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    init(service: NotificationService, session: AuthSession, live: Bool) {
        self.service = service
        self.session = session
        self.live = live
    }

    func start() {
        Task { await refresh() }
        guard live, streamTask == nil else { return }
        let stream = SSEClient.stream(url: service.streamURL, session: session) { [weak self] in
            Task { await self?.refresh() }
        }
        streamTask = Task {
            for await message in stream { handle(message) }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        items = []
        unread = 0
    }

    func refresh() async {
        if let page = try? await service.page() {
            upsert(page)
            if items.count <= page.count { hasMore = page.count == NotificationService.pageSize }
        }
        if let count = try? await service.unreadCount() { unread = count }
    }

    func loadMore() async {
        guard hasMore, !isLoading, let last = items.last else { return }
        isLoading = true
        defer { isLoading = false }
        if let page = try? await service.page(before: last.createdAt) {
            upsert(page)
            hasMore = page.count == NotificationService.pageSize
        }
    }

    func markRead(_ notification: AppNotification) {
        if let key = notification.groupKey {
            markLocally { $0.groupKey == key }
            Task { try? await service.markRead(NotificationReadRequest(groupKey: key)) }
        } else {
            markLocally { $0.id == notification.id }
            Task { try? await service.markRead(NotificationReadRequest(ids: [notification.id])) }
        }
    }

    func markAllRead() {
        markLocally { _ in true }
        unread = 0
        Task { try? await service.markRead(NotificationReadRequest(all: true)) }
    }

    func handle(_ message: SSEMessage) {
        let data = Data(message.data.utf8)
        switch message.event {
        case "notification":
            guard let notification = try? JSONDecoder.wely.decode(AppNotification.self, from: data) else { return }
            upsert([notification])
            if !notification.isRead {
                arrival = notification
                onArrival?(notification)
            }
        case "unread":
            if let count = try? JSONDecoder.wely.decode(UnreadCount.self, from: data) { unread = count.count }
        default:
            break
        }
    }

    private func upsert(_ page: [AppNotification]) {
        var byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        for item in page { byId[item.id] = item }
        items = byId.values.sorted { $0.createdAt > $1.createdAt }
    }

    private func markLocally(_ matches: (AppNotification) -> Bool) {
        var changed = 0
        items = items.map { item in
            guard !item.isRead, matches(item) else { return item }
            changed += 1
            var read = item
            read.readAt = .now
            return read
        }
        unread = max(0, unread - changed)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
