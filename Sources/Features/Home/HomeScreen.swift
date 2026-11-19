import ComposableArchitecture
import SwiftUI

struct HomeScreen: View {
    let store: StoreOf<StudyFeature>
    @State private var settings = false
    @State private var practice = false
    @State private var units: [ExamUnit] = []
    @State private var loadError: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private let skills: [(name: String, detail: String, symbol: String, tint: Color)] = [
        ("Reading", "3 sections", "book.fill", StudyColors.reading),
        ("Listening", "4 parts", "headphones", StudyColors.listening),
        ("Writing", "2 tasks", "pencil", StudyColors.writing),
        ("Speaking", "3 parts", "mic.fill", StudyColors.speaking)
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
                            .accessibilityLabel("設定")
                            .accessibilityIdentifier("home.settings")
                        }
                        .foregroundStyle(StudyColors.accent)
                        Text("今日は何を練習する？")
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
            do { units = try ExamUnit.load() } catch { loadError = error.localizedDescription }
        }
        .sheet(isPresented: $settings) { SettingsScreen(store: store.scope(state: \.settings, action: \.settings)) }
        .fullScreenCover(isPresented: $practice, onDismiss: { store.send(.finish) }) { PracticeScreen(store: store) }
        .tint(StudyColors.accent)
    }

    private var skillGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: StudySpacing.gridGap),
                                             count: typeSize.isAccessibilitySize ? 1 : 2), spacing: StudySpacing.gridGap) {
                        ForEach(skills, id: \.name) { skill in
                            NavigationLink {
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
        NavigationLink { history.navigationTitle("学習記録") } label: {
                        VStack(alignment: .leading, spacing: StudySpacing.contentInset) {
                            Text("現在の推定レベル").font(.subheadline.bold())
                            HStack {
                                metric("IELTS Overall")
                                metric("CEFR 目安")
                            }
                        }.padding(StudySpacing.screenInset).foregroundStyle(.white)
                            .background(StudyColors.levelCard, in: RoundedRectangle(cornerRadius: StudySpacing.cardRadius))
                    }.buttonStyle(.plain)
                    NavigationLink {
                        if !units.isEmpty { MockIntroScreen(units: units, store: store) }
                        else { Text(loadError ?? "教材を読み込み中…") }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: StudySpacing.related) {
                                Text("模擬テスト").font(StudyTypography.japaneseTitle(24, relativeTo: .title2))
                                Text("4技能をまとめて腕試し").font(.subheadline)
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
            Text(title == "CEFR 目安" ? StudyBand.cefr(StudyBand.overall(store.records)) : StudyBand.label(StudyBand.overall(store.records)))
                .font(StudyTypography.roundedTitle(30))
            Text(title).font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel(title + " " + (title == "CEFR 目安" ? StudyBand.cefr(StudyBand.overall(store.records)) : StudyBand.label(StudyBand.overall(store.records))))
    }

    private var history: some View {
        ProgressScreen(store: store)
    }

    private func partPicker(_ skill: String) -> some View {
        let parts = units.filter { $0.skill == skill }
        let tint = skills.first { $0.name == skill }?.tint ?? StudyColors.reading
        let descriptions = [
            "Reading": ["日常生活の案内", "仕事・研修の文書", "一般的な話題の長文"],
            "Listening": ["日常の会話", "日常の独話", "教育・研修の会話", "学術的な独話"],
            "Writing": ["手紙 · 150語以上 · 約20分", "エッセイ · 250語以上 · 約40分"],
            "Speaking": ["身近な話題のインタビュー", "トピックカードでスピーチ", "Part 2に関連する議論"]
        ]
        let noun = skill == "Reading" ? "Section" : skill == "Writing" ? "Task" : "Part"
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("GENERAL TRAINING").font(.caption.bold()).foregroundStyle(StudyColors.accent)
                Text(skill).font(StudyTypography.roundedTitle(34))
                Text("練習する\(noun)を選択").font(.headline)
                ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                    VStack(alignment: .leading, spacing: 16) {
                        NavigationLink { ExamScreen(units: [part], store: store) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(noun) \(index + 1)").font(StudyTypography.roundedTitle(24))
                                    Text(descriptions[skill].flatMap { index < $0.count ? $0[index] : nil } ?? part.title).font(.subheadline)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("part.open.\(part.id)")
                        NavigationLink { GeneratedExamScreen(templates: [part], store: store) } label: {
                            Label("新しい問題を生成して練習", systemImage: "sparkles").font(.subheadline)
                        }
                    }.padding(20).background(tint, in: RoundedRectangle(cornerRadius: 20))
                }
                Text("選んだ区分の全文・全設問で練習します。").font(.footnote).foregroundStyle(.secondary)
                if let loadError { Text(loadError).foregroundStyle(StudyColors.error) }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity).foregroundStyle(StudyColors.ink)
        }.navigationTitle("パート選択").navigationBarTitleDisplayMode(.inline)
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
                Text("いまのレベル").font(StudyTypography.japaneseTitle(30))
                VStack(alignment: .leading, spacing: 22) {
                    Text("推定 IELTS Overall").font(.headline).foregroundStyle(StudyColors.reading)
                    HStack { Text(StudyBand.label(StudyBand.overall(store.records))).font(StudyTypography.roundedTitle(30)); Spacer(); Text("CEFR  " + StudyBand.cefr(StudyBand.overall(store.records))).bold() }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white).background(StudyColors.levelCard, in: RoundedRectangle(cornerRadius: 20))
                Text("技能別の推定バンド").font(.title2.bold())
                ForEach(["Reading", "Listening", "Writing", "Speaking"], id: \.self) { skill in
                    let records = store.records.filter { $0.skill == skill }
                    let total = records.reduce(0) { $0 + $1.total }
                    let correct = records.reduce(0) { $0 + $1.correct }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(skill).bold(); Spacer()
                            Text(StudyBand.label(StudyBand.skill(skill, records: store.records)))
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: (StudyBand.skill(skill, records: store.records) ?? 0) / 9)
                        Text(total > 0 ? "\(correct) / \(total)問 正解" : "\(records.count)回練習").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("直近の演習からの学習用推定です。Reading・Listeningは10問以上、Writing・SpeakingはAI講評があると表示します。Speakingの発音・音声の流暢さは含みません。公式スコアではありません。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("学習履歴").font(.title2.bold())
                if store.records.isEmpty && store.results.isEmpty {
                    ContentUnavailableView("学習記録はまだありません", systemImage: "chart.bar")
                }
                ForEach(store.records) { result in
                    NavigationLink { ResultDetailScreen(result: result, store: store) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.skill + (result.isMock ? " · 模擬テスト" : "")).font(.caption).foregroundStyle(StudyColors.accent)
                        Text(result.title).bold()
                        HStack {
                            Text(result.total > 0 ? "\(result.correct) / \(result.total) 正解" : "練習完了")
                            Spacer(); Text(result.date, style: .date)
                        }.font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                        .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
                ForEach(Array(store.results.enumerated()), id: \.offset) { Text($0.element).font(.footnote) }
            }.padding(StudySpacing.screenInset).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }
    }
}

struct VocabularyScreen: View {
    let store: StoreOf<StudyFeature>
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("保存した表現").font(.subheadline.bold()).foregroundStyle(StudyColors.accent)
                if store.vocabulary.isEmpty {
                    ContentUnavailableView("単語帳は空です", systemImage: "book", description: Text("本文や解説を長押しして表現を追加できます。"))
                }
                ForEach(store.vocabulary) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(entry.source).font(.caption.bold()).foregroundStyle(StudyColors.accent)
                        Text(entry.expression).font(.title2.bold()).textSelection(.enabled)
                        TextField("意味・メモを追加", text: Binding(get: {
                            store.vocabulary.first { $0.id == entry.id }?.meaning ?? ""
                        }, set: { store.send(.updateMeaning(entry.id, $0)) }), axis: .vertical)
                        if !entry.sourceText.isEmpty { Text(entry.contextExcerpt).font(.subheadline).textSelection(.enabled) }
                        if let paper = entry.paper {
                            NavigationLink("元の問題を復習") { ExamScreen(units: [paper], store: store) }
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                }
                NavigationLink {
                    List {
                        Text("保存した問題を選ぶと、もう一度練習できます。")
                        if store.papers.isEmpty { ContentUnavailableView("保存した問題はありません", systemImage: "book") }
                        ForEach(store.papers) { paper in
                            NavigationLink { ExamScreen(units: [paper], store: store) } label: {
                                VStack(alignment: .leading) { Text(paper.id).font(.caption); Text(paper.title).bold() }
                            }
                        }
                    }.navigationTitle("保存した問題")
                } label: {
                    HStack { Text("保存した問題を見る").bold(); Spacer(); Image(systemName: "chevron.right") }
                        .padding().background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
                }
            }.padding(StudySpacing.screenInset).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.background(Color(uiColor: .systemGroupedBackground))
    }
}

struct ResultDetailScreen: View {
    let result: StudyResult
    let store: StoreOf<StudyFeature>
    @State private var audio = SpeakingRecorder()
    @State private var evaluating = false
    @State private var error: String?
    private var current: StudyResult { store.records.first { $0.id == result.id } ?? result }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(current.skill).font(.subheadline.bold()).foregroundStyle(StudyColors.accent)
                Text(current.title).font(.title.bold())
                Text(current.date, style: .date).foregroundStyle(.secondary)
                if current.total > 0 { Text("\(current.correct) / \(current.total) 正解").font(.title2.bold()) }
                if let response = current.response, !response.isEmpty {
                    Text("あなたの回答").font(.headline)
                    Text(response).textSelection(.enabled)
                }
                if let file = current.recordingFile { Button("録音を聞く", systemImage: "play.circle") { audio.playArchived(file) } }
                if let paper = current.paper {
                    if let assessment = current.assessment { AssessmentContent(assessment: assessment, paper: paper, store: store) }
                    if ["Writing", "Speaking"].contains(current.skill), let response = current.response, !response.isEmpty {
                        Button("AIの講評を確認・更新") { evaluating = true }.disabled(evaluating)
                        if evaluating { ProgressView("講評中…") }
                    }
                    NavigationLink("この問題をもう一度練習") { ExamScreen(units: [paper], store: store) }
                    Button("この問題を保存") { store.send(.savePaper(paper)) }
                }
                if let error = error ?? audio.error { Text(error).foregroundStyle(StudyColors.error) }
            }.padding(20).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }
        .navigationTitle("学習の振り返り").navigationBarTitleDisplayMode(.inline)
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
