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
                            }.buttonStyle(.plain)
                        }
                    }
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
                }.foregroundStyle(StudyColors.ink)
                    .padding(.horizontal, StudySpacing.screenInset)
                    .padding(.top, 6)
                    .padding(.bottom, StudySpacing.screenInset)
            }
            .toolbar(.hidden, for: .navigationBar)
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

    private func metric(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: StudySpacing.related) {
            Text("—").font(.title.bold())
            Text(title).font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel(title + " 未算出")
    }

    private var history: some View {
        ProgressScreen(store: store)
    }

    private func partPicker(_ skill: String) -> some View {
        List {
            if skill == "Reading" {
                Section("新しい問題を生成") {
                    ForEach(1...3, id: \.self) { section in
                        Button("Section \(section)") {
                            if store.settings.canPractice { store.send(.start(section)); practice = true }
                            else { settings = true }
                        }
                    }
                }
            }
            if skill != "Reading" {
                Section("新しい問題を生成") {
                    ForEach(units.filter { $0.skill == skill }) { part in
                        NavigationLink(part.id) { GeneratedExamScreen(templates: [part], store: store) }
                    }
                }
            }
            Section("収録問題") {
                ForEach(units.filter { $0.skill == skill }) { part in
                    NavigationLink { ExamScreen(units: [part], store: store) } label: {
                        VStack(alignment: .leading) { Text(part.id); Text(part.title).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                if let loadError { Text(loadError) }
            }
        }.navigationTitle(skill)
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
                Text("いまのレベル").font(.system(.largeTitle, design: .rounded, weight: .black))
                VStack(alignment: .leading, spacing: 22) {
                    Text("推定 IELTS Overall").font(.headline).foregroundStyle(StudyColors.reading)
                    HStack { Text("判定中").font(.largeTitle.bold()); Spacer(); Text("CEFR  —").bold() }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white).background(StudyColors.levelCard, in: RoundedRectangle(cornerRadius: 20))
                Text("技能別の学習状況").font(.title2.bold())
                ForEach(["Reading", "Listening", "Writing", "Speaking"], id: \.self) { skill in
                    let records = store.records.filter { $0.skill == skill }
                    let total = records.reduce(0) { $0 + $1.total }
                    let correct = records.reduce(0) { $0 + $1.correct }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(skill).bold(); Spacer()
                            Text(total > 0 ? "\(correct) / \(total)問" : records.isEmpty ? "判定中" : "\(records.count)回練習")
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: total > 0 ? Double(correct) / Double(total) : 0)
                    }
                }
                Text("演習の正答数を表示しています。IELTSバンド・CEFRは、4技能の評価が揃うまで判定中です。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("学習履歴").font(.title2.bold())
                if store.records.isEmpty && store.results.isEmpty {
                    ContentUnavailableView("学習記録はまだありません", systemImage: "chart.bar")
                }
                ForEach(store.records) { result in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.skill + (result.isMock ? " · 模擬テスト" : "")).font(.caption).foregroundStyle(StudyColors.accent)
                        Text(result.title).bold()
                        HStack {
                            Text(result.total > 0 ? "\(result.correct) / \(result.total) 正解" : "練習完了")
                            Spacer(); Text(result.date, style: .date)
                        }.font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                        .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
                }
                ForEach(Array(store.results.enumerated()), id: \.offset) { Text($0.element).font(.footnote) }
            }.padding(StudySpacing.screenInset)
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
                            store.vocabulary.first { $0.expression == entry.expression && $0.source == entry.source }?.meaning ?? ""
                        }, set: { store.send(.updateMeaning(entry.expression, $0)) }), axis: .vertical)
                        if !entry.sourceText.isEmpty { Text(entry.sourceText).font(.subheadline).textSelection(.enabled) }
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
            }.padding(StudySpacing.screenInset)
        }.background(Color(uiColor: .systemGroupedBackground))
    }
}
