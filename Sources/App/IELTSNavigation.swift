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

/// A stable destination identity lets every study link participate in the stack's path.
/// Content is captured when the link is followed; it is not persisted across launches.
struct StudyRoute: Hashable {
    let id: UUID
    let destination: AnyView
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
struct StudyLink<Destination: View, Label: View>: View {
    @State private var id = UUID()
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let label: () -> Label
    var body: some View {
        NavigationLink(value: StudyRoute(id: id, destination: AnyView(destination())), label: label)
    }
}

struct IELTSNavigation<Home: View, Progress: View, Vocabulary: View>: View {
    @ViewBuilder let home: () -> Home
    @ViewBuilder let progress: () -> Progress
    @ViewBuilder let vocabulary: () -> Vocabulary
    @State private var selectedTab = 0
    @State private var homePath = NavigationPath()
    @State private var progressPath = NavigationPath()
    @State private var vocabularyPath = NavigationPath()
    @State private var returning = false
    @State private var preferredCompactColumn = NavigationSplitViewColumn.detail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selectedPath: Binding<NavigationPath> {
        switch selectedTab {
        case 1: $progressPath
        case 2: $vocabularyPath
        default: $homePath
        }
    }
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
                    List {
                        sidebarRow(String(localized: "ホーム"), symbol: "house", tag: 0)
                        sidebarRow(String(localized: "学習記録"), symbol: "chart.bar", tag: 1)
                        sidebarRow(String(localized: "単語帳"), symbol: "book", tag: 2)
                    }.navigationTitle("Pocket IELTS")
                        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
                } detail: {
                    NavigationStack(path: selectedPath) {
                        Group {
                            switch selectedTab {
                            case 1: progress().navigationTitle(String(localized: "学習記録"))
                            case 2: vocabulary().navigationTitle(String(localized: "単語帳"))
                            default: home()
                            }
                        }.navigationDestination(for: StudyRoute.self) { $0.destination }
                    }
                }.navigationSplitViewStyle(.balanced)
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack(path: $homePath) { home().navigationDestination(for: StudyRoute.self) { $0.destination } }
                        .tabItem { Label(String(localized: "ホーム"), systemImage: "house") }.tag(0)
                    NavigationStack(path: $progressPath) {
                        progress().navigationTitle(String(localized: "学習記録"))
                            .navigationDestination(for: StudyRoute.self) { $0.destination }
                    }.tabItem { Label(String(localized: "学習記録"), systemImage: "chart.bar") }.tag(1)
                    NavigationStack(path: $vocabularyPath) {
                        vocabulary().navigationTitle(String(localized: "単語帳"))
                            .navigationDestination(for: StudyRoute.self) { $0.destination }
                    }.tabItem { Label(String(localized: "単語帳"), systemImage: "book") }.tag(2)
                }
            }
        }.environment(\.studyNavigation, StudyNavigationActions(home: { returnToRoot(tab: 0) }, progress: { returnToRoot(tab: 1) }))
    }
    private func returnToRoot(tab: Int) {
        guard !returning else { return }
        returning = true
        // Pop the existing stack; rebuilding it with a new ID bypasses native transitions.
        withAnimation(reduceMotion ? nil : .default, completionCriteria: .logicallyComplete) {
            homePath = NavigationPath(); progressPath = NavigationPath(); vocabularyPath = NavigationPath()
        } completion: {
            selectedTab = tab; preferredCompactColumn = .detail; returning = false
        }
    }
    private func sidebarRow(_ title: String, symbol: String, tag: Int) -> some View {
        Button {
            selectedTab = tag; preferredCompactColumn = .detail
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
        }.listRowBackground(selectedTab == tag ? StudyColors.accent.opacity(0.14) : Color.clear)
            .accessibilityIdentifier("navigation.\(tag)")
            .accessibilityAddTraits(selectedTab == tag ? .isSelected : [])
    }
}
