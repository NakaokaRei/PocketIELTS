import ComposableArchitecture
import Foundation

@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var configured = false
        var error: String?
        var didSave = false
    }
    enum Action {
        case opened, remove
        case save(String)
    }

    @Dependency(CredentialClient.self) var credentials

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            state.error = nil
            state.didSave = false
            do {
                switch action {
                case .opened:
                    state.configured = try credentials.isConfigured()
                case let .save(value):
                    let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { return .none }
                    try credentials.save(key)
                    state.configured = true
                    state.didSave = true
                case .remove:
                    try credentials.remove()
                    state.configured = false
                }
            } catch { state.error = error.localizedDescription }
            return .none
        }
    }
}
