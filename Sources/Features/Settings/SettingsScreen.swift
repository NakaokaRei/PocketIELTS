import ComposableArchitecture
import SwiftUI

struct SettingsScreen: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.studyCloud) private var cloud
    let store: StoreOf<SettingsFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "カラーモード"), selection: Binding(get: { store.appearance }, set: { store.send(.setAppearance($0)) })) {
                        Text(String(localized: "システム")).tag("system")
                        Text(String(localized: "ライト")).tag("light")
                        Text(String(localized: "ダーク")).tag("dark")
                    }.pickerStyle(.segmented).accessibilityIdentifier("settings.appearance")
                } header: { Text(String(localized: "表示")) }
                footer: { Text(String(localized: "システムを選ぶと、端末の外観設定に合わせて切り替わります。")) }

                Section {
                    if let active = store.account.active {
                        LabeledContent(String(localized: "接続中"), value: store.account.profiles.first { $0.id == active }?.displayName ?? "ChatGPT")
                        Link(String(localized: "利用状況を確認"), destination: URL(string: "https://chatgpt.com/settings/usage")!)
                        Button(String(localized: "サインアウト"), role: .destructive) { store.send(.signOut) }
                    } else {
                        ForEach(store.account.profiles) { profile in
                            Button(profile.displayName) { store.send(.signIn(profile)) }
                        }
                        Button("Sign in with ChatGPT") { store.send(.signIn(nil)) }
                    }
                    if store.connecting { ProgressView(String(localized: "接続中…")) }
                } header: { Text(String(localized: "ChatGPT アカウント")) }
                  footer: { Text(String(localized: "問題の生成とAI解説に、接続したChatGPTプランの利用枠を使います。")) }
                  .disabled(store.connecting)
                if let cloud {
                    Section {
                        Toggle(String(localized: "iCloudで同期"), isOn: Binding(get: { cloud.enabled }, set: { cloud.enabled = $0; if $0 { Task { await cloud.sync() } } }))
                            .accessibilityIdentifier("settings.icloud")
                        Label(cloud.status, systemImage: cloud.syncing ? "arrow.triangle.2.circlepath.icloud" : "icloud")
                            .font(.subheadline)
                        if let date = cloud.lastSynced { LabeledContent(String(localized: "前回の同期"), value: date.formatted(date: .abbreviated, time: .shortened)) }
                        Button(String(localized: "今すぐ同期")) { Task { await cloud.sync() } }.disabled(!cloud.enabled || cloud.syncing)
                    } header: { Text("iCloud") }
                    footer: { Text(String(localized: "同じApple AccountのiPhone・iPadで、単語帳・保存した問題・学習履歴・回答・講評・録音を同期します。オフラインでも保存でき、アプリ使用中に再同期します。ChatGPTの接続は端末ごとに設定してください。")) }
                }
                if let error = store.error { Text(error).foregroundStyle(StudyColors.error) }
            }
            .preferredColorScheme(store.appearance == "light" ? .light : store.appearance == "dark" ? .dark : nil)
            .interactiveDismissDisabled(store.connecting)
            .navigationTitle(String(localized: "設定"))
            .toolbar { Button(String(localized: "完了")) { dismiss() }.disabled(store.connecting) }
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
