import Foundation
import CryptoKit

@MainActor
enum ChatGPTAccount {
    static let resource = "https://api.openai.com/v1"
    static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    struct Profile: Codable, Equatable, Identifiable {
        var id: String
        var subject: String
        var email: String?
        var displayName: String { email ?? "ChatGPT" }
    }
    struct Session: Codable {
        var access: String
        var refresh: String
        var identity: String
        var expiry: Date
    }
    struct Vault: Codable {
        var profiles: [Profile] = []
        var active: String?
        var session: Session?
    }
    private struct Tokens: Decodable {
        var access_token: String
        var refresh_token: String?
        var id_token: String?
        var expires_in: Double
        var scope: String?
    }
    private static var refreshTask: Task<String, Error>?
    private static var generation = UUID()

    static func vault() throws -> Vault {
        guard let json = try KeyStore.read(account: "chatgpt") else { return Vault() }
        return try JSONDecoder().decode(Vault.self, from: Data(json.utf8))
    }
    private static func persist(_ vault: Vault) throws {
        try KeyStore.save(String(decoding: try JSONEncoder().encode(vault), as: UTF8.self), account: "chatgpt")
    }

    static func signIn(profile: Profile?) async throws {
        let verifier = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64URL }
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = UUID().uuidString, nonce = UUID().uuidString
        let host = UserDefaults.standard.string(forKey: "chatGPTHost") ?? "urn:uuid:" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(host, forKey: "chatGPTHost")
        let (callback, redirect) = try await SignInBrowser().authorize(state: state) { redirect in
            var components = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
            var fields = ["client_id": profile?.id ?? "dynamic_agent_client", "ext_agent_host_id": host,
                          "response_type": "code", "scope": scopes, "resource": resource, "state": state,
                          "nonce": nonce, "code_challenge": challenge, "code_challenge_method": "S256",
                          "redirect_uri": redirect.absoluteString]
            if profile == nil { fields["agent_name_hint"] = "Pocket Band AI" }
            else { fields["login_hint"] = profile?.email }
            components.queryItems = fields.map(URLQueryItem.init)
            return components.url!
        }
        let params = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func field(_ name: String) -> String? { params.first { $0.name == name }?.value }
        guard field("state") == state, field("error") == nil, let code = field("code"), !code.isEmpty,
              let client = field("client_id") ?? profile?.id, !client.isEmpty, client != "dynamic_agent_client",
              profile == nil || profile?.id == client else { throw StudyError.message(String(localized: "ChatGPTとの接続が承認されませんでした。")) }
        let tokens = try await exchange(["grant_type": "authorization_code", "client_id": client,
                                         "code": code, "code_verifier": verifier, "redirect_uri": redirect.absoluteString])
        guard let identity = tokens.id_token, let refresh = tokens.refresh_token,
              allowsInference(tokens.scope) else { throw StudyError.message(String(localized: "ChatGPTプランの利用を許可してください。")) }
        let claims = try await ChatGPTIdentity.verify(identity, client: client, nonce: nonce)
        guard profile == nil || profile?.subject == claims.sub else { throw StudyError.message(String(localized: "選択したアカウントと一致しません。")) }
        var saved = try vault()
        let newProfile = Profile(id: client, subject: claims.sub, email: claims.email)
        saved.profiles.removeAll { $0.id == client }
        saved.profiles.append(newProfile)
        saved.active = client
        saved.session = Session(access: tokens.access_token, refresh: refresh, identity: identity,
                                expiry: Date().addingTimeInterval(tokens.expires_in))
        try Task.checkCancellation()
        try persist(saved)
        invalidatePendingRefresh()
    }

    static func accessToken() async throws -> String? {
        let saved = try vault()
        guard let client = saved.active, let session = saved.session else { return nil }
        if session.expiry.timeIntervalSinceNow > 90 { return session.access }
        if let refreshTask { return try await refreshTask.value }
        let current = generation
        let task = Task<String, Error> {
            defer { if current == generation { refreshTask = nil } }
            let tokens = try await exchange(["grant_type":"refresh_token", "client_id":client, "refresh_token":session.refresh])
            guard current == generation else { throw CancellationError() }
            guard tokens.scope == nil || allowsInference(tokens.scope) else { throw StudyError.message(String(localized: "ChatGPTの利用許可を再確認してください。")) }
            var updated = saved
            updated.session = Session(access: tokens.access_token, refresh: tokens.refresh_token ?? session.refresh,
                                      identity: session.identity, expiry: Date().addingTimeInterval(tokens.expires_in))
            try persist(updated)
            return tokens.access_token
        }
        refreshTask = task
        return try await task.value
    }

    static func signOut() async throws {
        var saved = try vault()
        guard let client = saved.active, let session = saved.session else { return }
        invalidatePendingRefresh()
        saved.active = nil
        saved.session = nil
        try persist(saved)
        let (_, response) = try await URLSession.shared.data(for: form("revoke", ["client_id":client, "token":session.refresh, "token_type_hint":"refresh_token"]))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw StudyError.message(String(localized: "端末からログアウトしました。ChatGPT設定から接続状態を確認してください。"))
        }
    }

    private static func invalidatePendingRefresh() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
    }
    private static func allowsInference(_ scope: String?) -> Bool {
        let granted = Set((scope ?? "").split(separator: " "))
        return granted.contains("resource.invoke") && granted.contains("chatgpt.tokens.use.direct")
    }
    private static func form(_ path: String, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/" + path)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = Data(fields.map { key, value in key + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }.joined(separator:"&").utf8)
        return request
    }
    private static func exchange(_ fields: [String: String]) async throws -> Tokens {
        var fields = fields
        fields["resource"] = resource
        let (data, response) = try await URLSession.shared.data(for: form("token", fields))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw StudyError.message(String(localized: "ChatGPTにもう一度サインインしてください。")) }
        return try JSONDecoder().decode(Tokens.self, from: data)
    }
}
