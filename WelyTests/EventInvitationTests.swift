import Foundation
import Testing
@testable import Wely

@MainActor
struct EventInvitationTests {
    private let config = AppConfig(gatewayURL: URL(string: "https://gw")!, keycloakURL: URL(string: "https://kc")!,
                                   webURL: URL(string: "https://web.wely")!)
    private let paris = TimeZone(identifier: "Europe/Paris")!

    private func events() -> EventService {
        let session = AuthSession(store: InMemoryTokenStore(TokenSet(accessToken: "t", refreshToken: nil, idToken: nil, expiresAt: .distantFuture)))
        return EventService(api: APIClient(session: session, http: DemoTransport()))
    }

    private func dinner(allDay: Bool = false, poll: Poll? = nil) -> FeedEvent {
        allDay
            ? FeedEvent(id: "e1", title: "Week-end", organizerId: "me", startDate: Date(timeIntervalSince1970: 1_761_264_000), // 2025-10-24T00:00Z
                        endDate: Date(timeIntervalSince1970: 1_761_436_800), allDay: true)
            : FeedEvent(id: "e1", title: "Dîner", organizerId: "me", startDate: Date(timeIntervalSince1970: 1_761_415_200), // 2025-10-25T18:00Z
                        poll: poll)
    }

    @Test func linksToTheEventPage_markedAsAnInvitation() {
        #expect(EventInvitation.link(eventId: "e1", config: config).absoluteString == "https://web.wely/event/e1?invitation")
    }

    @Test func readsTheEventOfAnInvitation_fromAnyOrigin() {
        #expect(EventInvitation.eventId(in: "Je t'invite : http://localhost/event/6713a0f1c2?invitation") == "6713a0f1c2")
        #expect(EventInvitation.eventId(in: "https://dev-web.welylabs.app/event/abc_D-9?invitation") == "abc_D-9")
    }

    @Test func ignoresAPlainLinkToAnEvent_orNoText() {
        #expect(EventInvitation.eventId(in: "https://web.wely/event/e1") == nil)
        #expect(EventInvitation.eventId(in: "https://web.wely/event/e1?invitations") == nil)
        #expect(EventInvitation.eventId(in: nil) == nil)
    }

    @Test func keepsTheWordsBeforeTheLink() {
        #expect(EventInvitation.intro(of: "Je t'invite à « Dîner » sur Wely : https://web.wely/event/e1?invitation") == "Je t'invite à « Dîner » sur Wely")
        #expect(EventInvitation.intro(of: "/event/e1?invitation") == "")
        #expect(EventInvitation.intro(of: "Rien") == "Rien")
    }

    @Test func saysTheDayAndTime_aWholeDay_orNothingWhileVoted() {
        #expect(EventInvitation.when(dinner(), timeZone: paris) == " le samedi 25 octobre à 20:00")
        #expect(EventInvitation.when(dinner(allDay: true), timeZone: paris) == " le vendredi 24 octobre")
        let poll = Poll(status: .open, slots: [PollSlot(id: "s1", start: .now, end: .now.addingTimeInterval(3600))])
        #expect(EventInvitation.when(dinner(poll: poll), timeZone: paris) == "")
    }

    @Test func writesTheSameMessageAsTheWeb() {
        let message = EventInvitation.message(for: dinner(allDay: true), config: config)
        #expect(message == "Je t'invite à « Week-end » le vendredi 24 octobre sur Wely : https://web.wely/event/e1?invitation")
        #expect(EventInvitation.eventId(in: message) == "e1")
    }

    @Test func decodesTheInvitations_fromAnOlderBackendToo() throws {
        let with = try JSONDecoder.wely.decode(EventParticipants.self, from: Data(#"{"count":1,"participantIds":["me"],"invitedIds":["lea"]}"#.utf8))
        let without = try JSONDecoder.wely.decode(EventParticipants.self, from: Data(#"{"count":1}"#.utf8))
        #expect(with.invitedIds == ["lea"])
        #expect(without.invitedIds == [])
    }

    @Test func wordsTheInvitationErrorsInFrench() {
        #expect(ErrorMessages.text(for: "EVT-BUS-036")?.contains("amis") == true)
        #expect(ErrorMessages.text(for: "EVT-BUS-039")?.contains("terminé") == true)
        #expect(ErrorMessages.text(for: "EVT-BUS-040")?.contains("participe déjà") == true)
    }

    /// Its own event: the demo's store is shared by the tests running alongside.
    private func privateDinner(_ events: EventService) async throws -> FeedEvent {
        try await events.create(EventCreateRequest(title: "Dîner \(UUID().uuidString)", startDate: .now.addingTimeInterval(86_400),
                                                   endDate: nil, location: "Chez moi", visibility: .private))
    }

    @Test func theOrganizerInvitesThenTakesBackAFriendInTheDemo() async throws {
        let events = events()
        let dinner = try await privateDinner(events)

        let invited = try await events.invite(dinner.id, friendId: "lea")
        #expect(invited.invitedIds == ["lea"])
        #expect(try await events.participants(dinner.id).invitedIds == ["lea"])

        try await events.withdrawInvitation(dinner.id, userId: "lea")
        #expect(try await events.participants(dinner.id).invitedIds == [])
    }

    @Test func theDemoRefusesAStrangerOrAnEventOfSomeoneElse() async {
        let events = events()

        let dinner = try? await privateDinner(events)
        await #expect(throws: (any Error).self) { try await events.invite(dinner?.id ?? "", friendId: "jules") }
        await #expect(throws: (any Error).self) { try await events.invite("demo-2", friendId: "hugo") }
    }
}
