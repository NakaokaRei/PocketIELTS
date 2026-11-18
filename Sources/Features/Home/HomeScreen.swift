import ComposableArchitecture
import SwiftUI

struct HomeScreen: View {
    let store: StoreOf<StudyFeature>
    @State private var settings = false
    @State private var practice = false
    @State private var section = 1
    private var configured: Bool { store.settings.configured }

    var body: some View {
        IELTSNavigation {
            List {
                Section("Reading") {
                    Picker("練習するパート", selection: $section) {
                        ForEach(1...3, id: \.self) { Text("Section \($0)").tag($0) }
                    }
                    Text(["生活に関する文書 · 13問", "職場に関する文書 · 13問", "一般的な話題の長文 · 14問"][section-1])
                        .foregroundStyle(StudyColors.secondaryText)
                    Button {
                        if configured {
                            store.send(.start(section))
                            practice = true
                        } else { settings = true }
                    } label: {
                        Label(configured ? "練習を始める" : "APIキーを設定して始める", systemImage: configured ? "play.fill" : "key")
                    }
                }
            }
            .navigationTitle("Pocket IELTS")
            .toolbar {
                Button { settings = true } label: { Label("設定", systemImage: "gearshape") }
            }
        } progress: {
            List {
                if store.results.isEmpty { Text("練習を採点すると、ここに結果が表示されます。") }
                ForEach(Array(store.results.enumerated()), id: \.offset) { Text($0.element) }
            }
        } vocabulary: {
            List {
                if store.entries.isEmpty { Text("本文や設問を長押しして、表現を追加できます。") }
                ForEach(store.entries, id: \.self) { Text($0) }
            }
        }
        .onAppear { store.send(.settings(.opened)) }
        .sheet(isPresented: $settings) { SettingsScreen(store: store.scope(state: \.settings, action: \.settings)) }
        .fullScreenCover(isPresented: $practice, onDismiss: { store.send(.finish) }) {
            PracticeScreen(store: store)
        }
    }
}
