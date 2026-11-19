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
    @State private var preferredCompactColumn = NavigationSplitViewColumn.detail

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
                    List {
                        sidebarRow(String(localized: "ホーム"), symbol: "house", tag: 0)
                        sidebarRow(String(localized: "学習記録"), symbol: "chart.bar", tag: 1)
                        sidebarRow(String(localized: "単語帳"), symbol: "book", tag: 2)
                    }
                    .navigationTitle("Pocket IELTS")
                    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
                } detail: {
                    NavigationStack(path: $homePath) {
                        switch selectedTab {
                        case 1: progress().navigationTitle(String(localized: "学習記録"))
                        case 2: vocabulary().navigationTitle(String(localized: "単語帳"))
                        default: home()
                        }
                    }.id(homeID)
                }
                .navigationSplitViewStyle(.balanced)
                .id(homeID)
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack(path: $homePath) { home() }.id(homeID)
                        .tabItem { Label(String(localized: "ホーム"), systemImage: "house") }.tag(0)
                    NavigationStack { progress().navigationTitle(String(localized: "学習記録")) }
                        .tabItem { Label(String(localized: "学習記録"), systemImage: "chart.bar") }.tag(1)
                    NavigationStack { vocabulary().navigationTitle(String(localized: "単語帳")) }
                        .tabItem { Label(String(localized: "単語帳"), systemImage: "book") }.tag(2)
                }
            }
        }
        .environment(\.studyNavigation, StudyNavigationActions(
            home: { homePath = NavigationPath(); homeID = UUID(); selectedTab = 0 },
            progress: { homePath = NavigationPath(); homeID = UUID(); selectedTab = 1 }
        ))
    }
    private func sidebarRow(_ title: String, symbol: String, tag: Int) -> some View {
        Button {
            homePath = NavigationPath(); homeID = UUID(); selectedTab = tag; preferredCompactColumn = .detail
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
        }
        .listRowBackground(selectedTab == tag ? StudyColors.accent.opacity(0.14) : Color.clear)
        .accessibilityIdentifier("navigation.\(tag)")
        .accessibilityAddTraits(selectedTab == tag ? .isSelected : [])
    }

}
