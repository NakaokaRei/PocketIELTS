import ComposableArchitecture
import SwiftUI

struct SettingsScreen: View {
    @Environment(\.dismiss) var dismiss
    let store: StoreOf<SettingsFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let active = store.account.active {
                        LabeledContent("接続中", value: store.account.profiles.first { $0.id == active }?.displayName ?? "ChatGPT")
                        Link("利用状況を確認", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                        Button("サインアウト", role: .destructive) { store.send(.signOut) }
                    } else {
                        ForEach(store.account.profiles) { profile in
                            Button(profile.displayName) { store.send(.signIn(profile)) }
                        }
                        Button("Sign in with ChatGPT") { store.send(.signIn(nil)) }
                    }
                    if store.connecting { ProgressView("接続中…") }
                } header: { Text("ChatGPT アカウント") }
                  footer: { Text("問題の生成とAI解説に、接続したChatGPTプランの利用枠を使います。") }
                  .disabled(store.connecting)
                if let error = store.error { Text(error).foregroundStyle(StudyColors.error) }
            }
            .interactiveDismissDisabled(store.connecting)
            .navigationTitle("設定")
            .toolbar { Button("完了") { dismiss() }.disabled(store.connecting) }
            .onAppear {
                store.send(.opened)
                store.send(.refreshAccount)
            }

        }
    }
}

#Preview("設定 · Light") {
    SettingsScreen(store: Store(initialState: SettingsFeature.State()) { SettingsFeature() })
        .tint(StudyColors.accent).preferredColorScheme(.light)
}

#Preview("設定 · Dark") {
    SettingsScreen(store: Store(initialState: SettingsFeature.State()) { SettingsFeature() })
        .tint(StudyColors.accent).preferredColorScheme(.dark)
}
