import SwiftUI

struct StudyNavigationActions {
    var home: () -> Void = {}
    var progress: () -> Void = {}
}
private struct StudyNavigationKey: EnvironmentKey {
    static let defaultValue = StudyNavigationActions()
}
extension EnvironmentValues {
    var studyNavigation: StudyNavigationActions {
        get { self[StudyNavigationKey.self] }
        set { self[StudyNavigationKey.self] = newValue }
    }
}

/// System tabs retain native accessibility; actions let a completed session return to its root.
struct IELTSNavigation<Home: View, Progress: View, Vocabulary: View>: View {
    @ViewBuilder let home: () -> Home
    @ViewBuilder let progress: () -> Progress
    @ViewBuilder let vocabulary: () -> Vocabulary
    @State private var selectedTab = 0
    @State private var homePath = NavigationPath()
    @State private var homeID = UUID()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homePath) { home() }.id(homeID)
                .tabItem { Label("ホーム", systemImage: "house") }.tag(0)
            NavigationStack { progress().navigationTitle("学習記録") }
                .tabItem { Label("学習記録", systemImage: "chart.bar") }.tag(1)
            NavigationStack { vocabulary().navigationTitle("単語帳") }
                .tabItem { Label("単語帳", systemImage: "book") }.tag(2)
        }
        .environment(\.studyNavigation, StudyNavigationActions(
            home: { homePath = NavigationPath(); homeID = UUID(); selectedTab = 0 },
            progress: { homePath = NavigationPath(); homeID = UUID(); selectedTab = 1 }
        ))
    }
}
