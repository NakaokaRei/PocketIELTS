import SwiftUI

/// Hosts the app's existing content in system-owned tabs and navigation stacks.
struct IELTSNavigation<Home: View, Progress: View, Vocabulary: View>: View {
    @ViewBuilder let home: () -> Home
    @ViewBuilder let progress: () -> Progress
    @ViewBuilder let vocabulary: () -> Vocabulary

    var body: some View {
        TabView {
            NavigationStack { home() }
                .tabItem { Label("ホーム", systemImage: "house") }
            NavigationStack { progress().navigationTitle("学習記録") }
                .tabItem { Label("学習記録", systemImage: "chart.bar") }
            NavigationStack { vocabulary().navigationTitle("単語帳") }
                .tabItem { Label("単語帳", systemImage: "book") }
        }
    }
}
