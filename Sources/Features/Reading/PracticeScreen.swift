import ComposableArchitecture
import SwiftUI

struct PracticeScreen: View {
    let store: StoreOf<StudyFeature>
    @State private var tutor = false
    @State private var context = ""
    @State private var saved = false
    @State private var vocabulary = false

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
                                    selectable(item.explanation, id: "explanation-\(i)")
                                }
                            }
                        }
                        Button(store.reviewed ? "次のセットを生成" : "採点して解説を見る") {
                            if store.reviewed { store.send(.start(store.section)) } else { store.send(.review) }
                        }.buttonStyle(.borderedProminent)
                        Button("この問題を保存", systemImage: "bookmark") {
                            store.send(.savePaper(ExamUnit(id: "Reading / Section \(store.section) · " + set.title,
                                skill: "Reading", title: set.title, directions: "", passages: set.passages,
                                questions: set.questions, audio: nil, oral: [])))
                            saved = true
                        }
                        Button("この問題をAIに質問") { openTutor(set.passages.joined(separator: "\n") + "\n" + set.questions.map(\.prompt).joined(separator: "\n")) }
                    }
                }.padding(.horizontal, StudySpacing.screenInset)
                    .padding(.vertical, StudySpacing.contentInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("保存しました", isPresented: $saved) { Button("学習を続ける") {} }
        .sheet(isPresented: $vocabulary) { NavigationStack { VocabularyScreen(store: store).navigationTitle("単語帳").toolbar { Button("完了") { vocabulary = false } } } }
        .sheet(isPresented: $tutor, onDismiss: { store.send(.closeQuestion) }) {
            TutorScreen(store: store, context: context)
        }
    }

    private func selectable(_ text: String, id: String) -> some View {
        SelectableStudyText(text: text, sourceID: id) { entry in
            let paper = store.session.map {
                ExamUnit(id: "Reading / Section \(store.section) · " + $0.title, skill: "Reading", title: $0.title,
                         directions: "", passages: $0.passages, questions: $0.questions, audio: nil, oral: [])
            }
            store.send(.saveExpression(SavedExpression(expression: entry.expression,
                source: "Reading / Section \(store.section)", sourceText: entry.sourceText, meaning: entry.meaning, paper: paper, sourceID: entry.sourceID, selectionLocation: entry.utf16Range.location, selectionLength: entry.utf16Range.length)))
        } onAsk: { entry in openTutor(entry.sourceText + "\n選択範囲: " + entry.expression) } onSavePaper: {
            if let set = store.session {
                store.send(.savePaper(ExamUnit(id: "Reading / Section \(store.section) · " + set.title,
                    skill: "Reading", title: set.title, directions: "", passages: set.passages, questions: set.questions, audio: nil, oral: [])))
            }
        } onVocabulary: { vocabulary = true }
    }

    private func openTutor(_ selection: String) {
        context = selection
        tutor = true
    }
}

struct TutorScreen: View {
    let store: StoreOf<StudyFeature>
    let context: String
    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        DisclosureGroup("質問の対象") { Text(context).font(.footnote).textSelection(.enabled) }
                            .padding().background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 18))
                        if store.messages.isEmpty { Text("意味や答えの根拠を質問できます。").foregroundStyle(.secondary) }
                        ForEach(store.messages) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(message.isUser ? "あなた" : "AIチューター").font(.caption.bold()).foregroundStyle(StudyColors.accent)
                                SelectableStudyText(text: message.text, sourceID: message.id.uuidString) { entry in
                                    store.send(.saveExpression(SavedExpression(expression: entry.expression,
                                        source: "AIチューター", sourceText: entry.sourceText, meaning: entry.meaning, sourceID: entry.sourceID, selectionLocation: entry.utf16Range.location, selectionLength: entry.utf16Range.length)))
                                }
                            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.isUser ? StudyColors.mockCard : Color.clear, in: RoundedRectangle(cornerRadius: 18))
                        }
                        if store.asking { ProgressView("回答中…") }
                        if let error = store.explanation, store.messages.last?.text != error {
                            Text(error).foregroundStyle(StudyColors.error)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(20)
                }.onChange(of: store.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(alignment: .bottom) {
                    TextField("追加で質問…", text: $draft, axis: .vertical).lineLimit(1...5)
                    Button("送信", systemImage: "arrow.up.circle.fill") {
                        store.send(.ask(context, draft)); draft = ""
                    }.labelStyle(.iconOnly).font(.title)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.asking)
                }.padding().background(.regularMaterial)
            }
            .navigationTitle("AIチューター").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完了") { dismiss() } }
        }
    }
}
