import ComposableArchitecture
import SwiftUI

struct HomeScreen: View {
    let store: StoreOf<StudyFeature>
    @State private var settings = false
    @State private var practice = false
    private let units: [ExamUnit]
    private let loadError: String?

    init(store: StoreOf<StudyFeature>) {
        self.store = store
        // Bundled content must exist before value-based navigation captures a destination.
        // Loading in onAppear can permanently capture an empty section list.
        do {
            units = try ExamUnit.load()
            loadError = nil
        } catch {
            units = []
            loadError = error.localizedDescription
        }
    }
    @Environment(\.dynamicTypeSize) private var typeSize

    private let skills: [(name: String, detail: String, symbol: String, tint: Color)] = [
        ("Reading", String(localized: "3 sections"), "book.fill", StudyColors.reading),
        ("Listening", String(localized: "4 parts"), "headphones", StudyColors.listening),
        ("Writing", String(localized: "2 tasks"), "pencil", StudyColors.writing),
        ("Speaking", String(localized: "3 parts"), "mic.fill", StudyColors.speaking)
    ]

    var body: some View {
        IELTSNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: StudySpacing.section) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Pocket IELTS")
                                .font(.system(size: 14, weight: .bold))
                            Spacer()
                            Button { settings = true } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 22, weight: .regular))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "設定"))
                            .accessibilityIdentifier("home.settings")
                        }
                        .foregroundStyle(StudyColors.accent)
                        Text(String(localized: "今日は何を練習する？"))
                            .font(StudyTypography.japaneseTitle(30))
                            .accessibilityAddTraits(.isHeader)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 24) {
                            skillGrid.frame(minWidth: 400)
                            summaryCards.frame(width: 280)
                        }
                        VStack(spacing: 24) { skillGrid; summaryCards }
                    }

                }.foregroundStyle(StudyColors.ink)
                    .padding(.horizontal, StudySpacing.screenInset)
                    .padding(.top, 6)
                    .padding(.bottom, StudySpacing.screenInset)
                    .frame(maxWidth: 1100)
                    .frame(maxWidth: .infinity)
            }
            .toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .visible : .hidden, for: .navigationBar)
        } progress: { history } vocabulary: {
            VocabularyScreen(store: store)
        }
        .onAppear {
            store.send(.settings(.opened))
            store.send(.settings(.refreshAccount))
        }
        .sheet(isPresented: $settings) { SettingsScreen(store: store.scope(state: \.settings, action: \.settings)) }
        .fullScreenCover(isPresented: $practice, onDismiss: { store.send(.finish) }) { PracticeScreen(store: store) }
        .tint(StudyColors.accent)
    }

    private var skillGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: StudySpacing.gridGap),
                                             count: typeSize.isAccessibilitySize ? 1 : 2), spacing: StudySpacing.gridGap) {
                        ForEach(skills, id: \.name) { skill in
                            StudyLink {
                                partPicker(skill.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Image(systemName: skill.symbol).font(.title2).accessibilityHidden(true)
                                    Spacer(minLength: StudySpacing.related)
                                    Text(skill.name).font(StudyTypography.roundedTitle(24))
                                    HStack(spacing: 6) {
                                        Text(skill.detail)
                                        Image(systemName: "chevron.right").font(.caption2)
                                    }.font(.system(size: 14))
                                }
                                .padding(StudySpacing.contentInset).frame(maxWidth: .infinity, minHeight: StudySpacing.cardHeight, alignment: .leading)
                                .background(skill.tint, in: RoundedRectangle(cornerRadius: StudySpacing.cardRadius))
                            }.buttonStyle(.plain).accessibilityIdentifier("home.skill.\(skill.name)")
                        }
                    }
    }
    private var summaryCards: some View {
        VStack(spacing: 24) {
        StudyLink { OfflineLibraryScreen(units: units, store: store) } label: {
            Label(String(localized: "Offline practice"), systemImage: "books.vertical.fill")
                .font(StudyTypography.button).frame(maxWidth: .infinity, alignment: .leading)
                .padding(20).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityIdentifier("home.offline")
        StudyLink { SavedPapersScreen(store: store) } label: {
            HStack(spacing: 12) {
                Image(systemName: "bookmark.fill").font(.title2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "保存した問題から練習")).font(StudyTypography.headline)
                    Text(String(format: String(localized: "%@件の問題"), String(store.papers.count))).font(StudyTypography.subheadline)
                }
                Spacer(); Image(systemName: "chevron.right")
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityIdentifier("home.savedPapers")
        StudyLink { history.navigationTitle(String(localized: "学習記録")) } label: {
                        VStack(alignment: .leading, spacing: StudySpacing.contentInset) {
                            Text(String(localized: "現在の推定レベル")).font(StudyTypography.subheadline.bold())
                            HStack {
                                metric("IELTS Overall")
                                metric(String(localized: "CEFR 目安"))
                            }
                        }.padding(StudySpacing.screenInset).foregroundStyle(.white)
                            .background(StudyColors.levelCard, in: RoundedRectangle(cornerRadius: StudySpacing.cardRadius))
                    }.buttonStyle(.plain)
                    StudyLink {
                        if !units.isEmpty { MockIntroScreen(units: units, store: store) }
                        else { Text(loadError ?? String(localized: "教材を読み込み中…")) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: StudySpacing.related) {
                                Text(String(localized: "模擬テスト")).font(StudyTypography.japaneseTitle(24, relativeTo: .title2))
                                Text(String(localized: "4技能をまとめて腕試し")).font(StudyTypography.subheadline)
                            }
                            Spacer()
                            Image(systemName: "arrow.right").font(.title3.bold())
                        }.padding(StudySpacing.screenInset).frame(minHeight: 106)
                            .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: StudySpacing.cardRadius))
                    }.buttonStyle(.plain)
        }
    }

    private func metric(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: StudySpacing.related) {
            Text(title == String(localized: "CEFR 目安") ? StudyBand.cefr(StudyBand.overall(store.records)) : StudyBand.label(StudyBand.overall(store.records)))
                .font(StudyTypography.roundedTitle(30))
            Text(title).font(StudyTypography.caption)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel(title + " " + (title == String(localized: "CEFR 目安") ? StudyBand.cefr(StudyBand.overall(store.records)) : StudyBand.label(StudyBand.overall(store.records))))
    }

    private var history: some View {
        ProgressScreen(store: store)
    }

    private func partPicker(_ skill: String) -> some View {
        let parts = units.filter { $0.skill == skill }
        let tint = skills.first { $0.name == skill }?.tint ?? StudyColors.reading
        let descriptions = [
            "Reading": [String(localized: "日常生活の案内"), String(localized: "仕事・研修の文書"), String(localized: "一般的な話題の長文")],
            "Listening": [String(localized: "日常の会話"), String(localized: "日常の独話"), String(localized: "教育・研修の会話"), String(localized: "学術的な独話")],
            "Writing": [String(localized: "手紙 · 150語以上 · 約20分"), String(localized: "エッセイ · 250語以上 · 約40分")],
            "Speaking": [String(localized: "身近な話題のインタビュー"), String(localized: "トピックカードでスピーチ"), String(localized: "Part 2に関連する議論")]
        ]
        let noun = skill == "Reading" ? "Section" : skill == "Writing" ? "Task" : "Part"
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("GENERAL TRAINING").font(StudyTypography.caption.bold()).foregroundStyle(StudyColors.accent)
                Text(skill).font(StudyTypography.roundedTitle(34))
                StudyLink { SavedPapersScreen(store: store, skill: skill) } label: {
                    Label(String(localized: "保存した問題から練習"), systemImage: "bookmark.fill")
                }.buttonStyle(StudySecondaryButtonStyle()).accessibilityIdentifier("part.savedPapers")
                Text(String(format: String(localized: "練習する%@を選択"), String(noun))).font(StudyTypography.headline)
                if let loadError { Text(loadError).foregroundStyle(StudyColors.error) }
                ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                    VStack(alignment: .leading, spacing: 16) {
                        StudyLink { ExamScreen(units: [part], store: store) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(noun) \(index + 1)").font(StudyTypography.roundedTitle(24))
                                    Label(String(localized: "収録問題で練習"), systemImage: "book.closed").font(StudyTypography.caption.bold())
                                    Text(descriptions[skill].flatMap { index < $0.count ? $0[index] : nil } ?? part.title).font(StudyTypography.subheadline)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("part.open.\(part.id)")
                        Divider()
                        StudyLink { GeneratedExamScreen(templates: [part], store: store) } label: {
                            Label(String(localized: "新しい問題を生成して練習"), systemImage: "sparkles").font(StudyTypography.subheadline)
                        }
                    }.padding(20).background(tint, in: RoundedRectangle(cornerRadius: 20))
                }
                Text(String(localized: "選んだ区分の全文・全設問で練習します。")).font(StudyTypography.footnote).foregroundStyle(StudyColors.secondaryText)
                if let loadError { Text(loadError).foregroundStyle(StudyColors.error) }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity).foregroundStyle(StudyColors.ink)
        }.navigationTitle(String(localized: "パート選択")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
    }
}

#Preview("ホーム · Light") {
    HomeScreen(store: Store(initialState: StudyFeature.State()) { StudyFeature() }).preferredColorScheme(.light)
}

#Preview("ホーム · Dark") {
    HomeScreen(store: Store(initialState: StudyFeature.State()) { StudyFeature() }).preferredColorScheme(.dark)
}

struct ProgressScreen: View {
    let store: StoreOf<StudyFeature>
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(String(localized: "いまのレベル")).font(StudyTypography.japaneseTitle(30))
                VStack(alignment: .leading, spacing: 22) {
                    Text(String(localized: "推定 IELTS Overall")).font(StudyTypography.headline).foregroundStyle(StudyColors.reading)
                    HStack { Text(StudyBand.label(StudyBand.overall(store.records))).font(StudyTypography.roundedTitle(30)); Spacer(); Text("CEFR  " + StudyBand.cefr(StudyBand.overall(store.records))).bold() }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white).background(StudyColors.levelCard, in: RoundedRectangle(cornerRadius: 20))
                Text(String(localized: "技能別の推定バンド")).font(StudyTypography.heading)
                ForEach(["Reading", "Listening", "Writing", "Speaking"], id: \.self) { skill in
                    let records = store.records.filter { $0.skill == skill }
                    let total = records.reduce(0) { $0 + $1.total }
                    let correct = records.reduce(0) { $0 + $1.correct }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(skill).bold(); Spacer()
                            Text(StudyBand.label(StudyBand.skill(skill, records: store.records)))
                                .foregroundStyle(StudyColors.secondaryText)
                        }
                        ProgressView(value: (StudyBand.skill(skill, records: store.records) ?? 0) / 9)
                        Text(total > 0 ? String(format: String(localized: "%@ / %@問 正解"), String(correct), String(total)) : String(format: String(localized: "%@回練習"), String(records.count))).font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                    }
                }
                Text(String(localized: "直近の演習からの学習用推定です。Reading・Listeningは10問以上、Writing・SpeakingはAI講評があると表示します。Speakingの発音・音声の流暢さは含みません。公式スコアではありません。"))
                    .font(StudyTypography.footnote).foregroundStyle(StudyColors.secondaryText)
                Text(String(localized: "学習履歴")).font(StudyTypography.heading)
                if store.records.isEmpty && store.results.isEmpty {
                    ContentUnavailableView(String(localized: "学習記録はまだありません"), systemImage: "chart.bar")
                }
                ForEach(store.records) { result in
                    StudyLink { ResultDetailScreen(result: result, store: store) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.skill + (result.isMock ? String(localized: " · 模擬テスト") : "")).font(StudyTypography.caption).foregroundStyle(StudyColors.accent)
                        Text(result.title).bold()
                        HStack {
                            Text(result.total > 0 ? String(format: String(localized: "%@ / %@ 正解"), String(result.correct), String(result.total)) : String(localized: "練習完了"))
                            Spacer(); Text(result.date, style: .date)
                        }.font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                        .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
                ForEach(Array(store.results.enumerated()), id: \.offset) { Text($0.element).font(StudyTypography.footnote) }
            }.padding(StudySpacing.screenInset).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }
    }
}

struct VocabularyScreen: View {
    let store: StoreOf<StudyFeature>
    @State private var adding = false
    @State private var deleting: SavedExpression?
    @State private var tutor = false
    @StateObject private var pronunciation = WordPronouncer()
    @State private var context = ""
    @State private var selectedText: String?
    var body: some View {
        List {
            Section {
                StudyLink { VocabularyLibraryScreen(store: store) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "IELTS word library"), systemImage: "books.vertical.fill").font(StudyTypography.heading)
                        Text(String(format: String(localized: "%@ words · 3 levels · Offline"), String(StarterWord.all.count))).font(StudyTypography.subheadline)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(StudyColors.reading, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityIdentifier("vocabulary.library")
                Text(String(localized: "My vocabulary")).font(StudyTypography.subheadline.bold()).foregroundStyle(StudyColors.accent)
                if store.vocabulary.isEmpty {
                    ContentUnavailableView(String(localized: "単語帳は空です"), systemImage: "book", description: Text(String(localized: "本文や解説を長押しして表現を追加できます。")))
                }
                ForEach(store.vocabulary) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(entry.sourceID == "manual" ? String(localized: "My vocabulary") : entry.source).font(StudyTypography.caption.bold()).foregroundStyle(StudyColors.accent)
                        HStack(alignment: .top) {
                            Text(entry.expression).font(StudyTypography.heading).textSelection(.enabled)
                            WordPronunciationButton(word: entry.expression, pronunciation: pronunciation)
                            Spacer(minLength: 0)
                        }
                        if !entry.sourceText.isEmpty { Text(entry.contextExcerpt).font(StudyTypography.subheadline).textSelection(.enabled) }
                        Button(String(localized: "AIに質問"), systemImage: "bubble.left.and.bubble.right") {
                            pronunciation.stop()
                            context = entry.expression + "\n\n" + entry.sourceText + "\n\n" + entry.meaning
                            selectedText = entry.expression
                            tutor = true
                        }.buttonStyle(StudySecondaryButtonStyle()).accessibilityIdentifier("vocabulary.askAI")
                        if let paper = entry.paper {
                            StudyLink { ExamScreen(units: [paper], store: store) } label: { Label(String(localized: "元の問題を復習"), systemImage: "book") }.buttonStyle(StudySecondaryButtonStyle())
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleting = entry } label: { Label(String(localized: "削除"), systemImage: "trash") }.tint(.red)
                        }
                }

            }.listRowSeparator(.hidden).listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        }.listStyle(.plain).scrollContentBackground(.hidden)
            .frame(maxWidth: 800).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button(String(localized: "Add vocabulary"), systemImage: "plus") { adding = true }
                .accessibilityIdentifier("vocabulary.add")
        } }
        .sheet(isPresented: $adding) { AddVocabularyScreen(store: store) }
        .alert(String(localized: "この単語を削除しますか？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { entry in
            Button(String(localized: "削除"), role: .destructive) { store.send(.deleteExpression(entry.id)); deleting = nil }
            Button(String(localized: "キャンセル"), role: .cancel) { deleting = nil }
        } message: { entry in Text(entry.expression) }
        .onDisappear { pronunciation.stop() }
        .sheet(isPresented: $tutor, onDismiss: { store.send(.closeQuestion) }) {
            TutorScreen(store: store, context: context, selectedText: selectedText, vocabularyMode: true)
        }
    }
}

struct ResultDetailScreen: View {
    let result: StudyResult
    let store: StoreOf<StudyFeature>
    @State private var audio = SpeakingRecorder()
    @State private var evaluating = false
    @State private var error: String?
    @State private var saved = false
    private var current: StudyResult { store.records.first { $0.id == result.id } ?? result }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(current.skill, systemImage: current.skill == "Listening" ? "headphones" : current.skill == "Speaking" ? "mic" : current.skill == "Writing" ? "pencil" : "book")
                            .font(StudyTypography.subheadline.bold()).foregroundStyle(StudyColors.accent)
                        Spacer()
                        Text(current.date, style: .date).font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                    }
                    Text(current.title).font(StudyTypography.japaneseTitle(24))
                    if current.total > 0 {
                        Text(String(format: String(localized: "%@ / %@ 正解"), String(current.correct), String(current.total)))
                            .font(StudyTypography.heading).foregroundStyle(StudyColors.accent)
                        ProgressView(value: Double(current.correct), total: Double(current.total))
                            .tint(StudyColors.accent)
                    }
                }.padding(24).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 24))
                if let answers = current.questionAnswers, let paper = current.paper {
                    DisclosureGroup(String(localized: "あなたの回答")) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(paper.questions.indices, id: \.self) { index in
                                let question = paper.questions[index]
                                let answer = index < answers.count ? answers[index] : ""
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Question \(paper.firstQuestionNumber + index)", systemImage: question.accepts(answer) ? "checkmark.circle.fill" : "xmark.circle")
                                        .font(StudyTypography.headline).foregroundStyle(StudyColors.accent)
                                    Text(question.displayPrompt(number: paper.firstQuestionNumber + index, localNumber: index + 1))
                                    Text(String(localized: "あなたの解答: ") + (answer.isEmpty ? String(localized: "未回答") : answer))
                                        .font(StudyTypography.subheadline).bold()
                                    Text(String(localized: "正解: ") + question.answers.joined(separator: " / ")).font(StudyTypography.subheadline)
                                    Text(question.explanation).font(StudyTypography.subheadline).foregroundStyle(StudyColors.secondaryText)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }.padding(.top, 12)
                    }.accessibilityIdentifier("history.answers")
                }
                if let response = current.response, !response.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "あなたの回答")).font(StudyTypography.headline)
                        Text(response).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
                }
                if let file = current.recordingFile {
                    Button(String(localized: "録音を聞く"), systemImage: "play.circle") { audio.playArchived(file) }
                        .buttonStyle(StudySecondaryButtonStyle())
                }
                if let paper = current.paper {
                    if let assessment = current.assessment { AssessmentContent(assessment: assessment, paper: paper, store: store) }
                    if ["Writing", "Speaking"].contains(current.skill), let response = current.response, !response.isEmpty {
                        Button(String(localized: "AIの講評を確認・更新"), systemImage: "sparkles") { evaluating = true }.buttonStyle(StudySecondaryButtonStyle()).disabled(evaluating)
                        if evaluating { ProgressView(String(localized: "講評中…")) }
                    }
                    StudyLink { ExamScreen(units: [paper], store: store) } label: {
                        Label(String(localized: "この問題をもう一度練習"), systemImage: "arrow.counterclockwise")
                    }.buttonStyle(StudyPrimaryButtonStyle())
                    Button(String(localized: "この問題を保存"), systemImage: "bookmark") { store.send(.savePaper(paper)); saved = true }
                        .buttonStyle(StudySecondaryButtonStyle())
                }
                if let error = error ?? audio.error { Text(error).foregroundStyle(StudyColors.error) }
            }.padding(20).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }
        .alert(String(localized: "保存しました"), isPresented: $saved) { Button(String(localized: "学習を続ける"), role: .cancel) {} }
        .navigationTitle(String(localized: "学習の振り返り")).navigationBarTitleDisplayMode(.inline)
        .onDisappear { audio.stop() }
        .task(id: evaluating) {
            guard evaluating, let paper = current.paper, let response = current.response else { return }
            do {
                let assessment = try await StudyClient.assess(paper, response: response)
                try Task.checkCancellation()
                store.send(.updateAssessment(current.id, assessment))
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            evaluating = false
        }
    }
}

enum SavedPaperGrouping {
    static let skills = ["Reading", "Listening", "Writing", "Speaking"]
    static func part(_ paper: ExamUnit) -> String {
        let prefix = paper.id.components(separatedBy: " · ")[0]
        let noun = paper.skill == "Reading" ? "Section" : paper.skill == "Writing" ? "Task" : "Part"
        let count = paper.skill == "Reading" || paper.skill == "Speaking" ? 3 : paper.skill == "Writing" ? 2 : 4
        for index in 1...count where prefix.hasSuffix("\(noun) \(index)") { return "\(noun) \(index)" }
        return String(localized: "その他")
    }
}

struct SavedPapersScreen: View {
    let store: StoreOf<StudyFeature>
    @State private var selectedSkill: String
    @State private var deleting: ExamUnit?
    init(store: StoreOf<StudyFeature>, skill: String? = nil) {
        self.store = store
        _selectedSkill = State(initialValue: skill ?? SavedPaperGrouping.skills.first(where: { candidate in store.papers.contains { $0.skill == candidate } }) ?? "Reading")
    }
    private var papers: [ExamUnit] { store.papers.filter { $0.skill == selectedSkill } }
    private var groups: [String] { Array(Set(papers.map(SavedPaperGrouping.part))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var body: some View {
        List {
            Section {
                Text(String(localized: "技能とパートを選んで、保存した問題を復習できます。"))
                    .font(StudyTypography.subheadline).foregroundStyle(StudyColors.secondaryText)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(SavedPaperGrouping.skills.enumerated()), id: \.element) { index, skill in
                        Button { selectedSkill = skill } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Image(systemName: ["book", "headphones", "pencil", "mic"][index]); Spacer(); if selectedSkill == skill { Image(systemName: "checkmark.circle.fill") } }
                                Text(skill).font(StudyTypography.roundedTitle(20))
                                Text(String(format: String(localized: "%@件の問題"), String(store.papers.filter { $0.skill == skill }.count))).font(StudyTypography.caption)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background([StudyColors.reading, StudyColors.listening, StudyColors.writing, StudyColors.speaking][index], in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selectedSkill == skill ? StudyColors.accent : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).foregroundStyle(StudyColors.ink)
                            .accessibilityAddTraits(selectedSkill == skill ? .isSelected : [])
                            .accessibilityIdentifier("saved.skill.\(skill)")
                    }
                }
                if papers.isEmpty {
                    ContentUnavailableView(String(localized: "保存した問題はありません"), systemImage: "bookmark", description: Text(String(localized: "解説画面の「この問題を保存」から追加できます。")))
                }
                ForEach(groups, id: \.self) { group in
                    Section {
                        HStack {
                            Text(group).font(StudyTypography.heading)
                            Spacer()
                            Text(String(format: String(localized: "%@件の問題"), String(papers.filter { SavedPaperGrouping.part($0) == group }.count))).font(StudyTypography.caption)
                        }.accessibilityAddTraits(.isHeader)
                        ForEach(papers.filter { SavedPaperGrouping.part($0) == group }) { paper in
                            HStack(alignment: .top, spacing: 12) {
                                StudyLink { ExamScreen(units: [paper], store: store) } label: {
                                    HStack(spacing: 16) {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text(paper.title).font(StudyTypography.heading).foregroundStyle(StudyColors.ink)
                                            Label(String(localized: "もう一度練習する"), systemImage: "play.fill").font(StudyTypography.button)
                                        }
                                        Spacer(minLength: 0)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { deleting = paper } label: { Label(String(localized: "削除"), systemImage: "trash") }.tint(.red)
                                }
                        }
                    }
                }
            }.listRowSeparator(.hidden).listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
        }.listStyle(.plain).scrollContentBackground(.hidden)
            .frame(maxWidth: 800).frame(maxWidth: .infinity)
            .navigationTitle(String(localized: "保存した問題")).navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "保存した問題を削除しますか？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { paper in
            Button(String(localized: "削除"), role: .destructive) { store.send(.deletePaper(paper.id)); deleting = nil }
            Button(String(localized: "キャンセル"), role: .cancel) { deleting = nil }
        } message: { paper in
            Text(paper.title + "\n\n" + String(localized: "学習履歴と保存した単語は残ります。"))
        }
    }
}
