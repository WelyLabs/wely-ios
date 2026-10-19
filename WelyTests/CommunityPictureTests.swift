import Foundation
import Testing
@testable import Wely

struct CommunityPictureTests {
    private func decode(_ json: String) throws -> Community {
        try JSONDecoder.wely.decode(Community.self, from: Data(json.utf8))
    }

    private func social() -> SocialService {
        let session = AuthSession(store: InMemoryTokenStore(TokenSet(accessToken: "t", refreshToken: nil, idToken: nil, expiresAt: .distantFuture)))
        return SocialService(api: APIClient(session: session, http: DemoTransport()))
    }

    @Test func decodesTheSignedUrlOfItsPicture() throws {
        let community = try decode("""
        {"communityId":"c1","name":"Club","description":null,"interests":[],"visibility":"PUBLIC","createdAt":null,
         "memberCount":3,"role":"ADMIN","friendMembers":[],"friendMemberCount":0,"pictureUrl":"https://media/c1.jpg"}
        """)
        #expect(community.pictureUrl == "https://media/c1.jpg")
    }

    @Test func decodesACommunityWithoutPicture_fromAnOlderBackendToo() throws {
        let withNull = try decode(#"{"communityId":"c1","name":"Club","visibility":"PUBLIC","memberCount":1,"pictureUrl":null}"#)
        let without = try decode(#"{"communityId":"c1","name":"Club","visibility":"PUBLIC","memberCount":1}"#)
        #expect(withNull.pictureUrl == nil)
        #expect(without.pictureUrl == nil)
    }

    @Test func wordsThePictureErrorsInFrench() {
        #expect(ErrorMessages.text(for: "SCL-BUS-020")?.contains("JPEG") == true)
        #expect(ErrorMessages.text(for: "SCL-BUS-021")?.contains("10 Mo") == true)
        #expect(ErrorMessages.text(for: "SCL-TEC-004")?.contains("Réessayez") == true)
    }

    @Test func readsTheFileOfAMultipartBody() {
        let body = Data("--b\r\nContent-Disposition: form-data; name=\"file\"; filename=\"p.jpg\"\r\nContent-Type: image/jpeg\r\n\r\nJPEG\r\n--b--\r\n".utf8)
        #expect(DemoStore.uploadedFile(in: body) == Data("JPEG".utf8))
        #expect(DemoStore.uploadedFile(in: Data("no parts".utf8)) == nil)
        #expect(DemoStore.uploadedFile(in: nil) == nil)
    }

    @Test func anAdminSetsThenRemovesThePictureInTheDemo() async throws {
        let social = social()
        let created = try await social.createCommunity(CommunityRequest(name: "Mon club", description: nil, interests: [], visibility: .public))
        #expect(created.pictureUrl == nil)

        let withPicture = try await social.uploadCommunityPicture(created.communityId, jpeg: Data("JPEG".utf8))
        let url = try #require(withPicture.pictureUrl.flatMap(URL.init(string:)))
        #expect(try Data(contentsOf: url) == Data("JPEG".utf8))
        #expect(try await social.community(created.communityId).pictureUrl == withPicture.pictureUrl)

        let removed = try await social.removeCommunityPicture(created.communityId)
        #expect(removed.pictureUrl == nil)
    }

    @Test func aMemberCannotChangeThePictureInTheDemo() async {
        await #expect {
            _ = try await social().uploadCommunityPicture("club-auto", jpeg: Data("JPEG".utf8))
        } throws: { error in
            (error as? APIError)?.code == "SCL-BUS-011"
        }
    }
}
