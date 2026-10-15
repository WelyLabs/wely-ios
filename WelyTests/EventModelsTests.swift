import Foundation
import Testing
@testable import Wely

struct EventModelsTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.wely.decode(type, from: Data(json.utf8))
    }

    @Test func decodesAFullEvent() throws {
        let event = try decode(FeedEvent.self, """
        {"id":"e1","title":"Afterwork","organizerId":"u1","startDate":"2026-10-15T17:00:00Z",
         "endDate":"2026-10-15T20:00:00Z","location":"Ninkasi","coordinates":{"latitude":45.7,"longitude":4.8},
         "image":"/demo/a.jpg","description":"Go","visibility":"PUBLIC","communityId":null,
         "poll":{"status":"OPEN","fixedSlotId":null,"slots":[{"id":"s1","start":"2026-10-16T17:00:00Z","end":"2026-10-16T19:00:00Z","yes":["u2"]}]}}
        """)
        #expect(event.title == "Afterwork")
        #expect(event.endDate.timeIntervalSince(event.startDate) == 3 * 3600)
        #expect(event.coordinates == Coordinates(latitude: 45.7, longitude: 4.8))
        #expect(event.visibility == .public)
        #expect(event.isOpenPoll)
        #expect(event.poll?.slots.first?.yes == ["u2"])
        #expect(event.poll?.slots.first?.maybe == [])
    }

    @Test func aMissingEndLastsAnHour() throws {
        let event = try decode(FeedEvent.self, #"{"id":"e1","title":"T","organizerId":"u","startDate":"2026-10-15T17:00:00Z","endDate":null}"#)
        #expect(event.endDate.timeIntervalSince(event.startDate) == FeedEvent.defaultDuration)
        #expect(event.location == "")
        #expect(event.description == "")
        #expect(event.poll == nil)
    }

    @Test func anUnknownVisibilityDoesNotFailTheEvent() throws {
        let event = try decode(FeedEvent.self, #"{"id":"e1","title":"T","organizerId":"u","startDate":"2026-10-15T17:00:00Z","visibility":"SECRET"}"#)
        #expect(event.visibility == .unknown)
    }

    @Test func aPollDropsSlotsWithUnreadableDates() throws {
        let poll = try decode(Poll.self, """
        {"status":"OPEN","slots":[{"id":"ok","start":"2026-10-16T17:00:00Z","end":"2026-10-16T19:00:00Z"},
                                  {"id":"ko","start":"nope","end":"nope"}]}
        """)
        #expect(poll.slots.map(\.id) == ["ok"])
        #expect(poll.fixedSlotId == nil)
    }

    @Test func aLenientListSkipsBrokenEvents() throws {
        let events = try decode([Lenient<FeedEvent>].self, #"[{"id":"e1","title":"T","organizerId":"u"},{"title":"no id"}]"#)
        #expect(events.compactMap(\.value).map(\.id) == ["e1"])
    }

    @Test func profileNamesAndHandle() {
        let user = UserProfile(id: "1", userName: "robin", email: nil, firstName: "Robin", lastName: "Leblanc", hashtag: "4907")
        #expect(user.displayName == "Robin Leblanc")
        #expect(user.handle == "@robin#4907")
        #expect(user.initials == "RL")

        let bare = UserProfile(id: "2", userName: "lea", email: nil, firstName: nil, lastName: "")
        #expect(bare.displayName == "lea")
        #expect(bare.handle == "@lea")
        #expect(bare.initials == "LE")
    }

    @Test func visibilityLabels() {
        #expect(Visibility.friends.label == "Amis")
        #expect(Visibility.community.systemImage == "person.3")
    }

    @Test func coverURLs() {
        let config = AppConfig(gatewayURL: URL(string: "http://gw")!, keycloakURL: URL(string: "http://kc")!, webURL: URL(string: "http://web")!)
        #expect(config.imageURL("/demo/a.jpg")?.absoluteString == "http://web/demo/a.jpg")
        #expect(config.imageURL("https://s3/x.jpg?sig=1")?.absoluteString == "https://s3/x.jpg?sig=1")
        #expect(config.imageURL("") == nil)
        #expect(config.imageURL(nil) == nil)
        #expect(config.tokenEndpoint.absoluteString == "http://kc/realms/wely-realm/protocol/openid-connect/token")
        #expect(config.apiURL.absoluteString == "http://gw/api/v1")
    }
}
