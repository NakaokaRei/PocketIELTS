import ComposableArchitecture
import SwiftUI

struct PracticeScreen: View {
    let store: StoreOf<StudyFeature>
    @State private var tutor = false
    @State private var context = ""
    @State private var selectedText: String?
    @State private var saved = false

    private var currentPaper: ExamUnit? {
        guard let set = store.session, !store.loading else { return nil }
        let paper = ExamUnit(id: "Reading / Section \(store.section) · " + set.title,
            skill: "Reading", title: set.title, directions: "", passages: set.passages,
            questions: set.questions, audio: nil, oral: [], visuals: set.visuals)
        return paper
    }

    var body: some View {
        IELTSPracticeSession(title: "Reading / Section \(store.section)", finish: { store.send(.finish) },
            save: currentPaper.map { paper in { store.send(.savePaper(paper)); saved = true } }) {
            ScrollView {
                VStack(alignment: .leading, spacing: StudySpacing.section) {
                    if store.loading { ProgressView(String(localized: "本文と設問を生成中…")) }
                    if let error = store.error {
                        Text(error)
                        Button(String(localized: "もう一度生成")) { store.send(.start(store.section)) }
                    }
                    if let set = store.session, !store.loading {
                        Text(set.title).font(StudyTypography.title)
                        ForEach(set.passages.indices, id: \.self) { i in selectable(set.passages[i], id: "passage-\(i)") }
                        ForEach(Array((set.visuals ?? []).enumerated()), id: \.offset) { _, visual in QuestionVisualView(visual: visual) }
                        Divider()
                        ForEach(set.questions.indices, id: \.self) { i in
                            let item = set.questions[i]
                            VStack(alignment: .leading, spacing: StudySpacing.related) {
                                Text("Question \([1,14,27][store.section-1] + i)").font(StudyTypography.headline)
                                if i == 0 || item.instruction != set.questions[i-1].instruction {
                                    selectable(StudyQuestionLayout(item.instruction).formatted, id: "instructions-\(i)")
                                }
                                selectable(item.displayPrompt(number: [1,14,27][store.section-1] + i, localNumber: i + 1), id: "question-\(i)")
                                ForEach(item.choices, id: \.self) { choice in
                                    selectable(item.choiceText(choice), id: "choice-\(i)-\(choice)")
                                }
                                TextField(String(localized: "解答"), text: Binding(get: { store.answers[i] ?? "" }, set: { store.send(.answer(i, $0)) }))
                                    .textFieldStyle(.roundedBorder).disabled(store.reviewed)
                                if store.reviewed {
                                    Label(item.answers.joined(separator: " / "), systemImage: item.accepts(store.answers[i] ?? "") ? "checkmark.circle" : "xmark.circle")
                                    selectable(item.explanation, id: "explanation-\(i)")
                                    if let currentPaper { QuestionReviewActions(part: currentPaper, index: i, answer: store.answers[i] ?? "", store: store) }
                                }
                            }
                        }
                        Button(store.reviewed ? String(localized: "次のセットを生成") : String(localized: "採点して解説を見る")) {
                            if store.reviewed { store.send(.start(store.section)) } else { store.send(.review) }
                        }.buttonStyle(.borderedProminent)
                        Button(String(localized: "この問題を保存"), systemImage: "bookmark") {
                            store.send(.savePaper(ExamUnit(id: "Reading / Section \(store.section) · " + set.title,
                                skill: "Reading", title: set.title, directions: "", passages: set.passages,
                                questions: set.questions, audio: nil, oral: [], visuals: set.visuals)))
                            saved = true
                        }
                        .buttonStyle(StudySecondaryButtonStyle())
                        Button(String(localized: "この問題をAIに質問"), systemImage: "bubble.left.and.bubble.right") { openTutor(QuestionVisual.context(set.visuals) + set.passages.joined(separator: "\n") + "\n" + set.questions.map(\.prompt).joined(separator: "\n")) }
                            .buttonStyle(StudySecondaryButtonStyle())
                    }
                }.padding(.horizontal, StudySpacing.screenInset)
                    .padding(.vertical, StudySpacing.contentInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert(String(localized: "保存しました"), isPresented: $saved) { Button(String(localized: "学習を続ける")) {} }
        .sheet(isPresented: $tutor, onDismiss: { store.send(.closeQuestion) }) {
            TutorScreen(store: store, context: context, selectedText: selectedText)
        }
    }

    private func selectable(_ text: String, id: String) -> some View {
        SelectableStudyText(text: text, sourceID: id) { entry in
            let paper = store.session.map {
                ExamUnit(id: "Reading / Section \(store.section) · " + $0.title, skill: "Reading", title: $0.title,
                         directions: "", passages: $0.passages, questions: $0.questions, audio: nil, oral: [], visuals: $0.visuals)
            }
            store.send(.saveExpression(SavedExpression(expression: entry.expression,
                source: "Reading / Section \(store.section)", sourceText: entry.sourceText, meaning: entry.meaning, paper: paper, sourceID: entry.sourceID, selectionLocation: entry.utf16Range.location, selectionLength: entry.utf16Range.length)))
        } onAsk: { entry in openTutor(entry.sourceText + String(localized: "\n選択範囲: ") + entry.expression, selection: entry.expression) } onSavePaper: {
            if let set = store.session {
                store.send(.savePaper(ExamUnit(id: "Reading / Section \(store.section) · " + set.title,
                    skill: "Reading", title: set.title, directions: "", passages: set.passages, questions: set.questions, audio: nil, oral: [], visuals: set.visuals)))
            }
        }
    }

    private func openTutor(_ context: String, selection: String? = nil) {
        self.context = context
        selectedText = selection
        tutor = true
    }
}

struct TutorScreen: View {
    let store: StoreOf<StudyFeature>
    let context: String
    var selectedText: String? = nil
    var vocabularyMode = false
    @State private var draft = ""
    @State private var settings = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        TutorSubjectCard(text: selectedText ?? context)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(localized: "よくある質問")).font(StudyTypography.headline)
                            Text(String(localized: "選ぶと入力欄に入ります。編集して送信できます。"))
                                .font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                                ForEach(Array((vocabularyMode ? TutorQuickQuestion.vocabulary : TutorQuickQuestion.all).enumerated()), id: \.offset) { index, item in
                                    Button { draft = item.prompt } label: {
                                        Text(item.title).font(StudyTypography.subheadline).multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 12)
                                            .background(StudyColors.reading.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain).foregroundStyle(StudyColors.accent)
                                        .disabled(store.asking).accessibilityIdentifier("tutor.quick.\(index)")
                                }
                            }
                        }
                        if !store.settings.canPractice { Button(String(localized: "ChatGPTの接続設定")) { settings = true } }
                        ForEach(store.messages) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(message.isUser ? String(localized: "あなた") : String(localized: "AIチューター")).font(StudyTypography.caption.bold()).foregroundStyle(StudyColors.accent)
                                SelectableStudyText(text: message.text, sourceID: message.id.uuidString, onSave: { entry in
                                    store.send(.saveExpression(SavedExpression(expression: entry.expression,
                                        source: String(localized: "AIチューター"), sourceText: entry.sourceText, meaning: entry.meaning, sourceID: entry.sourceID, selectionLocation: entry.utf16Range.location, selectionLength: entry.utf16Range.length)))
                                }, markdown: !message.isUser)
                            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.isUser ? StudyColors.mockCard : Color.clear, in: RoundedRectangle(cornerRadius: 18))
                        }
                        if store.asking { ProgressView(String(localized: "回答中…")) }
                        if let error = store.explanation, store.messages.last?.text != error {
                            Text(error).foregroundStyle(StudyColors.error)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(20)
                }.onChange(of: store.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(alignment: .bottom) {
                    TextField(String(localized: "追加で質問…"), text: $draft, axis: .vertical).lineLimit(1...5)
                        .accessibilityIdentifier("tutor.input")
                    Button(String(localized: "送信"), systemImage: "arrow.up.circle.fill") {
                        store.send(.ask(context, draft)); draft = ""
                    }.labelStyle(.iconOnly).font(.title)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.asking)
                }.padding().background(.regularMaterial)
            }
            .navigationTitle(String(localized: "AIチューター")).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(String(localized: "完了")) { dismiss() } }
            .sheet(isPresented: $settings) { SettingsScreen(store: store.scope(state: \.settings, action: \.settings)) }
        }
    }
}

enum TutorQuickQuestion {
    static var vocabulary: [(title: String, prompt: String)] {
        [all[0], (String(localized: "使い方を教えて"), String(localized: "この表現の使い方と、よく一緒に使う語を例文付きで教えてください。")), all[2], all[1]]
    }
    static let all: [(title: String, prompt: String)] = [
        (String(localized: "この意味は？"), String(localized: "選択した表現や文の、この文脈での意味をやさしい日本語で教えてください。")),
        (String(localized: "文法・文の構造"), String(localized: "選択した英文の文法と文の構造を、主語・動詞などに分けて説明してください。")),
        (String(localized: "言い換えと例文"), String(localized: "選択した表現の自然な言い換えと、英語の例文を2つ、日本語訳付きで教えてください。")),
        (String(localized: "正解の根拠"), String(localized: "この問題の正解の根拠を、本文の該当箇所を示して説明してください。")),
        (String(localized: "他の選択肢との違い"), String(localized: "この問題で他の選択肢が合わない理由と、見分けるポイントを教えてください。")),
        (String(localized: "ヒントだけほしい"), String(localized: "正解はまだ言わず、この問題を自分で解くためのヒントを一つください。"))
    ]
}


/// The visible subject is the exact selection; full exercise context is still sent to AI.
struct TutorSubjectCard: View {
    let text: String
    @State private var expanded = false
    private var isLong: Bool { text.count > 160 || text.components(separatedBy: .newlines).count > 4 }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "質問の対象"), systemImage: "text.quote")
                .font(StudyTypography.caption.bold()).foregroundStyle(StudyColors.accent)
            Text(text).font(StudyTypography.body).textSelection(.enabled)
                .lineLimit(isLong && !expanded ? 4 : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("tutor.subject")
            if isLong {
                Button(expanded ? String(localized: "折りたたむ") : String(localized: "全文を見る"), systemImage: expanded ? "chevron.up" : "chevron.down") {
                    expanded.toggle()
                }.font(StudyTypography.subheadline.bold()).foregroundStyle(StudyColors.accent)
                    .accessibilityIdentifier("tutor.subject.expand")
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 18))
            .onChange(of: text) { _, _ in expanded = false }
    }
}
