import Foundation
import Testing
@testable import Wely

struct CallModelsTests {
    @Test func decodesACallEventFromWelyChat() throws {
        let event = try JSONDecoder.wely.decode(CallEvent.self, from: Data("""
        {"type":"TRACKS_PUBLISHED","actorId":"u2","call":{"id":"c1","conversationId":"conv1","startedBy":"u1",
         "media":"VIDEO","status":"ACTIVE","startedAt":"2026-10-17T10:00:00Z","endedAt":null,"memberIds":["u1","u2"],
         "participants":[{"userId":"u2","joinedAt":"2026-10-17T10:00:05Z","trackNames":["audio","camera"]}]}}
        """.utf8))
        #expect(event.type == .tracksPublished)
        #expect(event.call.media == .video)
        #expect(event.call.isLive)
        #expect(event.call.participants.first?.trackNames == [Call.audioTrack, Call.cameraTrack])
    }

    @Test func decodesTheIceServersOfAJoin() throws {
        let join = try JSONDecoder.wely.decode(CallJoin.self, from: Data("""
        {"call":{"id":"c1","conversationId":"conv1","startedBy":"u1","media":"AUDIO","status":"ENDED",
         "memberIds":[],"participants":[]},
         "iceServers":[{"urls":["stun:stun.cloudflare.com:3478"],"username":null,"credential":null},
                       {"urls":["turn:turn.cloudflare.com:3478"],"username":"u","credential":"p"}]}
        """.utf8))
        #expect(!join.call.isLive)
        #expect(join.iceServers.count == 2)
        #expect(join.iceServers[1].username == "u")
    }

    @Test func theGridPicksSmallerLayersAsItFills() {
        #expect(VideoLayer.forGrid(others: 1) == .full)
        #expect(VideoLayer.forGrid(others: 2) == .half)
        #expect(VideoLayer.forGrid(others: 3) == .half)
        #expect(VideoLayer.forGrid(others: 4) == .quarter)
    }

    @Test func anAudioTrackRequestCarriesNoLayer() throws {
        let json = try JSONEncoder.wely.encode(TrackRequest(userId: "u2", trackName: Call.audioTrack, layer: nil))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["trackName"] as? String == "audio")
        #expect(object["layer"] == nil)
    }
}
