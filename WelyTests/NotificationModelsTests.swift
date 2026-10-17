import Foundation
import Testing
@testable import Wely

struct NotificationModelsTests {
    @Test func aDeviceIsRegisteredWithItsGateway() throws {
        let json = try JSONEncoder.wely.encode(ApnsDeviceRequest(token: "ab12", environment: .sandbox))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: String])
        #expect(object == ["token": "ab12", "environment": "SANDBOX"])
    }
}
