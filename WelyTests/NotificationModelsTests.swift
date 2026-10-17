import Foundation
import Testing
@testable import Wely

struct NotificationModelsTests {
    @Test func aDeviceIsRegisteredWithItsGateway() throws {
        let json = try JSONEncoder.wely.encode(ApnsDeviceRequest(token: "ab12", environment: .sandbox))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: String])
        #expect(object == ["token": "ab12", "environment": "SANDBOX", "kind": "ALERT"])
    }

    @Test func aPushKitTokenIsRegisteredAsVoip() throws {
        let json = try JSONEncoder.wely.encode(ApnsDeviceRequest(token: "cd34", environment: .production, kind: .voip))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: String])
        #expect(object["kind"] == "VOIP")
    }
}
