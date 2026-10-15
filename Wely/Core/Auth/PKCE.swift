import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636): what lets a public client like this app use the
/// authorization code flow without a secret.
struct PKCE: Sendable {
    let verifier: String
    let challenge: String
    let state: String

    init(verifier: String = PKCE.randomString(), state: String = PKCE.randomString(byteCount: 16)) {
        self.verifier = verifier
        self.challenge = PKCE.challenge(for: verifier)
        self.state = state
    }

    /// S256: base64url of the verifier's SHA-256.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    static func randomString(byteCount: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64URLEncoded()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
