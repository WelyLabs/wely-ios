import Foundation
import Testing
@testable import Wely

struct RSocketFrameTests {
    @Test func setupFrameLayout() {
        let bytes = [UInt8](RSocketFrame.setup(keepAliveMs: 30_000, lifetimeMs: 90_000, metadataMime: "m", dataMime: "application/json").encoded())
        #expect(Array(bytes[0..<4]) == [0, 0, 0, 0])                 // stream 0
        #expect(bytes[4] >> 2 == 0x01)                                // SETUP
        #expect(Array(bytes[6..<10]) == [0, 1, 0, 0])                // version 1.0
        #expect(Array(bytes[10..<14]) == [0, 0, 0x75, 0x30])         // 30 000 ms
        #expect(Array(bytes[14..<18]) == [0, 0x01, 0x5F, 0x90])      // 90 000 ms
        #expect(bytes[18] == 1 && bytes[19] == UInt8(ascii: "m"))
        #expect(bytes[20] == 16)
        #expect(String(decoding: bytes[21...], as: UTF8.self) == "application/json")
    }

    @Test func requestResponseCarriesMetadataLength() {
        let bytes = [UInt8](RSocketFrame.requestResponse(stream: 3, metadata: Data([1, 2]), data: Data("{}".utf8)).encoded())
        #expect(Array(bytes[0..<4]) == [0, 0, 0, 3])
        let typeAndFlags = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        #expect(typeAndFlags >> 10 == 0x04)
        #expect(typeAndFlags & 0x100 != 0)                            // metadata flag
        #expect(Array(bytes[6..<9]) == [0, 0, 2])
        #expect(Array(bytes[9..<11]) == [1, 2])
        #expect(String(decoding: bytes[11...], as: UTF8.self) == "{}")
    }

    @Test func requestStreamAsksForMany() {
        let bytes = [UInt8](RSocketFrame.requestStream(stream: 5, initialN: UInt32(Int32.max), metadata: Data(), data: Data()).encoded())
        #expect(bytes[4] >> 2 == 0x06)
        #expect(Array(bytes[6..<10]) == [0x7F, 0xFF, 0xFF, 0xFF])
    }

    @Test func decodesAPayloadWithMetadata() {
        // stream 1, PAYLOAD with M|C|N, 1 byte of metadata, then data.
        let flags: UInt16 = 0x100 | 0x40 | 0x20
        let header = UInt16(0x0A) << 10 | flags
        let raw = Data([0, 0, 0, 1, UInt8(header >> 8), UInt8(header & 0xFF), 0, 0, 1, 9] + Array("hi".utf8))
        #expect(RSocketFrame.decode(raw) == .payload(stream: 1, data: Data("hi".utf8), next: true, complete: true))
    }

    @Test func decodesAnErrorAndAKeepAlive() {
        let error = Data([0, 0, 0, 3, UInt8(0x0B << 2), 0, 0, 0, 0x02, 0x01] + Array("nope".utf8))
        #expect(RSocketFrame.decode(error) == .error(stream: 3, code: 0x201, message: "nope"))
        let keepAlive = RSocketFrame.keepAlive(respond: true, position: 7).encoded()
        #expect(RSocketFrame.decode(keepAlive) == .keepAlive(respond: true, position: 7))
        #expect(RSocketFrame.decode(Data([1, 2])) == nil)
    }

    @Test func compositeMetadataHoldsRouteThenBearer() {
        let bytes = [UInt8](RSocketMetadata.compose(route: "chat.send", bearer: "TOKEN"))
        #expect(bytes[0] == 0xFE)                                     // routing, well-known
        #expect(Array(bytes[1..<4]) == [0, 0, 10])                    // 1 + "chat.send"
        #expect(bytes[4] == 9)
        #expect(String(decoding: bytes[5..<14], as: UTF8.self) == "chat.send")
        #expect(bytes[14] == 0xFC)                                    // authentication, well-known
        #expect(Array(bytes[15..<18]) == [0, 0, 6])
        #expect(bytes[18] == 0x81)                                    // bearer
        #expect(String(decoding: bytes[19...], as: UTF8.self) == "TOKEN")
    }
}

struct SSEParserTests {
    @Test func dispatchesOnBlankLines() {
        var parser = SSEParser()
        #expect(parser.feed(": keep-alive") == nil)
        #expect(parser.feed("event: unread") == nil)
        #expect(parser.feed("data: {\"count\":3}") == nil)
        #expect(parser.feed("") == SSEMessage(event: "unread", data: "{\"count\":3}"))
        #expect(parser.feed("data:a") == nil)
        #expect(parser.feed("data: b") == nil)
        #expect(parser.feed("") == SSEMessage(event: "message", data: "a\nb"))
        #expect(parser.feed("") == nil)
    }

    @Test func notificationCenterHandlesStreamEvents() {
        let session = AuthSession(store: InMemoryTokenStore())
        let center = NotificationCenterModel(service: NotificationService(api: APIClient(session: session, http: DemoTransport())), session: session, live: false)
        center.handle(SSEMessage(event: "unread", data: #"{"count":4}"#))
        #expect(center.unread == 4)
        center.handle(SSEMessage(event: "notification", data: #"{"id":"n9","type":"MESSAGE","title":"Hi","body":"b","createdAt":"2026-10-15T10:00:00Z"}"#))
        #expect(center.items.map(\.id) == ["n9"])
        #expect(center.arrival?.id == "n9")
        center.markRead(center.items[0])
        #expect(center.items[0].isRead)
        #expect(center.unread == 3)
    }
}

struct LinkAndMoneyTests {
    @Test func webPathsMapToScreens() {
        #expect(AppDestination(webPath: "/event/e1") == .event("e1"))
        #expect(AppDestination(webPath: "/preferences?account=delete") == .preferences)
        #expect(AppDestination(webPath: "/event/feed/e1") == .event("e1"))
        #expect(AppDestination(webPath: "/chat/c1?x=1") == .conversation("c1"))
        #expect(AppDestination(webPath: "/friends/u1") == .person("u1"))
        #expect(AppDestination(webPath: "/communities/k1") == .community("k1"))
        #expect(AppDestination(webPath: "/communities/invite/tok") == .invitation("tok"))
        #expect(AppDestination(webPath: "/call/x") == nil)
    }

    @Test func invitationTokenInALink() {
        #expect(CommunityInvitation.token(in: "Rejoins : https://wely.app/communities/invite/abcdefghij0123456789") == "abcdefghij0123456789")
        #expect(CommunityInvitation.token(in: "/communities/invite/short") == nil)
        #expect(CommunityInvitation.token(in: nil) == nil)
    }

    @Test func moneyParsesAndFormats() {
        #expect(Money.cents(from: "12,5") == 1250)
        #expect(Money.cents(from: "12.50 €") == 1250)
        #expect(Money.cents(from: "0") == nil)
        #expect(Money.cents(from: "abc") == nil)
        #expect(Money.format(cents: 1250).replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ") == "12,50 €")
    }

    @Test func closenessOptions() {
        let friendship = Friendship(friendId: "f", closeness: .close, proposal: .intimate, proposedByFriend: false)
        #expect(friendship.options.map(\.label) == ["Redescendre à Ami"])
        let theirs = Friendship(friendId: "f", closeness: .friend, proposal: .close, proposedByFriend: true)
        #expect(theirs.options.map(\.label) == ["Proposer : Proche", "Proposer : Intime"])
    }

    @Test func lenientWrappersFillGaps() throws {
        let node = try JSONDecoder.wely.decode(UserNode.self, from: Data(#"{"userId":"u","userName":"n","hashtag":4907}"#.utf8))
        #expect(node.hashtag == "4907")
        let summary = try JSONDecoder.wely.decode(FriendSummary.self, from: Data(#"{"userId":"u","userName":"n","closeness":"CLOSE"}"#.utf8))
        #expect(summary.hashtag == "")
        #expect(summary.proposedByFriend == false)
        let community = try JSONDecoder.wely.decode(Community.self, from: Data(#"{"communityId":"c","name":"N","visibility":"PUBLIC","memberCount":2,"interests":null}"#.utf8))
        #expect(community.interests == [])
        #expect(!community.isMember)
        let status = try JSONDecoder.wely.decode(UserWithStatus.self, from: Data(#"{"userId":"u","userName":"n","relationStatus":"WHATEVER"}"#.utf8))
        #expect(status.relationStatus == .unknown)
    }

    @Test func personInitials() {
        #expect(Person.initials(of: "Club Auto Rétro") == "CA")
        #expect(Person.initials(of: "lea") == "LE")
    }
}

/// The demo gateway keeps what the user does, as the screens expect from the real one.
struct DemoStoreTests {
    private func call<T: Decodable>(_ store: inout DemoStore, _ method: String, _ path: String, body: some Encodable = Empty(), query: [String: String] = [:]) throws -> T {
        let (status, data) = store.handle(method: method, path: path, query: query, body: (try? JSONEncoder.wely.encode(body)) ?? Data())
        #expect((200..<300).contains(status), "\(method) \(path) → \(status)")
        return try JSONDecoder.wely.decode(T.self, from: data)
    }

    @Test func joiningAndLeavingAnEvent() throws {
        var store = DemoStore()
        let before: [FeedEvent] = try call(&store, "GET", "events-service/events/me/subscribed")
        #expect(!before.contains { $0.id == "demo-7" })
        let _: FeedEvent = try call(&store, "POST", "events-service/events/demo-7/subscribe")
        let after: [FeedEvent] = try call(&store, "GET", "events-service/events/me/subscribed")
        #expect(after.contains { $0.id == "demo-7" })
    }

    @Test func creatingAPollAndFixingItsDate() throws {
        var store = DemoStore()
        let start = Date.now.addingTimeInterval(86_400)
        let created: FeedEvent = try call(&store, "POST", "events-service/events", body: EventCreateRequest(
            title: "Test", startDate: start, location: "Lyon",
            candidateSlots: [.init(start: start, end: start.addingTimeInterval(3600)), .init(start: start.addingTimeInterval(86_400), end: start.addingTimeInterval(90_000))]))
        #expect(created.isOpenPoll)
        let slot = created.poll!.slots[1]
        let poll: Poll = try call(&store, "PUT", "events-service/events/\(created.id)/poll/ballot", body: BallotRequest(answers: [slot.id: .yes]))
        #expect(poll.slots[1].yes == [DemoStore.me])
        let fixed: FeedEvent = try call(&store, "POST", "events-service/events/\(created.id)/poll/fix", body: SlotChoice(slotId: slot.id))
        #expect(!fixed.isOpenPoll)
        #expect(fixed.startDate == slot.start)
    }

    @Test func acceptingAFriendRequest() throws {
        var store = DemoStore()
        let (status, _) = store.handle(method: "PUT", path: "social-service/relationships/accept/jules", query: [:], body: Data())
        #expect(status == 204)
        let friends: [FriendSummary] = try call(&store, "GET", "social-service/relationships")
        #expect(friends.contains { $0.userId == "jules" })
    }

    @Test func ledgerBalancesToZero() throws {
        var store = DemoStore()
        let ledger: Ledger = try call(&store, "GET", "events-service/events/demo-10/expenses/ledger")
        #expect(ledger.totalCents == 44_450)
        #expect(ledger.balances.map(\.netCents).reduce(0, +) == 0)
        #expect(!ledger.transfers.isEmpty)
    }

    @Test func theOrganizerEditsTheirEvent_othersCannot() throws {
        var store = DemoStore()
        let edit = EventUpdateRequest(title: "Afterwork déplacé", location: "Le Sucre", description: "Rooftop", visibility: .public)
        let updated: FeedEvent = try call(&store, "PUT", "events-service/events/demo-1", body: edit)
        #expect(updated.title == "Afterwork déplacé")
        #expect(updated.location == "Le Sucre")
        #expect(updated.visibility == .public)
        let body = try JSONEncoder.wely.encode(edit)
        #expect(store.handle(method: "PUT", path: "events-service/events/demo-2", query: [:], body: body).0 == 403)
    }

    @Test func anEventWithoutLocationIsRefused() {
        var store = DemoStore()
        let body = try! JSONEncoder.wely.encode(EventCreateRequest(title: "Sans lieu", startDate: .now, location: " "))
        #expect(store.handle(method: "POST", path: "events-service/events", query: [:], body: body).0 == 400)
    }

    @Test func unknownRoutesAre404() {
        var store = DemoStore()
        #expect(store.handle(method: "GET", path: "nope", query: [:], body: Data()).0 == 404)
    }
}
