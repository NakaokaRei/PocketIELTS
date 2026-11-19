import Foundation
import CryptoKit
import Security

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL: String) {
        var padded = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        self.init(base64Encoded: padded)
    }
}

enum ChatGPTIdentity {
    struct Claims: Decodable {
        var iss: String
        var aud: [String]
        var sub: String
        var exp: Double
        var nonce: String
        var email: String?
        var azp: String?

        enum CodingKeys: String, CodingKey { case iss, aud, sub, exp, nonce, email, azp }

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            iss = try fields.decode(String.self, forKey: .iss)
            if let one = try? fields.decode(String.self, forKey: .aud) { aud = [one] }
            else { aud = try fields.decode([String].self, forKey: .aud) }
            sub = try fields.decode(String.self, forKey: .sub)
            exp = try fields.decode(Double.self, forKey: .exp)
            nonce = try fields.decode(String.self, forKey: .nonce)
            email = try fields.decodeIfPresent(String.self, forKey: .email)
            azp = try fields.decodeIfPresent(String.self, forKey: .azp)
        }
    }

    struct Header: Decodable { var alg: String; var kid: String }
    struct JWK: Decodable { var kid: String; var kty: String; var n: String?; var e: String? }
    struct KeySet: Decodable { var keys: [JWK] }

    static func verify(_ jwt: String, client: String, nonce: String) async throws -> Claims {
        let parts = jwt.components(separatedBy: ".")
        let invalid = StudyError.message("ChatGPTの本人確認に失敗しました。")
        guard parts.count == 3, let headerData = Data(base64URL: parts[0]),
              let payload = Data(base64URL: parts[1]), let signature = Data(base64URL: parts[2])
        else { throw invalid }
        let header = try JSONDecoder().decode(Header.self, from: headerData)
        guard header.alg == "RS256" else { throw invalid }
        let (data, response) = try await URLSession.shared.data(from: URL(string: "https://auth.openai.com/.well-known/jwks.json")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw invalid }
        let keys = try JSONDecoder().decode(KeySet.self, from: data)
        guard let key = keys.keys.first(where: { $0.kid == header.kid && $0.kty == "RSA" }),
              let modulus = key.n.flatMap({ Data(base64URL: $0) }), !modulus.isEmpty,
              let exponent = key.e.flatMap({ Data(base64URL: $0) }), !exponent.isEmpty else { throw invalid }
        let der = tagged(0x30, integer(modulus) + integer(exponent))
        let attributes = [kSecAttrKeyClass: kSecAttrKeyClassPublic, kSecAttrKeyType: kSecAttrKeyTypeRSA] as CFDictionary
        guard let rsa = SecKeyCreateWithData(der as CFData, attributes, nil),
              SecKeyVerifySignature(rsa, .rsaSignatureMessagePKCS1v15SHA256,
                                    Data((parts[0] + "." + parts[1]).utf8) as CFData, signature as CFData, nil)
        else { throw invalid }
        let claims = try JSONDecoder().decode(Claims.self, from: payload)
        guard claims.iss == "https://auth.openai.com", claims.aud.contains(client),
              (claims.azp == client || (claims.azp == nil && claims.aud.count == 1)),
              !claims.sub.isEmpty, claims.nonce == nonce, claims.exp > Date().timeIntervalSince1970 else { throw invalid }
        return claims
    }

    private static func integer(_ bytes: Data) -> Data {
        tagged(0x02, (bytes.first! >= 128 ? Data([0]) : Data()) + bytes)
    }

    private static func tagged(_ tag: UInt8, _ content: Data) -> Data {
        var length = content.count
        var bytes: [UInt8] = []
        repeat { bytes.insert(UInt8(length & 255), at: 0); length >>= 8 } while length > 0
        let prefix: [UInt8] = content.count < 128 ? bytes : [0x80 | UInt8(bytes.count)] + bytes
        return Data([tag] + prefix) + content
    }
}
