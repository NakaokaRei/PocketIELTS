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
        WindowGroup {
            StudyCloudHost(store: store).tint(StudyColors.accent)
                .font(StudyTypography.body)
                .background(WindowAppearance(preference: store.settings.appearance))
        }
    }
}

/// Apply the preference to the scene's window so presented sheets inherit the same traits.
private struct WindowAppearance: UIViewRepresentable {
    let preference: String

    final class ObserverView: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { applyStyle() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyStyle()
        }

        private func applyStyle() {
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            window.overrideUserInterfaceStyle = style
        }
    }

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        switch preference {
        case "light": view.style = .light
        case "dark": view.style = .dark
        default: view.style = .unspecified
        }
    }
}
