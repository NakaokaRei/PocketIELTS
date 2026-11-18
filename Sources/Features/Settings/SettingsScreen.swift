import ComposableArchitecture
import SwiftUI

struct SettingsScreen: View {
    @Environment(\.dismiss) var dismiss
    @State private var draft = ""
    let store: StoreOf<SettingsFeature>
    private var saved: Bool { store.configured }
    @State private var confirmRemoval = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("APIキー", value: saved ? "設定済み" : "未設定")
                    SecureField(saved ? "新しいキーを入力" : "キーを入力", text: $draft)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("OpenAI API") }
                  footer: { Text("このiPhoneのキーチェーンに保存します。問題生成・質問にはご自身のOpenAI API利用枠を使用します。") }
                Section {
                    Button("保存") {
                        store.send(.save(draft))
                        if store.didSave { draft = ""; dismiss() }
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if saved { Button("キーを削除", role: .destructive) { confirmRemoval = true } }
                }
                if let error = store.error { Text(error).foregroundStyle(StudyColors.error) }
            }
            .navigationTitle("設定")
            .toolbar { Button("完了") { dismiss() } }
            .onAppear {
                store.send(.opened)
            }
            .confirmationDialog("APIキーを削除しますか？", isPresented: $confirmRemoval) {
                Button("削除", role: .destructive) {
                    store.send(.remove)
                    draft = ""
                }
            }
        }
    }
}
