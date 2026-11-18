import ComposableArchitecture

struct AccountClient: DependencyKey {
    struct Status: Equatable {
        var profiles: [ChatGPTAccount.Profile] = []
        var active: String?
    }
    var status: @Sendable () async throws -> Status
    var signIn: @Sendable (ChatGPTAccount.Profile?) async throws -> Void
    var signOut: @Sendable () async throws -> Void
    static let liveValue = Self(status: {
        let vault = try await ChatGPTAccount.vault()
        return Status(profiles: vault.profiles, active: vault.active)
    }, signIn: { try await ChatGPTAccount.signIn(profile: $0) }, signOut: { try await ChatGPTAccount.signOut() })
    static let testValue = Self(
        status: { throw StudyError.message("AccountClient.status is not configured for this test") },
        signIn: { _ in throw StudyError.message("AccountClient.signIn is not configured for this test") },
        signOut: { throw StudyError.message("AccountClient.signOut is not configured for this test") }
    )
    static let previewValue = Self(status: { Status() }, signIn: { _ in }, signOut: {})
}
