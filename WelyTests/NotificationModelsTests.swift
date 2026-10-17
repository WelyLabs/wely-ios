import Foundation
import Testing
@testable import Wely

struct NotificationModelsTests {
    @Test func aDeviceIsRegisteredWithItsGateway() throws {
        let json = try JSONEncoder.wely.encode(ApnsDeviceRequest(token: "ab12", environment: .sandbox))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: String])
        #expect(object == ["token": "ab12", "environment": "SANDBOX", "kind": "ALERT"])
    }

    @Test func birthdayNotificationsHaveTheirIcons() {
        let icon = { (type: String) in
            AppNotification(id: "n", type: type, category: "BIRTHDAYS", title: "", body: "", link: nil, groupKey: nil, count: nil, actorId: nil,
                            createdAt: .now).systemImage
        }
        #expect(icon("BIRTHDAY_TODAY") == "birthday.cake.fill")
        #expect(icon("FRIEND_BIRTHDAY") == "gift.fill")
        #expect(icon("BIRTHDAY_SURPRISE_PROPOSAL") == "party.popper.fill")
        #expect(icon("BIRTHDAY_SURPRISE_CREATED") == "party.popper.fill")
    }

    @Test func birthdayPushesDefaultToOnAndAreSaved() throws {
        let older = try JSONDecoder.wely.decode(NotificationPreferences.self, from: Data(#"{"calls":true,"messages":false,"events":true,"friends":true}"#.utf8))
        #expect(older.birthdays)
        let off = try JSONDecoder.wely.decode(NotificationPreferences.self, from: Data(#"{"calls":true,"messages":true,"events":true,"friends":true,"birthdays":false}"#.utf8))
        #expect(!off.birthdays)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.wely.encode(off)) as? [String: Bool])
        #expect(object["birthdays"] == false)
    }

    @Test func aPushKitTokenIsRegisteredAsVoip() throws {
        let json = try JSONEncoder.wely.encode(ApnsDeviceRequest(token: "cd34", environment: .production, kind: .voip))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: String])
        #expect(object["kind"] == "VOIP")
    }
}
