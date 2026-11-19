import ComposableArchitecture
import Foundation

@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage("appearance")) var appearance = "system"
        var account = AccountClient.Status()
        var connecting = false
        var canPractice: Bool { account.active != nil }
        var error: String?
    }
    enum Action {
        case refreshAccount, signIn(ChatGPTAccount.Profile?), signOut
        case accountChanged(AccountClient.Status, String?)
        case opened
        case setAppearance(String)
    }

    @Dependency(AccountClient.self) var accounts

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            state.error = nil
            do {
                switch action {
                case let .setAppearance(value):
                    guard ["system", "light", "dark"].contains(value) else { return .none }
                    state.$appearance.withLock { $0 = value }
                    return .none
                case .refreshAccount, .signIn, .signOut:
                    guard !state.connecting else { return .none }
                    if case .refreshAccount = action {} else { state.connecting = true }
                    return .run { send in
                        var message: String?
                        do {
                            switch action {
                            case let .signIn(profile): try await accounts.signIn(profile)
                            case .signOut: try await accounts.signOut()
                            default: break
                            }
                        } catch is CancellationError {
                        } catch { message = error.localizedDescription }
                        do { await send(.accountChanged(try await accounts.status(), message)) }
                        catch { await send(.accountChanged(.init(), error.localizedDescription)) }
                    }
                case let .accountChanged(status, error):
                    state.account = status
                    state.error = error
                    state.connecting = false
                case .opened:
                    // Remove credentials left by versions that offered personal API keys.
                    try KeyStore.remove(account: "personal")
                }
            } catch { state.error = error.localizedDescription }
            return .none
        }
    }
}
