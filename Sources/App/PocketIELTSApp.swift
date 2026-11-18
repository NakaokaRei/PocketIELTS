import ComposableArchitecture
import SwiftUI

@main
struct PocketIELTSApp: App {
    let store = Store(initialState: StudyFeature.State()) { StudyFeature() }

    var body: some Scene {
        WindowGroup { HomeScreen(store: store).tint(StudyColors.accent) }
    }
}
