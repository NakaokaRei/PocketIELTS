import ComposableArchitecture
import SwiftUI

@main
struct PocketIELTSApp: App {
    let store: StoreOf<StudyFeature>
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let suite = "PocketIELTS.UITests"
            let defaults = UserDefaults(suiteName: suite)!
            if ProcessInfo.processInfo.arguments.contains("--ui-reset") { defaults.removePersistentDomain(forName: suite) }
            store = withDependencies {
                $0.defaultAppStorage = defaults
                $0[AccountClient.self] = AccountClient(status: { .init() }, signIn: { _ in throw StudyError.message("UIテストでは認証しません。") }, signOut: {})
            } operation: { Store(initialState: StudyFeature.State()) { StudyFeature() } }
            return
        }
        #endif
        store = Store(initialState: StudyFeature.State()) { StudyFeature() }
    }

    var body: some Scene {
        WindowGroup { StudyCloudHost(store: store).tint(StudyColors.accent) }
    }
}
