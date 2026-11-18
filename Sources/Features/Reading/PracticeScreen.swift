import ComposableArchitecture
import SwiftUI

struct PracticeScreen: View {
    let store: StoreOf<StudyFeature>
    @State private var tutor = false
    @State private var context = ""
    @State private var question = ""
    @State private var saved = false

    var body: some View {
        IELTSPracticeSession(title: "Reading / Section \(store.section)", finish: { store.send(.finish) }) {
            ScrollView {
                VStack(alignment: .leading, spacing: StudySpacing.section) {
                    if store.loading { ProgressView("本文と設問を生成中…") }
                    if let error = store.error {
                        Text(error)
                        Button("もう一度生成") { store.send(.start(store.section)) }
                    }
                    if let set = store.session, !store.loading {
                        Text(set.title).font(StudyTypography.title)
                        ForEach(set.passages.indices, id: \.self) { i in selectable(set.passages[i], id: "passage-\(i)") }
                        Divider()
                        ForEach(set.questions.indices, id: \.self) { i in
                            let item = set.questions[i]
                            VStack(alignment: .leading, spacing: StudySpacing.related) {
                                Text("Question \([1,14,27][store.section-1] + i)").font(StudyTypography.headline)
                                if i == 0 || item.instruction != set.questions[i-1].instruction {
                                    selectable(item.instruction, id: "instructions-\(i)")
                                }
                                selectable(item.prompt, id: "question-\(i)")
                                TextField("解答", text: Binding(get: { store.answers[i] ?? "" }, set: { store.send(.answer(i, $0)) }))
                                    .textFieldStyle(.roundedBorder).disabled(store.reviewed)
                                if store.reviewed {
                                    Label(item.answers.joined(separator: " / "), systemImage: item.accepts(store.answers[i] ?? "") ? "checkmark.circle" : "xmark.circle")
                                    Text(item.explanation)
                                }
                            }
                        }
                        Button(store.reviewed ? "次のセットを生成" : "採点して解説を見る") {
                            if store.reviewed { store.send(.start(store.section)) } else { store.send(.review) }
                        }.buttonStyle(.borderedProminent)
                        Button("この問題をAIに質問") { openTutor(set.passages.joined(separator: "\n") + "\n" + set.questions.map(\.prompt).joined(separator: "\n")) }
                    }
                }.padding(.horizontal, StudySpacing.screenInset)
                    .padding(.vertical, StudySpacing.contentInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("単語帳に保存しました", isPresented: $saved) { Button("学習を続ける") {} }
        .sheet(isPresented: $tutor, onDismiss: { store.send(.closeQuestion) }) {
            NavigationStack {
                Form {
                    Section("質問") { TextField("何を知りたいですか？", text: $question, axis: .vertical) }
                    Button("送信", systemImage: "arrow.up.circle.fill") { store.send(.ask(context, question)) }
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.asking)
                    if store.asking { ProgressView() }
                    if let explanation = store.explanation { Section("回答") { Text(explanation).textSelection(.enabled) } }
                }.navigationTitle("AIに質問").toolbar { Button("完了") { tutor = false } }
            }
        }
    }

    private func selectable(_ text: String, id: String) -> some View {
        SelectableStudyText(text: text, sourceID: id) { entry in
            store.send(.save(entry.expression))
            saved = true
        } onAsk: { entry in openTutor(entry.sourceText + "\n選択範囲: " + entry.expression) }
    }

    private func openTutor(_ selection: String) {
        context = selection
        question = ""
        tutor = true
    }
}
