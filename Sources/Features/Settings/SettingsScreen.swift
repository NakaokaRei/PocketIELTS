import ComposableArchitecture
import SwiftUI

struct SettingsScreen: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.studyCloud) private var cloud
    let store: StoreOf<SettingsFeature>
    @AppStorage(SpeakingModel.preferenceKey) private var speakingModel = SpeakingModel.mini.rawValue
    @AppStorage(SpeechAudio.preparationPreference) private var prepareAudio = false
    @AppStorage(QuestionImage.preferenceKey) private var generateImages = false
    @AppStorage(SectionPreparation.preference) private var prepareAhead = false
    @State private var speechKey = ""
    @State private var speechKeySaved = false
    @State private var speechKeyError: String?

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
                        Button(String(localized: "Sign in with ChatGPT")) { store.send(.signIn(nil)) }.accessibilityIdentifier("settings.signIn")
                    }
                    if store.connecting { ProgressView(String(localized: "接続中…")) }
                } header: { Text(String(localized: "ChatGPT アカウント")) }
                  footer: { Text(String(localized: "問題の生成とAI解説に、接続したChatGPTプランの利用枠を使います。")) }
                  .disabled(store.connecting)
                Section {
                    Toggle(String(localized: "Prepare the next questions automatically"), isOn: $prepareAhead)
                        .accessibilityIdentifier("settings.prepareAhead")
                } footer: {
                    Text(String(localized: "While you use the app, prepare one exercise per section using your connected ChatGPT plan. Open the answer review to prepare the next exercise."))
                }
                Section {
                    Toggle(String(localized: "Generate audio with new listening exercises"), isOn: $prepareAudio)
                        .accessibilityIdentifier("settings.prepareListeningAudio")
                    Label(speechKeySaved ? String(localized: "APIキーを保存済み") : String(localized: "APIキーが未設定です"), systemImage: speechKeySaved ? "checkmark.shield" : "key")
                    SecureField(String(localized: "音声生成用APIキー"), text: $speechKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        .accessibilityIdentifier("settings.speechKey")
                    Button(String(localized: "APIキーを保存")) {
                        do {
                            try KeyStore.save(speechKey.trimmingCharacters(in: .whitespacesAndNewlines), account: SpeechCredentials.account)
                            speechKey = ""; speechKeySaved = true; speechKeyError = nil
                        } catch { speechKeyError = error.localizedDescription }
                    }.disabled(speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if speechKeySaved {
                        Button(String(localized: "APIキーを削除"), role: .destructive) {
                            do { try KeyStore.remove(account: SpeechCredentials.account); speechKeySaved = false; speechKey = ""; speechKeyError = nil }
                            catch { speechKeyError = error.localizedDescription }
                        }
                    }
                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) { Label(String(localized: "APIキー取得ページを開く"), systemImage: "arrow.up.right.square") }
                    Link(destination: URL(string: "https://platform.openai.com/usage")!) { Label(String(localized: "APIの利用状況を確認"), systemImage: "chart.bar") }
                    if let speechKeyError { Text(speechKeyError).foregroundStyle(StudyColors.error) }
                } header: { Text(String(localized: "リスニング音声の生成")) }
                footer: { Text(String(localized: "音声生成はOpenAI APIを使用し、ChatGPTプランとは別に課金されます。キーはこの端末のKeychainに保存され、iCloudには同期されません。")) }
                Section {
                    Picker(String(localized: "会話モデル"), selection: $speakingModel) {
                        ForEach(SpeakingModel.allCases, id: \.rawValue) { model in
                            Text(model.title).tag(model.rawValue)
                        }
                    }.accessibilityIdentifier("settings.speakingModel")
                    Text(SpeakingModel.resolve(speakingModel).rawValue).font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                } header: { Text(String(localized: "Speaking 音声会話")) }
                footer: { Text(String(localized: "Miniが初期設定です。標準モデルは料金が高くなります。変更は次の会話から適用されます。リスニングと同じAPIキーを使用し、ChatGPTプランとは別に課金されます。")) }
                Section {
                    Toggle(String(localized: "Generate question images with OpenAI"), isOn: $generateImages)
                        .accessibilityIdentifier("settings.questionImages")
                    Text(QuestionImage.model).font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                    Link(String(localized: "APIの利用状況を確認"), destination: URL(string: "https://platform.openai.com/usage")!)
                } header: { Text(String(localized: "Question images")) }
                footer: { Text(String(localized: "Uses the same API key as audio. Image generation is billed separately from ChatGPT. Off by default; applies to new questions that need figures.")) }
                if let cloud {
                    Section {
                        Toggle(String(localized: "iCloudで同期"), isOn: Binding(get: { cloud.enabled }, set: { cloud.enabled = $0; if $0 { Task { await cloud.sync() } } }))
                            .accessibilityIdentifier("settings.icloud")
                        Label(cloud.status, systemImage: cloud.syncing ? "arrow.triangle.2.circlepath.icloud" : "icloud")
                            .font(StudyTypography.subheadline)
                        if let date = cloud.lastSynced { LabeledContent(String(localized: "前回の同期"), value: date.formatted(date: .abbreviated, time: .shortened)) }
                        Button(String(localized: "今すぐ同期")) { Task { await cloud.sync() } }.disabled(!cloud.enabled || cloud.syncing)
                    } header: { Text("iCloud") }
                    footer: { Text(String(localized: "同じApple AccountのiPhone・iPadで、単語帳・保存した問題・学習履歴・回答・講評・録音を同期します。オフラインでも保存でき、アプリ使用中に再同期します。ChatGPTの接続は端末ごとに設定してください。")) }
                }
                Section {
                    NavigationLink { OSSLicensesScreen() } label: {
                        Label(String(localized: "OSSライセンス"), systemImage: "doc.text")
                    }.accessibilityIdentifier("settings.licenses")
                }
                if let error = store.error { Text(error).foregroundStyle(StudyColors.error) }
            }
            .preferredColorScheme(store.appearance == "light" ? .light : store.appearance == "dark" ? .dark : nil)
            .interactiveDismissDisabled(store.connecting)
            .navigationTitle(String(localized: "設定"))
            .toolbar { Button(String(localized: "完了")) { dismiss() }.disabled(store.connecting) }
            .onDisappear { speechKey = "" }
            .onAppear {
                speechKeySaved = (try? KeyStore.read(account: SpeechCredentials.account)) != nil
                speakingModel = SpeakingModel.resolve(speakingModel).rawValue
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


struct OSSNotice: Identifiable {
    let id: String
    let title: String
    let text: String
    static func load(bundle: Bundle = .main) throws -> [Self] {
        func rows(_ resource: String) throws -> [[String: Any]] {
            guard let url = bundle.url(forResource: resource, withExtension: "plist", subdirectory: "Licenses"),
                  let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any],
                  let rows = plist["PreferenceSpecifiers"] as? [[String: Any]] else {
                throw StudyError.message(String(localized: "ライセンス情報を読み込めませんでした。"))
            }
            return rows
        }
        return try rows("Acknowledgements").compactMap { row in
            guard row["Type"] as? String == "PSChildPaneSpecifier", let file = row["File"] as? String, let title = row["Title"] as? String else { return nil }
            return try Self(id: file, title: title, text: rows(file).compactMap { $0["FooterText"] as? String }.joined(separator: "\n\n"))
        }
    }
}

struct OSSLicensesScreen: View {
    @State private var notices: [OSSNotice] = []
    @State private var error: String?
    var body: some View {
        List {
            Section {
                ForEach(notices) { notice in
                    NavigationLink(notice.title) {
                        ScrollView { Text(notice.text).font(.body).textSelection(.enabled).frame(maxWidth: 800, alignment: .leading).padding(20).frame(maxWidth: .infinity) }
                            .navigationTitle(notice.title).navigationBarTitleDisplayMode(.inline)
                    }
                }
            } footer: { Text(String(localized: "LicensePlistで生成した、ライブラリとフォントのライセンス一覧です。")) }
            if let error { Text(error).foregroundStyle(StudyColors.error) }
        }.navigationTitle(String(localized: "OSSライセンス")).navigationBarTitleDisplayMode(.inline)
            .task { do { notices = try OSSNotice.load() } catch { self.error = error.localizedDescription } }
    }
}
