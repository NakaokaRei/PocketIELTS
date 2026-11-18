import ComposableArchitecture


struct CredentialClient: DependencyKey {
    var isConfigured: @Sendable () throws -> Bool
    var save: @Sendable (String) throws -> Void
    var remove: @Sendable () throws -> Void

    static let liveValue = Self(isConfigured: { try KeyStore.read() != nil },
                                save: { try KeyStore.save($0) },
                                remove: { try KeyStore.remove() })
}
