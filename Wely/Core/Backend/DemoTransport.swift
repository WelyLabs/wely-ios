#if DEBUG
import Foundation

/// A pretend gateway, in memory: answers the routes the app calls with sample data around
/// today, and keeps what the user changes for the session. `-WelyDemo` and the previews.
final class DemoTransport: HTTPTransport, @unchecked Sendable {
    private var store = DemoStore()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try? await Task.sleep(for: .milliseconds(150))
        let url = request.url!
        let path = url.path().components(separatedBy: "/api/v1/").last ?? ""
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let body = request.httpBody ?? Data()
        let (status, payload) = store.handle(method: request.httpMethod ?? "GET", path: path, query: query, body: body)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        return (payload, response)
    }
}

/// The demo's data and the little logic that keeps it consistent.
struct DemoStore {
    static let me = "demo-me"
    private let calendar = Calendar.wely
    private let now = Date.now

    var people: [String: (name: String, first: String, last: String, tag: String)] = [
        "demo-me": ("robin", "Robin", "Leblanc", "4907"),
        "lea": ("lea", "Léa", "Martin", "1203"),
        "hugo": ("hugo", "Hugo", "Bernard", "5521"),
        "ines": ("ines", "Inès", "Dubois", "8830"),
        "lucas": ("lucas", "Lucas", "Moreau", "2290"),
        "sarah": ("sarah", "Sarah", "Laurent", "7712"),
        "nathan": ("nathan", "Nathan", "Simon", "3345"),
        "jules": ("jules", "Jules", "Michel", "6107"),
        "camille": ("camille", "Camille", "Garcia", "9001"),
    ]
    var friends: [String: Closeness] = ["lea": .intimate, "hugo": .close, "ines": .close, "lucas": .friend, "sarah": .friend, "nathan": .friend]
    var incoming: Set<String> = ["jules"]
    var outgoing: Set<String> = []
    var events: [FeedEvent] = []
    var joined: Set<String> = []
    var participants: [String: [String]] = [:]
    /// Pending invitations, by event.
    var invited: [String: [String]] = [:]
    var communities: [Community] = []
    var memberships: [String: CommunityRole] = ["club-auto": .member]
    var conversations: [Conversation] = []
    var notifications: [AppNotification] = []
    var expenses: [String: [Expense]] = [:]
    var preferences = UserPreferences(theme: .system)
    var about = ProfileAbout(bio: "Toujours partant pour une sortie 🚲", interests: ["Escalade", "Jeux de société", "Cinéma"])
    /// Birthdays by user, in days from today: the user's own is today, to show the celebration.
    var birthdays: [String: MonthDay] = [:]
    var myBirthYear = 1996
    var notificationPreferences = NotificationPreferences(calls: true, messages: true, events: true, friends: true, birthdays: true)
    /// Friends put off from « Ça fait longtemps ».
    var dismissedReunions: Set<String> = []

    init() {
        events = [
            event("demo-1", "Afterwork au Ninkasi", by: Self.me, day: 0, 19, 22, "Ninkasi Gerland, Lyon", lat: 45.7325, lon: 4.8335,
                  description: "On se retrouve après le boulot, première tournée pour moi !", image: nil),
            event("demo-2", "Escalade à Climb Up", by: "lea", day: 2, 18, 20, "Climb Up Lyon Gerland", lat: 45.7301, lon: 4.8281,
                  description: "Séance bloc, prêt de chaussons possible."),
            event("demo-3", "Brunch du dimanche", by: "hugo", day: 4, 11, 14, "Café Mokxa, Lyon 1er", lat: 45.7676, lon: 4.8344, visibility: .private),
            event("demo-4", "Rallye Club Auto Rétro", by: "sarah", day: 9, 9, 17, "Place Bellecour, Lyon", lat: 45.7578, lon: 4.8320,
                  visibility: .community, community: "club-auto"),
            FeedEvent(id: "demo-5", title: "Soirée jeux", organizerId: Self.me, startDate: at(6, 20), endDate: at(6, 23), location: "Chez Robin",
                      description: "Ramenez vos jeux préférés !",
                      poll: Poll(status: .open, slots: [
                        PollSlot(id: "slot-a", start: at(6, 20), end: at(6, 23), yes: ["lea", "hugo"]),
                        PollSlot(id: "slot-b", start: at(7, 20), end: at(7, 23), yes: ["ines"], maybe: ["lea"]),
                      ])),
            event("demo-6", "Ciné : avant-première", by: "ines", day: -3, 20, 22, "Pathé Bellecour", lat: 45.7590, lon: 4.8340),
            event("demo-7", "Rando au Mont Pilat", by: "lucas", day: 12, 8, 18, "Crêt de la Perdrix", lat: 45.3594, lon: 4.5656,
                  visibility: .public, description: "15 km, prévoir le pique-nique."),
            event("demo-8", "Concert à la Halle Tony Garnier", by: "nathan", day: 15, 20, 23, "Halle Tony Garnier", lat: 45.7317, lon: 4.8215,
                  visibility: .public),
            event("demo-9", "Pique-nique au Parc de la Tête d'Or", by: "camille", day: 5, 12, 15, "Parc de la Tête d'Or", lat: 45.7772, lon: 4.8553,
                  visibility: .public),
            event("demo-10", "Week-end à Annecy", by: "lea", day: -20, 9, 18, "Annecy", lat: 45.8992, lon: 6.1294),
            FeedEvent(id: "demo-11", title: "Fête des Lumières", organizerId: "lea", startDate: AllDay.start(of: at(7, 12), calendar: calendar),
                      endDate: AllDay.start(of: at(9, 12), calendar: calendar), location: "Presqu'île, Lyon",
                      description: "Deux soirs de balade entre les installations.", allDay: true),
            FeedEvent(id: "demo-surprise", title: "Anniversaire surprise de Hugo 🎉", organizerId: "ines", startDate: at(9, 19), endDate: at(9, 23),
                      description: "🤫 Hugo ne voit pas cet événement. Invite ses amis et choisis le lieu.", kind: .surprise, honoreeId: "hugo"),
        ]
        joined = ["demo-1", "demo-2", "demo-3", "demo-4", "demo-5", "demo-6", "demo-10", "demo-11"]
        birthdays = [Self.me: 0, "lucas": 2, "lea": 5, "hugo": 9, "ines": 16, "sarah": 23].mapValues(monthDay)
        participants = [
            "demo-1": [Self.me, "lea", "hugo", "lucas"], "demo-2": ["lea", Self.me, "ines"], "demo-3": ["hugo", Self.me, "lea", "sarah"],
            "demo-4": ["sarah", Self.me, "nathan"], "demo-5": [Self.me, "lea", "hugo", "ines"], "demo-6": ["ines", Self.me],
            "demo-7": ["lucas", "nathan"], "demo-8": ["nathan", "hugo"], "demo-9": ["camille"], "demo-10": ["lea", Self.me, "hugo"],
            "demo-11": ["lea", Self.me], "demo-surprise": ["ines", "lea"],
        ]
        communities = [
            Community(communityId: "club-auto", name: "Club Auto Rétro Lyon", description: "Passionnés de voitures anciennes : rallyes, expos et balades.",
                      interests: ["Voitures", "Mécanique"], visibility: .public, createdAt: at(-90, 10), memberCount: 42, role: .member,
                      friendMembers: [node("sarah"), node("nathan")], friendMemberCount: 2),
            Community(communityId: "copains", name: "Les copains d'abord", description: "Le groupe des sorties entre potes.",
                      interests: ["Sorties"], visibility: .private, createdAt: at(-30, 10), memberCount: 8, role: nil,
                      friendMembers: [node("lea"), node("hugo")], friendMemberCount: 2),
            Community(communityId: "grimpe", name: "Grimpeurs lyonnais", description: "Bloc, voie, falaise : on grimpe ensemble.",
                      interests: ["Escalade", "Montagne"], visibility: .public, createdAt: at(-200, 10), memberCount: 128, role: nil,
                      friendMembers: [node("lea")], friendMemberCount: 1),
        ]
        conversations = [
            conversation("conv-lea", .direct, with: ["lea"], messages: [
                ("lea", "Tu viens à l'escalade jeudi ?", -120), (Self.me, "Carrément ! Je prends mes chaussons", -110), ("lea", "Top, à jeudi 🧗", -100),
            ]),
            conversation("conv-demo-1", .event, with: ["lea", "hugo", "lucas"], title: "Afterwork au Ninkasi", eventId: "demo-1", messages: [
                ("hugo", "J'arrive vers 19h15", -50), ("lucas", "Je réserve une table ?", -40), (Self.me, "Oui stp, pour 4 !", -30),
            ]),
            conversation("conv-hugo", .direct, with: ["hugo"], messages: [("hugo", "Merci pour hier soir !", -1500)]),
        ]
        notifications = [
            AppNotification(id: "n1", type: "FRIEND_REQUEST", category: "FRIENDS", title: "Jules vous a envoyé une demande d'ami", body: "Acceptez-la pour voir ses sorties.",
                            link: "/friends/jules", groupKey: nil, count: 1, actorId: "jules", createdAt: now.addingTimeInterval(-600), readAt: nil),
            AppNotification(id: "n2", type: "MESSAGE", category: "MESSAGES", title: "Lucas dans Afterwork au Ninkasi", body: "Je réserve une table ?",
                            link: "/chat/conv-demo-1", groupKey: "msg-conv-demo-1", count: 2, actorId: "lucas", createdAt: now.addingTimeInterval(-2400), readAt: nil),
            AppNotification(id: "n3", type: "EVENT_DATE_FIXED", category: "EVENTS", title: "Brunch du dimanche : date fixée", body: "Hugo a choisi dimanche 11:00.",
                            link: "/event/demo-3", groupKey: nil, count: 1, actorId: "hugo", createdAt: now.addingTimeInterval(-90_000), readAt: now),
            AppNotification(id: "n4", type: "BIRTHDAY_SURPRISE_PROPOSAL", category: "BIRTHDAYS", title: "🤫 L'anniversaire de Léa approche",
                            body: "Dans 5 jours. Organise une surprise : tout est déjà prêt, il ne reste qu'à créer.",
                            link: "/calendar?surpriseFor=lea&date=\(DayString.string(from: at(5, 12), calendar: calendar))", groupKey: "birthday-lea",
                            count: 1, actorId: "lea", createdAt: now.addingTimeInterval(-1200), readAt: nil),
            AppNotification(id: "n5", type: "BIRTHDAY_SURPRISE_CREATED", category: "BIRTHDAYS", title: "🤫 Inès organise l'anniversaire surprise de Hugo",
                            body: "Rejoins la fête, Hugo ne voit rien.", link: "/event/demo-surprise", groupKey: "birthday-hugo",
                            count: 1, actorId: "ines", createdAt: now.addingTimeInterval(-7200), readAt: nil),
            AppNotification(id: "n6", type: "FRIENDSHIP_ANNIVERSARY", category: "FRIENDS", title: "💛 1 an d'amitié avec Léa",
                            body: "Revivez vos souvenirs ensemble.", link: "/friends/lea/memories", groupKey: "friendship-lea-1",
                            count: 1, actorId: "lea", createdAt: now.addingTimeInterval(-300), readAt: nil),
            AppNotification(id: "n7", type: "REUNION_NUDGE", category: "FRIENDS", title: "💭 Ça fait un moment, Hugo",
                            body: "Vous ne vous êtes pas vus depuis 4 mois. Et si tu proposais une sortie ?", link: "/friends/hugo?propose=1",
                            groupKey: "reunion-hugo", count: 1, actorId: "hugo", createdAt: now.addingTimeInterval(-3600), readAt: nil),
            AppNotification(id: "n8", type: "CLOSENESS_UPGRADED", category: "FRIENDS", title: "🧡 Inès et toi êtes maintenant proches",
                            body: "Vous partagez désormais un peu plus.", link: "/friends/ines", groupKey: nil,
                            count: 1, actorId: "ines", createdAt: now.addingTimeInterval(-86_400), readAt: now),
        ]
        expenses = [
            "demo-10": [
                Expense(id: "x1", title: "Location du chalet", amountCents: 36000, currency: "EUR", paidBy: "lea", createdBy: "lea", kind: "EXPENSE",
                        split: .equal, shares: [], owedCents: ["lea": 12000, Self.me: 12000, "hugo": 12000], spentAt: at(-20, 10), version: 1, receiptUrl: nil),
                Expense(id: "x2", title: "Courses", amountCents: 8450, currency: "EUR", paidBy: Self.me, createdBy: Self.me, kind: "EXPENSE",
                        split: .equal, shares: [], owedCents: ["lea": 2817, Self.me: 2817, "hugo": 2816], spentAt: at(-20, 12), version: 1, receiptUrl: nil),
            ],
        ]
    }

    // MARK: Routing

    mutating func handle(method: String, path: String, query: [String: String], body: Data) -> (Int, Data) {
        let p = path.split(separator: "/").map(String.init)
        switch (method, p.count > 0 ? p[0] : "", Array(p.dropFirst())) {
        // users
        case ("GET", "user-service", ["profile"]): return ok(profile(Self.me))
        case ("PUT", "user-service", ["profile"]):
            if let update = decode(ProfileUpdate.self, body) {
                people[Self.me] = (update.userName, update.firstName, update.lastName, people[Self.me]!.tag)
            }
            return ok(profile(Self.me))
        case ("PUT", "user-service", ["profile", "registration"]):
            guard let request = decode(RegistrationRequest.self, body), let day = DayString.date(from: request.birthDate, calendar: calendar) else {
                return (400, json(["code": "USR-VAL-001"]))
            }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            myBirthYear = parts.year ?? myBirthYear
            birthdays[Self.me] = MonthDay(month: parts.month ?? 1, day: parts.day ?? 1)
            return ok(profile(Self.me))
        case ("GET", "user-service", ["profile", "preferences"]): return ok(preferences)
        case ("PUT", "user-service", ["profile", "preferences"]):
            if let update = decode(UserPreferences.self, body) { preferences = update }
            return ok(preferences)
        // The demo account is protected, as on the web.
        case ("GET", "user-service", ["profile", "deletion"]): return ok(DeletionEligibility(allowed: false))
        case ("DELETE", "user-service", ["profile"]): return (403, json(["code": "USR-BUS-011"]))
        case ("GET", "user-service", ["profile", "about"]): return ok(about)
        case ("PUT", "user-service", ["profile", "about"]):
            if let value = decode(ProfileAbout.self, body) { about = value }
            return ok(about)
        case ("POST", "user-service", ["profile", "picture"]): return ok(["profilePicUrl": nil as String?])
        case ("GET", "user-service", let r) where r.count == 3 && r[0] == "users":
            let id = r[1], person = people[id]
            return ok(FriendProfile(id: id, userName: person?.name ?? id, hashtag: person?.tag ?? "", firstName: person?.first, lastName: person?.last,
                                    joinedDate: "2025-03-01", bio: id == "lea" ? "Grimpeuse du dimanche 🧗" : nil, interests: id == "lea" ? ["Escalade", "Voyages"] : [],
                                    birthday: friends[id] != nil ? birthdays[id] : nil))
        case ("POST", "user-service", ["avatars"]): return ok([String: String]())

        // social
        case ("GET", "social-service", ["users"]):
            if query["friendshipStatus"] == "FRIENDS" { return ok(friends.keys.sorted().map(node)) }
            return ok(people.keys.filter { $0 != Self.me }.sorted().map(withStatus))
        case ("GET", "social-service", let r) where r.count == 3 && r[0] == "users" && r[2] == "mutual":
            return ok(Array(friends.keys.sorted().filter { $0 != r[1] }.prefix(2)).map(node))
        case ("GET", "social-service", let r) where r.count == 2 && r[0] == "users": return ok(socialPerson(r[1]))
        case ("GET", "social-service", ["relationships"]):
            return ok(friends.sorted { $0.key < $1.key }.map { id, closeness in
                FriendSummary(userId: id, userName: people[id]!.name, hashtag: people[id]!.tag, profilePicUrl: nil, closeness: closeness,
                              proposal: id == "hugo" ? .intimate : nil, proposedByFriend: id == "hugo")
            })
        case ("POST", "social-service", ["relationships", "request"]):
            let tag = decode([String: String].self, body)?["userTag"] ?? ""
            guard let id = people.first(where: { "\($0.value.name)#\($0.value.tag)".lowercased() == tag.lowercased() })?.key else {
                return (404, json(["code": "SCL-BUS-002", "message": "Aucun utilisateur avec ce tag."]))
            }
            outgoing.insert(id)
            return ok(node(id))
        case ("PUT", "social-service", let r) where r.count == 3 && r[0] == "relationships" && r[1] == "accept":
            incoming.remove(r[2]); friends[r[2]] = .friend
            return (204, Data())
        case ("PUT", "social-service", let r) where r.count == 3 && r[0] == "relationships" && r[1] == "reject":
            incoming.remove(r[2])
            return (204, Data())
        case ("DELETE", "social-service", let r) where r.count == 2 && r[0] == "relationships":
            friends.removeValue(forKey: r[1]); outgoing.remove(r[1])
            return (204, Data())
        case ("PUT", "social-service", let r) where r.count >= 3 && r[0] == "relationships" && r[2] == "closeness":
            let id = r[1]
            if r.count == 4, r[3] == "accept" { friends[id] = .intimate }
            if r.count == 3, let wanted = decode(ClosenessRequest.self, body)?.closeness, wanted < friends[id, default: .friend] { friends[id] = wanted }
            return ok(Friendship(friendId: id, closeness: friends[id, default: .friend], proposal: nil, proposedByFriend: false))

        // communities
        case ("GET", "social-service", ["communities"]):
            let q = (query["q"] ?? "").lowercased()
            return ok(communities.map(withRole).filter { $0.visibility == .public && (q.isEmpty || $0.name.lowercased().contains(q)) })
        case ("GET", "social-service", ["communities", "mine"]): return ok(communities.map(withRole).filter(\.isMember))
        case ("POST", "social-service", ["communities"]):
            guard let request = decode(CommunityRequest.self, body) else { return (400, Data()) }
            let id = "c-\(UUID().uuidString.prefix(6))"
            communities.append(Community(communityId: id, name: request.name, description: request.description, interests: request.interests,
                                         visibility: request.visibility, createdAt: now, memberCount: 1, role: .admin, friendMembers: [], friendMemberCount: 0))
            memberships[id] = .admin
            return ok(withRole(communities.last!))
        case ("GET", "social-service", let r) where r.count == 2 && r[0] == "communities":
            guard let community = communities.first(where: { $0.communityId == r[1] }) else { return (404, Data()) }
            return ok(withRole(community))
        case ("POST", "social-service", let r) where r.count == 3 && r[0] == "communities" && r[2] == "join":
            memberships[r[1]] = .member
            return ok(withRole(communities.first { $0.communityId == r[1] }!))
        case ("POST", "social-service", let r) where r.count == 3 && r[0] == "communities" && r[2] == "leave":
            memberships.removeValue(forKey: r[1])
            return ok(CommunityLeaveResult(communityDeleted: false, newAdminId: nil))
        case ("POST", "social-service", let r) where r.count == 3 && r[0] == "communities" && r[2] == "picture":
            guard memberships[r[1]] == .admin else { return (403, json(["code": "SCL-BUS-011"])) }
            guard let index = communities.firstIndex(where: { $0.communityId == r[1] }), let jpeg = Self.uploadedFile(in: body) else {
                return (400, json(["code": "SCL-BUS-020"]))
            }
            // Kept on disk, so AsyncImage loads it as it would a signed URL.
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("demo-community-\(r[1])-\(UUID().uuidString).jpg")
            guard (try? jpeg.write(to: file)) != nil else { return (502, json(["code": "SCL-TEC-004"])) }
            communities[index].pictureUrl = file.absoluteString
            return ok(withRole(communities[index]))
        case ("DELETE", "social-service", let r) where r.count == 3 && r[0] == "communities" && r[2] == "picture":
            guard memberships[r[1]] == .admin else { return (403, json(["code": "SCL-BUS-011"])) }
            guard let index = communities.firstIndex(where: { $0.communityId == r[1] }) else { return (404, Data()) }
            communities[index].pictureUrl = nil
            return ok(withRole(communities[index]))
        case ("GET", "social-service", let r) where r.count == 3 && r[0] == "communities" && r[2] == "members":
            var members = [CommunityMember(userId: "sarah", userName: "sarah", hashtag: "7712", profilePicUrl: nil, role: .admin, joinedAt: at(-90, 10)),
                           CommunityMember(userId: "nathan", userName: "nathan", hashtag: "3345", profilePicUrl: nil, role: .member, joinedAt: at(-60, 10))]
            if let role = memberships[r[1]] {
                members.append(CommunityMember(userId: Self.me, userName: "robin", hashtag: "4907", profilePicUrl: nil, role: role, joinedAt: at(-10, 10)))
            }
            return ok(members)
        case ("GET", "social-service", let r) where r.count == 3 && r[0] == "communities" && r[2] == "invitations": return ok([CommunityInvitation]())
        case ("POST", "social-service", let r) where r.count == 3 && r[0] == "communities" && r[2] == "invitations":
            let invitee = decode([String: String].self, body)?["inviteeId"] ?? ""
            return ok(CommunityInvitation(token: "demo-token-0123456789", communityId: r[1], communityName: "", visibility: .private, inviterId: Self.me,
                                          inviterName: "robin", inviteeId: invitee, inviteeName: people[invitee]?.name, createdAt: now,
                                          expiresAt: now.addingTimeInterval(3 * 86_400), expired: false))

        // events
        case ("GET", "events-service", ["events", "me", "subscribed"]): return ok(events.filter { joined.contains($0.id) })
        case ("GET", "events-service", ["events", "me", "feed"]):
            let feed = events.filter { !$0.isPast && $0.visibility != .private }.map(withFriendsGoing)
            if query["rank"] == "affinity" { return ok(feed.sorted { ($0.affinity, $1.startDate) > ($1.affinity, $0.startDate) }) }
            return ok(feed.sorted { $0.startDate < $1.startDate })
        case ("GET", "events-service", ["events", "me", "reunions"]):
            return ok(reunions().filter { !dismissedReunions.contains($0.friendId) })
        case ("POST", "events-service", let r) where r.count == 5 && r[0] == "events" && r[2] == "reunions" && r[4] == "dismiss":
            guard friends[r[3]] != nil else { return (404, json(["code": "EVT-BUS-040"])) }
            dismissedReunions.insert(r[3])
            return (204, Data())
        case ("GET", "events-service", let r) where r.count == 5 && r[0] == "events" && r[2] == "friendships" && r[4] == "memories":
            guard let memories = memories(with: r[3]) else { return (404, json(["code": "EVT-BUS-041"])) }
            return ok(memories)
        case ("GET", "events-service", ["events", "me", "circle"]): return ok(circle())
        case ("GET", "events-service", ["events", "me", "polls"]): return ok(events.filter(\.isOpenPoll))
        case ("GET", "events-service", ["events", "me", "birthdays"]):
            guard let from = query["from"].flatMap(WireDate.parse), let to = query["to"].flatMap(WireDate.parse) else { return (400, Data()) }
            return ok(birthdayOccurrences(from: from, to: to))
        case ("GET", "events-service", ["events", "me", "summary"]): return ok(summary())
        case ("POST", "events-service", ["events", "me", "conflicts"]):
            guard let request = decode(ConflictsRequest.self, body) else { return ok([FeedEvent]()) }
            return ok(events.filter { joined.contains($0.id) && $0.id != request.excludedEventId && $0.startDate < request.end && $0.endDate > request.start })
        case ("POST", "events-service", ["events", "me", "free-slots"]):
            return ok([FreeRange(start: at(3, 19), end: at(3, 23)), FreeRange(start: at(8, 10), end: at(8, 18))])
        case ("GET", "events-service", ["events", "map"]): return ok(events.filter { $0.coordinates != nil && !$0.isPast })
        case ("GET", "events-service", let r) where r.count == 3 && r[0] == "events" && r[1] == "community":
            return ok(events.filter { $0.communityId == r[2] })
        case ("GET", "events-service", let r) where r.count == 4 && r[0] == "events" && r[1] == "users" && r[3] == "overview":
            let id = r[2]
            let together = events.filter { joined.contains($0.id) && participants[$0.id, default: []].contains(id) }
            return ok(FriendOverview(outingsTogether: together.filter(\.isPast).count + 3, upcomingTogether: together.filter { !$0.isPast },
                                     memoriesTogether: together.filter(\.isPast), friendUpcoming: events.filter { $0.organizerId == id && !$0.isPast }))
        case ("GET", "events-service", let r) where r.count == 4 && r[0] == "events" && r[1] == "users" && r[3] == "calendar":
            return ok(events.filter { participants[$0.id, default: []].contains(r[2]) }.map {
                FriendCalendarEntry(start: $0.startDate, end: $0.endDate, eventId: $0.id, title: $0.title, location: $0.location, description: nil)
            })
        case ("POST", "events-service", ["events"]):
            // As wely-events' EventRequest: a title is required, and a location unless it is a surprise.
            guard let request = decode(EventCreateRequest.self, body),
                  !request.title.trimmingCharacters(in: .whitespaces).isEmpty,
                  request.kind == .surprise || !request.location.trimmingCharacters(in: .whitespaces).isEmpty else {
                return (400, json(["message": "Location is required"]))
            }
            if request.kind == .surprise, let existing = surprise(for: request.honoreeId ?? "", around: request.startDate) {
                return (409, json(["code": "EVT-BUS-030", "eventId": existing.id]))
            }
            let id = "demo-\(UUID().uuidString.prefix(6))"
            let poll = request.candidateSlots.map { slots in
                Poll(status: .open, slots: slots.enumerated().map { PollSlot(id: "\(id)-s\($0.offset)", start: $0.element.start, end: $0.element.end) })
            }
            events.append(FeedEvent(id: id, title: request.title, organizerId: Self.me, startDate: request.startDate, endDate: request.endDate,
                                    location: request.location, coordinates: request.coordinates, description: request.description ?? "",
                                    visibility: request.communityId != nil ? .community : request.visibility, poll: poll, communityId: request.communityId,
                                    allDay: request.allDay ?? false, kind: request.kind ?? .standard, honoreeId: request.honoreeId))
            joined.insert(id)
            participants[id] = [Self.me]
            return ok(events.last!)
        case ("GET", "events-service", let r) where r.count == 2 && r[0] == "events":
            guard let event = events.first(where: { $0.id == r[1] }) else { return (404, Data()) }
            return ok(withFriendsGoing(event))
        case ("PUT", "events-service", let r) where r.count == 2 && r[0] == "events":
            guard let request = decode(EventUpdateRequest.self, body), let index = events.firstIndex(where: { $0.id == r[1] }) else { return (404, Data()) }
            guard events[index].organizerId == Self.me else { return (403, json(["code": "EVT-BUS-002"])) }
            let old = events[index]
            events[index] = FeedEvent(id: old.id, title: request.title, organizerId: old.organizerId, startDate: old.startDate, endDate: old.endDate,
                                      location: request.location, coordinates: request.coordinates, image: old.image, description: request.description ?? "",
                                      visibility: old.communityId != nil ? .community : (request.visibility ?? old.visibility), poll: old.poll,
                                      communityId: old.communityId, responses: old.responses)
            return ok(events[index])
        case ("DELETE", "events-service", let r) where r.count == 2 && r[0] == "events":
            events.removeAll { $0.id == r[1] }
            return (204, Data())
        case ("GET", "events-service", let r) where r.count == 3 && r[0] == "events" && r[2] == "participants":
            let ids = participants[r[1], default: []]
            let visible = joined.contains(r[1])
            let organizes = events.first { $0.id == r[1] }?.organizerId == Self.me
            let pending = invited[r[1], default: []]
            return ok(EventParticipants(count: ids.count, participantIds: visible ? ids : [], friendsGoingIds: ids.filter { friends[$0] != nil },
                                        invitedIds: organizes ? pending : pending.filter { $0 == Self.me }))
        case ("POST", "events-service", let r) where r.count == 3 && r[0] == "events" && r[2] == "invitations":
            guard let friendId = decode([String: String].self, body)?["userId"], let event = events.first(where: { $0.id == r[1] }) else { return (400, Data()) }
            guard event.organizerId == Self.me else { return (403, json(["code": "EVT-BUS-002"])) }
            guard friends[friendId] != nil else { return (404, json(["code": "EVT-BUS-036"])) }
            guard !participants[r[1], default: []].contains(friendId) else { return (409, json(["code": "EVT-BUS-040"])) }
            if !invited[r[1], default: []].contains(friendId) { invited[r[1], default: []].append(friendId) }
            let ids = participants[r[1], default: []]
            return ok(EventParticipants(count: ids.count, participantIds: ids, friendsGoingIds: ids.filter { friends[$0] != nil },
                                        invitedIds: invited[r[1], default: []]))
        case ("DELETE", "events-service", let r) where r.count == 4 && r[0] == "events" && r[2] == "invitations":
            invited[r[1]]?.removeAll { $0 == r[3] }
            return (204, Data())
        case ("POST", "events-service", let r) where r.count == 3 && r[0] == "events" && r[2] == "subscribe":
            let id = r[1]
            if joined.contains(id) {
                joined.remove(id); participants[id]?.removeAll { $0 == Self.me }
            } else {
                joined.insert(id); participants[id, default: []].append(Self.me); invited[id]?.removeAll { $0 == Self.me }
            }
            return ok(events.first { $0.id == id }!)
        case ("POST", "events-service", let r) where r.count == 3 && r[0] == "events" && r[2] == "leave":
            joined.remove(r[1]); participants[r[1]]?.removeAll { $0 == Self.me }
            return ok(LeaveResult(deleted: false, event: events.first { $0.id == r[1] }))
        case ("PUT", "events-service", let r) where r.count == 3 && r[0] == "events" && r[2] == "response":
            guard let answer = decode(AnswerRequest.self, body)?.answer, let index = events.firstIndex(where: { $0.id == r[1] }) else { return (400, Data()) }
            var responses = events[index].responses ?? EventResponses()
            responses.yes.removeAll { $0 == Self.me }; responses.maybe.removeAll { $0 == Self.me }; responses.no.removeAll { $0 == Self.me }
            switch answer {
            case .yes: responses.yes.append(Self.me); joined.insert(r[1])
            case .maybe: responses.maybe.append(Self.me); joined.remove(r[1])
            case .no: responses.no.append(Self.me); joined.remove(r[1])
            }
            events[index] = events[index].with(responses: responses)
            return ok(events[index])
        case ("PUT", "events-service", let r) where r.count == 4 && r[0] == "events" && r[2] == "poll" && r[3] == "ballot":
            guard let ballot = decode(BallotRequest.self, body), let index = events.firstIndex(where: { $0.id == r[1] }), let poll = events[index].poll else { return (400, Data()) }
            let slots = poll.slots.map { slot -> PollSlot in
                var yes = slot.yes.filter { $0 != Self.me }, maybe = slot.maybe.filter { $0 != Self.me }, no = slot.no.filter { $0 != Self.me }
                switch ballot.answers[slot.id] {
                case .yes: yes.append(Self.me)
                case .maybe: maybe.append(Self.me)
                case .no: no.append(Self.me)
                case nil: break
                }
                return PollSlot(id: slot.id, start: slot.start, end: slot.end, yes: yes, maybe: maybe, no: no)
            }
            let updated = Poll(status: poll.status, fixedSlotId: poll.fixedSlotId, slots: slots)
            events[index] = events[index].with(poll: updated)
            return ok(updated)
        case ("POST", "events-service", let r) where r.count == 4 && r[0] == "events" && r[2] == "poll" && r[3] == "fix":
            guard let slotId = decode(SlotChoice.self, body)?.slotId, let index = events.firstIndex(where: { $0.id == r[1] }),
                  let slot = events[index].poll?.slots.first(where: { $0.id == slotId }) else { return (400, Data()) }
            events[index] = events[index].with(start: slot.start, end: slot.end, poll: Poll(status: .closed, fixedSlotId: slotId, slots: events[index].poll!.slots))
            return ok(events[index])
        case ("PUT", "events-service", let r) where r.count == 3 && r[0] == "events" && r[2] == "schedule":
            guard let range = decode(FreeRange.self, body), let index = events.firstIndex(where: { $0.id == r[1] }) else { return (400, Data()) }
            events[index] = events[index].with(start: range.start, end: range.end)
            return ok(events[index])
        case ("GET", "events-service", let r) where r.count == 3 && r[0] == "events" && r[2] == "expenses": return ok(expenses[r[1], default: []])
        case ("GET", "events-service", let r) where r.count == 4 && r[0] == "events" && r[2] == "expenses" && r[3] == "ledger": return ok(ledger(r[1]))
        case ("POST", "events-service", let r) where r.count == 3 && r[0] == "events" && r[2] == "expenses":
            guard let request = decode(ExpenseRequest.self, body) else { return (400, Data()) }
            let members = participants[r[1], default: [Self.me]]
            let each = request.amountCents / max(1, members.count)
            let expense = Expense(id: UUID().uuidString, title: request.title, amountCents: request.amountCents, currency: "EUR", paidBy: request.paidBy,
                                  createdBy: Self.me, kind: "EXPENSE", split: request.split, shares: request.shares,
                                  owedCents: Dictionary(uniqueKeysWithValues: members.map { ($0, each) }), spentAt: now, version: 1, receiptUrl: nil)
            expenses[r[1], default: []].append(expense)
            return ok(expense)
        case ("POST", "events-service", let r) where r.count == 4 && r[0] == "events" && r[2] == "expenses" && r[3] == "settlements":
            guard let request = decode(SettlementRequest.self, body) else { return (400, Data()) }
            let expense = Expense(id: UUID().uuidString, title: "Remboursement", amountCents: request.amountCents, currency: "EUR", paidBy: request.fromUserId,
                                  createdBy: Self.me, kind: "SETTLEMENT", split: .exact, shares: [], owedCents: [request.toUserId: request.amountCents],
                                  spentAt: now, version: 1, receiptUrl: nil)
            expenses[r[1], default: []].append(expense)
            return ok(expense)
        case ("DELETE", "events-service", let r) where r.count == 4 && r[0] == "events" && r[2] == "expenses":
            expenses[r[1]]?.removeAll { $0.id == r[3] }
            return (204, Data())

        // chat
        case ("GET", "chat-service", ["conversations", "all"]):
            return ok(conversations.map {
                ConversationSummary(id: $0.id, participantIds: $0.participantIds, type: $0.type, title: $0.title, updatedAt: $0.updatedAt,
                                    lastMessage: $0.messages.last, lastBucketIndex: 0, eventId: $0.eventId)
            }.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) })
        case ("GET", "chat-service", ["conversations"]):
            let friend = query["friendId"] ?? ""
            if let existing = conversations.first(where: { $0.type == .direct && $0.participantIds.contains(friend) }) { return ok(existing) }
            conversations.append(conversation("conv-\(friend)", .direct, with: [friend], messages: []))
            return ok(conversations.last!)
        case ("GET", "chat-service", let r) where r.count == 3 && r[0] == "conversations" && r[1] == "events":
            if let existing = conversations.first(where: { $0.eventId == r[2] }) { return ok(existing) }
            let ids = participants[r[2], default: []].filter { $0 != Self.me }
            conversations.append(conversation("conv-\(r[2])", .event, with: ids, title: events.first { $0.id == r[2] }?.title, eventId: r[2], messages: []))
            return ok(conversations.last!)
        case ("GET", "chat-service", let r) where r.count == 2 && r[0] == "conversations":
            guard let conversation = conversations.first(where: { $0.id == r[1] }) else { return (404, Data()) }
            return ok(conversation)
        case ("GET", "chat-service", let r) where r.count == 3 && r[0] == "conversations" && r[2] == "loadMessages":
            return ok(MessageBucket(conversationId: r[1], bucketIndex: Int(query["bucketIndex"] ?? "0") ?? 0, messages: []))
        case ("GET", "chat-service", let r) where r.count == 2 && r[0] == "presence":
            return ok(Presence(userId: r[1], online: r[1] == "lea", lastSeenAt: now.addingTimeInterval(-3600)))

        // notifications
        case ("GET", "notifications-service", ["notifications"]): return ok(notifications)
        case ("GET", "notifications-service", ["notifications", "unread-count"]): return ok(UnreadCount(count: notifications.filter { !$0.isRead }.count))
        case ("POST", "notifications-service", ["notifications", "read"]):
            notifications = notifications.map { var n = $0; n.readAt = n.readAt ?? now; return n }
            return (204, Data())
        case ("GET", "notifications-service", ["preferences"]): return ok(notificationPreferences)
        case ("PUT", "notifications-service", ["preferences"]):
            if let value = decode(NotificationPreferences.self, body) { notificationPreferences = value }
            return (204, Data())

        default:
            return (404, json(["message": "demo: \(method) \(path)"]))
        }
    }

    // MARK: Builders

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    }

    private func event(_ id: String, _ title: String, by organizer: String, day: Int, _ startHour: Int, _ endHour: Int, _ location: String,
                       lat: Double, lon: Double, visibility: Visibility = .friends, community: String? = nil, description: String = "",
                       image: String? = nil) -> FeedEvent {
        FeedEvent(id: id, title: title, organizerId: organizer, startDate: at(day, startHour), endDate: at(day, endHour), location: location,
                  coordinates: Coordinates(latitude: lat, longitude: lon), image: image, description: description, visibility: visibility,
                  communityId: community)
    }

    private func profile(_ id: String) -> UserProfile {
        let p = people[id]!
        let birthDate = birthdays[id].map { String(format: "%04d-%02d-%02d", myBirthYear, $0.month, $0.day) }
        return UserProfile(id: id, userName: p.name, email: "\(p.name)@example.com", firstName: p.first, lastName: p.last, hashtag: p.tag,
                           joinedDate: "2025-03-01", birthDate: birthDate, registrationCompleted: true)
    }

    private func monthDay(_ days: Int) -> MonthDay {
        let parts = calendar.dateComponents([.month, .day], from: at(days, 12))
        return MonthDay(month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// The surprise prepared for someone within 60 days of a date, as wely-events dedupes them.
    private func surprise(for honoreeId: String, around date: Date) -> FeedEvent? {
        events.first { $0.kind == .surprise && $0.honoreeId == honoreeId && abs($0.startDate.timeIntervalSince(date)) < 60 * 86_400 }
    }

    /// Mine and my friends' birthdays falling in the range, as `/events/me/birthdays` answers.
    private func birthdayOccurrences(from: Date, to: Date) -> [BirthdayOccurrence] {
        let years = calendar.component(.year, from: from)...calendar.component(.year, from: to)
        return birthdays.flatMap { id, birthday -> [BirthdayOccurrence] in
            let mine = id == Self.me
            guard mine || friends[id] != nil else { return [] }
            return years.compactMap { year in
                guard let day = calendar.date(from: DateComponents(year: year, month: birthday.month, day: birthday.day)), day >= from, day < to else { return nil }
                let closeness = mine ? nil : friends[id]
                let existing = mine ? nil : surprise(for: id, around: day)
                return BirthdayOccurrence(userId: id, name: people[id]!.first, date: DayString.string(from: day, calendar: calendar), mine: mine,
                                          closeness: closeness, canOrganize: !mine && existing == nil && (closeness ?? .friend) >= .close,
                                          surprise: existing.map { .init(eventId: $0.id, organizerId: $0.organizerId, joined: joined.contains($0.id)) })
            }
        }
        .sorted { $0.date < $1.date }
    }

    private func node(_ id: String) -> UserNode {
        UserNode(userId: id, userName: people[id]!.name, hashtag: people[id]!.tag, profilePicUrl: nil)
    }

    private func relation(_ id: String) -> RelationStatus {
        if friends[id] != nil { return .friends }
        if incoming.contains(id) { return .sentByThem }
        if outgoing.contains(id) { return .sentByMe }
        return id == Self.me ? .me : .none
    }

    private func withStatus(_ id: String) -> UserWithStatus {
        UserWithStatus(userId: id, userName: people[id]!.name, profilePicUrl: nil, relationStatus: relation(id), hashtag: people[id]!.tag, viaEventId: nil)
    }

    private func socialPerson(_ id: String) -> SocialPerson {
        SocialPerson(userId: id, userName: people[id]?.name ?? id, hashtag: people[id]?.tag ?? "", profilePicUrl: nil, relationStatus: relation(id),
                     closeness: friends[id], proposal: id == "hugo" ? .intimate : nil, proposedByFriend: id == "hugo",
                     since: friends[id] != nil ? DayString.string(from: since(id), calendar: calendar) : nil)
    }

    /// Léa became a friend a year ago today, to show the anniversary; the others in June 2025.
    private func since(_ id: String) -> Date {
        if id == "lea" { return calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: now))! }
        return calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))!
    }

    /// The caller's friends among the organizer and participants, as wely-events adds them.
    private func withFriendsGoing(_ event: FeedEvent) -> FeedEvent {
        guard event.kind != .birthday else { return event }
        let ids = Set([event.organizerId] + participants[event.id, default: []]).subtracting([Self.me])
        let going = ids.compactMap { id in friends[id].map { (id, $0) } }
            .sorted { ($0.1, $1.0) > ($1.1, $0.0) }
            .map { FriendGoing(userId: $0.0, closeness: $0.1) }
        let affinity = going.first.map { $0.closeness == .intimate ? 3 : $0.closeness == .close ? 2 : 1 } ?? 0
        return event.with(friendsGoing: Array(going.prefix(5)), count: going.count, affinity: affinity)
    }

    /// Hugo, last seen four months ago; Inès, never seen on Wely.
    private func reunions() -> [ReunionCandidate] {
        [
            ReunionCandidate(friendId: "hugo", name: "Hugo", closeness: friends["hugo"], lastSharedAt: at(-122, 11),
                             lastSharedEventId: "demo-10", lastSharedTitle: "Week-end à Annecy", monthsApart: 4),
            ReunionCandidate(friendId: "ines", name: "Inès", closeness: friends["ines"]),
        ].filter { friends[$0.friendId] != nil }
    }

    private func memories(with id: String) -> FriendshipMemories? {
        guard let closeness = friends[id], let person = people[id] else { return nil }
        let since = since(id)
        let days = calendar.dateComponents([.day], from: since, to: calendar.startOfDay(for: now)).day ?? 0
        let together = events.filter { $0.isPast && joined.contains($0.id) && participants[$0.id, default: []].contains(id) }
            .sorted { $0.startDate < $1.startDate }
        let memory = { (event: FeedEvent) in MemoryEvent(eventId: event.id, title: event.title, startDate: event.startDate, imageUrl: event.image) }
        let older = [
            MemoryEvent(eventId: "demo-10", title: "Week-end à Annecy", startDate: at(-20, 9)),
            MemoryEvent(eventId: "demo-6", title: "Pique-nique des quais", startDate: at(-75, 12)),
            MemoryEvent(eventId: "demo-2", title: "Première séance de bloc", startDate: at(-300, 18)),
            MemoryEvent(eventId: "demo-1", title: "Afterwork de rentrée", startDate: at(-40, 19)),
        ]
        let highlights = Array((together.map(memory) + older).reduce(into: [MemoryEvent]()) { list, item in
            if !list.contains(where: { $0.title == item.title }) { list.append(item) }
        }.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }.prefix(6))
        return FriendshipMemories(friendId: id, name: person.first, closeness: closeness, since: since,
                                  years: calendar.dateComponents([.year], from: since, to: now).year ?? 0, days: days,
                                  sharedCount: together.count + 11, first: older[2], last: together.last.map(memory) ?? older[0],
                                  highlights: highlights)
    }

    /// The intimate friends' entries: Léa's outings, a busy lunch and a dinner of her own.
    private func circle() -> [CircleEntry] {
        let intimates = friends.filter { $0.value == .intimate }.keys
        return intimates.flatMap { id -> [CircleEntry] in
            let outings = events.filter { participants[$0.id, default: []].contains(id) && !$0.isOpenPoll && $0.kind == .standard }.map {
                CircleEntry(userId: id, start: $0.startDate, end: $0.endDate, allDay: $0.allDay, eventId: $0.id, title: $0.title, location: $0.location)
            }
            return outings + [
                CircleEntry(userId: id, start: at(1, 12), end: at(1, 14)),
                CircleEntry(userId: id, start: at(3, 20), end: at(3, 23), title: "Dîner chez sa sœur", location: "Croix-Rousse"),
            ]
        }
    }

    /// The bytes of a multipart body's one file: after its part's headers, up to the closing boundary.
    static func uploadedFile(in body: Data?) -> Data? {
        guard let body, let headersEnd = body.range(of: Data("\r\n\r\n".utf8)),
              let closing = body.range(of: Data("\r\n--".utf8), options: .backwards, in: headersEnd.upperBound..<body.endIndex),
              closing.lowerBound > headersEnd.upperBound else { return nil }
        return body.subdata(in: headersEnd.upperBound..<closing.lowerBound)
    }

    private func withRole(_ community: Community) -> Community {
        Community(communityId: community.communityId, name: community.name, description: community.description, interests: community.interests,
                  visibility: community.visibility, createdAt: community.createdAt, memberCount: community.memberCount + (memberships[community.communityId] != nil && community.role == nil ? 1 : 0),
                  role: memberships[community.communityId], friendMembers: community.friendMembers, friendMemberCount: community.friendMemberCount,
                  pictureUrl: community.pictureUrl)
    }

    private func conversation(_ id: String, _ type: ConversationType, with others: [String], title: String? = nil, eventId: String? = nil,
                              messages: [(String, String, Double)]) -> Conversation {
        let list = messages.enumerated().map { index, item in
            Message(id: "\(id)-\(index)", senderId: item.0, senderName: people[item.0]?.name, receiverId: nil, conversationId: id, content: item.1,
                    timestamp: now.addingTimeInterval(item.2 * 60))
        }
        return Conversation(id: id, participantIds: [Self.me] + others, type: type, title: title, eventId: eventId, organizerId: nil,
                            updatedAt: list.last?.timestamp ?? now, lastMessage: list.last, messages: list, bucketIndex: 0)
    }

    private func ledger(_ eventId: String) -> Ledger {
        var net: [String: Int] = [:]
        for expense in expenses[eventId, default: []] {
            net[expense.paidBy, default: 0] += expense.amountCents
            for (id, owed) in expense.owedCents ?? [:] { net[id, default: 0] -= owed }
        }
        let balances = net.map { Balance(userId: $0.key, netCents: $0.value) }.sorted { $0.netCents > $1.netCents }
        var transfers: [Transfer] = []
        var creditors = balances.filter { $0.netCents > 0 }.map { ($0.userId, $0.netCents) }
        var debtors = balances.filter { $0.netCents < 0 }.map { ($0.userId, -$0.netCents) }
        while let creditor = creditors.first, let debtor = debtors.first {
            let amount = min(creditor.1, debtor.1)
            transfers.append(Transfer(fromUserId: debtor.0, toUserId: creditor.0, amountCents: amount))
            creditors[0].1 -= amount; debtors[0].1 -= amount
            if creditors[0].1 == 0 { creditors.removeFirst() }
            if debtors[0].1 == 0 { debtors.removeFirst() }
        }
        return Ledger(currency: "EUR", totalCents: expenses[eventId, default: []].filter { !$0.isSettlement }.map(\.amountCents).reduce(0, +),
                      balances: balances, transfers: transfers)
    }

    private func summary() -> ProfileSummary {
        let mine = events.filter { joined.contains($0.id) }
        return ProfileSummary(outingsThisYear: 24, outingsThisMonth: 3, organizedThisYear: 7, placesThisYear: 12,
                              upcoming: mine.filter { !$0.isPast }.sorted { $0.startDate < $1.startDate }, memories: mine.filter(\.isPast),
                              pastCount: 24, circle: [Companion(userId: "lea", outingsTogether: 14), Companion(userId: "hugo", outingsTogether: 9),
                                                      Companion(userId: "ines", outingsTogether: 5)],
                              places: [VisitedPlace(label: "Ninkasi Gerland", coordinates: Coordinates(latitude: 45.7325, longitude: 4.8335), visits: 6),
                                       VisitedPlace(label: "Climb Up Gerland", coordinates: Coordinates(latitude: 45.7301, longitude: 4.8281), visits: 4)],
                              balances: [EventBalance(eventId: "demo-10", title: "Week-end à Annecy", netCents: ledger("demo-10").balances.first { $0.userId == Self.me }?.netCents ?? 0)],
                              newFriendsThisYear: [NewFriend(userId: "nathan", since: at(-150, 12)), NewFriend(userId: "sarah", since: at(-60, 12))],
                              upgradesThisYear: [ClosenessUpgrade(userId: "lea", closeness: .intimate, at: at(-210, 12)),
                                                 ClosenessUpgrade(userId: "ines", closeness: .close, at: at(-1, 12))],
                              topFriendsThisYear: [Companion(userId: "lea", outingsTogether: 11), Companion(userId: "hugo", outingsTogether: 7),
                                                   Companion(userId: "ines", outingsTogether: 4)])
    }

    // MARK: JSON

    private func ok(_ value: some Encodable) -> (Int, Data) { (200, json(value)) }
    private func json(_ value: some Encodable) -> Data { (try? JSONEncoder.wely.encode(value)) ?? Data() }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? { try? JSONDecoder.wely.decode(type, from: data) }
}
#endif
