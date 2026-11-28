import AVFoundation
import Speech
import SwiftUI
import ComposableArchitecture

struct ExamUnit: Codable, Equatable, Identifiable, Sendable {
    let id, skill, title, directions: String
    let passages: [String]
    let questions: [ReadingSet.Question]
    let audio: String?
    let oral: [String]
    var visuals: [QuestionVisual]? = nil
    var audioPreparationFailed: Bool? = nil
    var estimatedTime: String? {
        let minutes: String
        switch id.components(separatedBy: " · ")[0] {
        case "Reading / Section 1": minutes = "15"
        case "Reading / Section 2", "Writing / Task 1": minutes = "20"
        case "Reading / Section 3": minutes = "25"
        case "Listening / Part 1", "Listening / Part 2": minutes = "7"
        case "Listening / Part 3", "Listening / Part 4": minutes = "8"
        case "Writing / Task 2": minutes = "40"
        case "Speaking / Part 1", "Speaking / Part 3": minutes = "4–5"
        case "Speaking / Part 2": minutes = "3–4"
        default: return nil
        }
        return String(format: String(localized: "About %@ min"), minutes)
    }

    var firstQuestionNumber: Int {
        if skill == "Reading" { return id.contains("Section 3") ? 27 : id.contains("Section 2") ? 14 : 1 }
        if skill == "Listening", let part = (1...4).first(where: { id.contains("Part \($0)") }) { return (part - 1) * 10 + 1 }
        return 1
    }
    static func load() throws -> [ExamUnit] {
        guard let url = Bundle.main.url(forResource: "GeneralTraining", withExtension: "json") else {
            throw StudyError.message(String(localized: "教材が見つかりません。"))
        }
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
    }
}

struct MockIntroScreen: View {
    let units: [ExamUnit]
    let store: StoreOf<StudyFeature>
    @State private var started = false
    @State private var exitToProgress: Bool?
    @Environment(\.studyNavigation) private var navigation
    @State private var generate = false
    private var ordered: [ExamUnit] {
        ["Listening", "Reading", "Writing", "Speaking"].flatMap { skill in units.filter { $0.skill == skill } }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(String(localized: "模擬テスト")).font(StudyTypography.japaneseTitle(30))
                VStack(alignment: .leading, spacing: 20) {
                    Text(String(localized: "Full mock")).font(StudyTypography.title)
                    Text(String(localized: "時間を計って4技能に挑戦。\n解説はテスト終了後に確認できます。"))
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudyColors.reading, in: RoundedRectangle(cornerRadius: 20))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(Array(["Listening", "Reading", "Writing", "Speaking"].enumerated()), id: \.offset) { index, skill in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(String(format: "%02d", index + 1)).font(StudyTypography.roundedTitle(18))
                                Spacer()
                                Image(systemName: ["headphones", "book", "pencil", "mic"][index])
                            }.foregroundStyle(StudyColors.ink)
                            Text(skill).font(StudyTypography.roundedTitle(22))
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background([StudyColors.listening, StudyColors.reading, StudyColors.writing, StudyColors.speaking][index], in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Label(String(localized: "新しい問題を生成する"), systemImage: "sparkles")
                            .font(StudyTypography.button).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Toggle(String(localized: "新しい問題を生成する"), isOn: $generate)
                            .labelsHidden().fixedSize().accessibilityIdentifier("mock.generate")
                    }
                    Text(generate ? String(localized: "新しい問題を生成します。") : String(localized: "収録問題を使用します。Writing・Speakingは終了後にAI講評を確認できます。"))
                        .font(StudyTypography.subheadline).foregroundStyle(StudyColors.secondaryText)
                }.padding(20).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
                Button(String(localized: "模試を始める"), systemImage: "play.fill") { started = true }
                    .buttonStyle(StudyPrimaryButtonStyle()).disabled(units.isEmpty)
            }.padding(20).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $started, onDismiss: {
                if let progress = exitToProgress {
                    exitToProgress = nil
                    if progress { navigation.progress() } else { navigation.home() }
                }
            }) {
                NavigationStack {
                    if generate { GeneratedExamScreen(templates: ordered, store: store, isMock: true) }
                    else { ExamScreen(units: ordered, store: store, isMock: true) }
                }.environment(\.studyNavigation, StudyNavigationActions(
                    home: { exitToProgress = false; started = false },
                    progress: { exitToProgress = true; started = false }
                ))
            }
    }
}

struct ExamScreen: View {
    var onFirstReview: () -> Void = {}
    let units: [ExamUnit]
    let store: StoreOf<StudyFeature>
    var isMock = false
    var historyResult: StudyResult?
    @Environment(\.studyNavigation) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum JumpTarget: Hashable { case passage, question(Int) }
    @State private var confirmEnd = false
    @State private var hasReachedReview = false
    @State private var completing = false
    @FocusState private var answerFocused: Bool
    @State private var listeningReviewDeadline: Date?
    @State private var listeningReviewPart = 0
    @State private var position = 0
    @State private var attemptID = UUID()
    @State private var resultIDs: [String: UUID] = [:]
    @State private var assessments: [String: PracticeAssessment] = [:]
    @State private var assessmentErrors: [String: String] = [:]
    @State private var evaluatingID: String?
    @State private var recordingFiles: [String: String] = [:]
    @State private var finished = false
    @State private var answers: [String: String] = [:]
    @State private var reviewPresented = false
    @State private var markedWords: [String: [SelectableStudyText.Entry]] = [:]
    @State private var questionPageID = UUID()
    @State private var recorded: Set<String> = []
    @State private var speaker: AVSpeechSynthesizer?
    @State private var started = Date()
    @State private var ended: Date?
    @State private var partStarted = Date()
    @State private var partEnded: Date?
    private struct TutorRequest: Identifiable {
        let id = UUID()
        let context: String
        let selection: String?
    }
    @State private var transcripts: [String: ListeningTranscript] = [:]
    @State private var tutor: TutorRequest?
    @State private var saved = false
    @State private var recording = false
    @State private var conversation = false
    @State private var settings = false
    @State private var audio = SpeakingRecorder()
    private var unit: ExamUnit { units[position] }
    private var unsavedUnits: [ExamUnit] {
        let candidates = isMock ? units : units.isEmpty ? [] : [unit]
        return candidates.filter { candidate in !store.papers.contains { $0.id == candidate.id } }
    }

    var body: some View {
        if historyResult != nil {
            page(showingReview: true)
        } else {
            page(showingReview: false)
                .navigationDestination(isPresented: $reviewPresented) { page(showingReview: true) }
                .navigationDestination(isPresented: $finished) {
                    ScrollView { results.padding(StudySpacing.screenInset).frame(maxWidth: 800).frame(maxWidth: .infinity) }
                        .navigationBarBackButtonHidden(true).navigationBarTitleDisplayMode(.inline)
                }
        }
    }

    private func page(showingReview: Bool) -> some View {
        let active = historyResult != nil || showingReview == reviewPresented
        return Group {
            if units.isEmpty {
                ContentUnavailableView(String(localized: "教材がありません"), systemImage: "book")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: StudySpacing.section) {
                            if isMock {
                                HStack {
                                    Text(String(localized: "模擬テスト")).bold(); Spacer()
                                    if let ended { Text(duration(ended.timeIntervalSince(started))).monospacedDigit() }
                                    else { Text(started, style: .timer).monospacedDigit() }
                                }.foregroundStyle(StudyColors.accent)
                            }
                            if let deadline = listeningReviewDeadline {
                                listeningAnswerReview(deadline)
                            } else {
                                exercise(showingReview: showingReview)
                            }
                        }.padding(StudySpacing.screenInset).frame(maxWidth: 800).frame(maxWidth: .infinity)
                    }.scrollEdgeEffectStyle(.soft, for: .top)
                        .scrollDismissesKeyboard(.interactively)
                        .id(listeningReviewDeadline != nil ? "listening-check" : showingReview ? unit.id : "\(position)-\(questionPageID)")
                        .safeAreaInset(edge: .bottom) {
                            if listeningReviewDeadline == nil && !showingReview && (!unit.questions.isEmpty || unit.skill == "Writing" || unit.skill == "Speaking") {
                                jumpControls(proxy)
                            }
                        }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!units.isEmpty && (isMock || !showingReview || answerFocused))
        .interactiveDismissDisabled(!finished && (isMock || !showingReview))
        .foregroundStyle(StudyColors.ink)
        .toolbar {
            if (isMock || !showingReview) && !finished && !units.isEmpty && !answerFocused {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "終了"), systemImage: "chevron.backward") {
                        completing = false; confirmEnd = true
                    }.labelStyle(.iconOnly).accessibilityIdentifier("practice.back")
                }
            }
            if answerFocused {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "入力を完了")) {
                        answerFocused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }.accessibilityIdentifier("practice.dismissKeyboard")
                }
            }
            if !finished && !units.isEmpty {
                if historyResult == nil {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 5) {
                            Image(systemName: "stopwatch").accessibilityLabel(String(localized: "Elapsed time"))
                            if let deadline = listeningReviewDeadline {
                                Text(timerInterval: min(.now, deadline)...deadline, countsDown: true)
                                    .accessibilityIdentifier("listening.reviewTimer")
                            } else if let partEnded {
                                Text(duration(partEnded.timeIntervalSince(partStarted)))
                            } else {
                                Text(partStarted, style: .timer)
                            }
                        }
                        .font(.subheadline.monospacedDigit())
                        .fixedSize()
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("practice.elapsed")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "この問題を保存"), systemImage: "bookmark") { store.send(.savePaper(unit)); saved = true }
                        .labelStyle(.iconOnly).accessibilityIdentifier("practice.saveToolbar")
                }
            }
        }
        .alert(String(localized: "練習を終了しますか？"), isPresented: active ? $confirmEnd : .constant(false)) {
            Button(String(localized: "練習を終了"), role: .destructive) {
                if !isMock && !completing { dismiss() } else { endPractice() }
            }
            Button(String(localized: "続ける"), role: .cancel) {}
        }
        .onDisappear { speaker?.stopSpeaking(at: .immediate); audio.stop(); audio.cancelTranscription() }
        .onChange(of: audio.transcript) { _, text in
            if unit.skill == "Speaking", !text.isEmpty { answers[unit.id + "-0"] = text }
        }
        .task(id: evaluatingID) {
            guard showingReview || isMock, let id = evaluatingID, let part = units.first(where: { $0.id == id }) else { return }
            do {
                let result = try await StudyClient.assess(part, response: answers[id + "-0", default: ""])
                try Task.checkCancellation()
                assessments[id] = result
                if let resultID = resultIDs[id] { store.send(.updateAssessment(resultID, result)) }
            } catch { if !Task.isCancelled { assessmentErrors[id] = error.localizedDescription } }
            if evaluatingID == id { evaluatingID = nil }
        }
        .alert(String(localized: "保存しました"), isPresented: active ? $saved : .constant(false)) { Button(String(localized: "学習を続ける"), role: .cancel) {} }
        .sheet(item: active ? $tutor : .constant(nil), onDismiss: { store.send(.closeQuestion) }) { request in
            TutorScreen(store: store, context: request.context, selectedText: request.selection)
        }
        .sheet(isPresented: active ? $settings : .constant(false)) { SettingsScreen(store: store.scope(state: \.settings, action: \.settings)) }
        .fullScreenCover(isPresented: active ? $conversation : .constant(false)) {
            SpeakingConversationScreen(unit: unit) { text in answers[unit.id + "-0"] = text }
        }
        .sheet(isPresented: active ? $recording : .constant(false), onDismiss: { audio.stop() }) {
            RecordingScreen(recorder: audio, title: unit.id, prompt: ([unit.title] + unit.passages + unit.oral).joined(separator: "\n\n"))
        }
    }

    private func jumpControls(_ proxy: ScrollViewProxy) -> some View {
        let index = unit.questions.indices.last { index in
            guard let answer = answers[unit.id + "-\(index)"] else { return false }
            return !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? 0
        let destination = unit.questions.isEmpty ? String(localized: "Your response")
            : String(format: String(localized: "Question %@"), String(unit.firstQuestionNumber + index))

        return GlassEffectContainer(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    jump(to: .passage, using: proxy)
                } label: {
                    Label(String(localized: "Passage"), systemImage: "text.alignleft")
                }.accessibilityIdentifier("practice.jumpPassage")
                Button {
                    jump(to: .question(index), using: proxy)
                } label: {
                    Label(destination, systemImage: "list.number")
                }.accessibilityIdentifier("practice.jumpQuestion")
            }
            .font(StudyTypography.subheadline.bold())
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func jump(to target: JumpTarget, using proxy: ScrollViewProxy) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(target, anchor: .top) }
    }

    private func exercise(showingReview: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(unit.id).font(StudyTypography.subheadline.bold()).foregroundStyle(StudyColors.accent)
            Text(showingReview ? String(localized: "答えと解説") : unit.title).font(showingReview ? StudyTypography.japaneseTitle(30) : .system(size: 24, weight: .bold))
                .id(JumpTarget.passage)
            ForEach(Array((showingReview ? [] : unit.visuals ?? []).enumerated()), id: \.offset) { _, visual in
                QuestionVisualView(visual: visual)
            }
            if showingReview {
                if let historyResult {
                    Text(historyResult.title).font(StudyTypography.headline)
                    Text(historyResult.date, style: .date).font(StudyTypography.caption)
                }
                if !unit.questions.isEmpty { scoreSummary(unit) }
                reviewContent(unit)
            } else {
                if !unit.directions.isEmpty { selectable(unit.directions, id: "directions") }
                ForEach(ExamMaterialBlock.passages(unit.passages), id: \.offset) { index, text in selectable(text, id: "passage-\(index)") }
                if let script = unit.audio {
                    ListeningAudioView(script: script, part: unit, preparationFailed: unit.audioPreparationFailed == true,
                                       onFinished: { if isLastMockListeningPart { beginListeningReview() } },
                                       openSettings: { settings = true }).id(unit.id)
                }
                if !unit.questions.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(unit.questions.indices, id: \.self) { index in
                            questionRow(index)
                                .id(JumpTarget.question(index))
                        }
                    }
                }
                if unit.skill == "Writing" {
                    Text(String(localized: "Your response")).font(StudyTypography.headline)
                        .id(JumpTarget.question(0))
                    TextEditor(text: binding(0)).disabled(recorded.contains(unit.id)).focused($answerFocused).keyboardType(.asciiCapable).frame(minHeight: 220)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                        .accessibilityLabel(String(localized: "英作文の回答"))
                    Text(String(format: String(localized: "Word count: %@"), String(binding(0).wrappedValue.split(whereSeparator: \.isWhitespace).count))).font(StudyTypography.caption)
                }
                ForEach(unit.oral.indices, id: \.self) { index in
                    selectable(unit.oral[index], id: "oral-\(index)")
                    Button(String(localized: "質問を聞く"), systemImage: "speaker.wave.2") { speak(unit.oral[index]) }
                }
                if unit.skill == "Speaking" {
                    Button(String(localized: "AI試験官と音声会話"), systemImage: "waveform") {
                        speaker?.stopSpeaking(at: .immediate); audio.stop(); audio.cancelTranscription(); conversation = true
                    }.buttonStyle(StudyPrimaryButtonStyle()).accessibilityIdentifier("speaking.conversation").disabled(recorded.contains(unit.id))
                        .id(JumpTarget.question(0))
                    Button(String(localized: "マイクで回答"), systemImage: "mic.fill") {
                        speaker?.stopSpeaking(at: .immediate)
                        recording = true
                    }.disabled(recorded.contains(unit.id))
                    if audio.hasRecording {
                        HStack {
                            Button(String(localized: "録音を聞く"), systemImage: "play.fill") { audio.play() }
                            Button(String(localized: "文字起こし"), systemImage: "text.bubble") { Task { await audio.transcribe() } }
                                .disabled(audio.transcribing || recorded.contains(unit.id))
                        }
                    }
                    if audio.transcribing { ProgressView(String(localized: "端末内で文字起こし中…")) }
                    Text(String(localized: "回答の文字起こし")).font(StudyTypography.headline)
                    TextEditor(text: binding(0)).disabled(recorded.contains(unit.id)).focused($answerFocused).keyboardType(.asciiCapable).frame(minHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                        .accessibilityLabel(String(localized: "スピーキングの文字起こし"))
                    Text(String(localized: "文字起こしを確認・修正してから講評へ進めます。認識できない場合は回答を入力してください。"))
                        .font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                    if let error = audio.error { Text(error).foregroundStyle(StudyColors.error) }
                }
            }
            VStack(spacing: 12) {
                if historyResult == nil {
                    Button {
                        answerFocused = false
                        if !isMock && !showingReview {
                            speaker?.stopSpeaking(at: .immediate)
                            if partEnded == nil { partEnded = Date() }
                            reviewPresented = true
                            saveResult(unit)
                            if !hasReachedReview {
                                hasReachedReview = true
                                onFirstReview()
                            }
                        } else if isLastMockListeningPart { beginListeningReview() } else { advance() }
                    } label: {
                        Label(isLastMockListeningPart ? String(localized: "Check listening answers") : isMock ? (position + 1 < units.count ? String(localized: "次のパートへ") : String(localized: "テストを終了して結果を見る")) : showingReview ? (position + 1 < units.count ? String(localized: "次のパートへ") : String(localized: "練習を終了")) : String(localized: "解答・振り返りを確認"),
                              systemImage: showingReview || isMock ? "arrow.right" : "checkmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(StudyPrimaryButtonStyle())
                    .disabled(audio.transcribing || audio.isRecording)
                    .accessibilityIdentifier("practice.review")
                }
                if showingReview && !isMock {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        Button(String(localized: "この問題を保存"), systemImage: "bookmark") {
                            store.send(.savePaper(unit)); saved = true
                        }.accessibilityIdentifier("practice.save")
                        Button(String(localized: "この問題をAIに質問"), systemImage: "bubble.left.and.bubble.right") {
                            openTutor(material(unit))
                        }.accessibilityIdentifier("practice.ask")
                    }.buttonStyle(StudySecondaryButtonStyle())
                }
                if historyResult != nil {
                    StudyLink { ExamScreen(units: [unit], store: store) } label: {
                        Label(String(localized: "この問題をもう一度練習"), systemImage: "arrow.counterclockwise")
                    }.buttonStyle(StudySecondaryButtonStyle())
                } else if showingReview {
                    Button(String(localized: "このパートをもう一度"), systemImage: "arrow.counterclockwise") {
                        reviewPresented = false
                        markedWords[unit.id] = nil
                        partStarted = Date()
                        partEnded = nil
                        questionPageID = UUID()
                        recorded.remove(unit.id)
                        answers = answers.filter { !$0.key.hasPrefix(unit.id + "-") }
                        audio.clear(); assessments[unit.id] = nil; assessmentErrors[unit.id] = nil
                        resultIDs[unit.id] = nil; recordingFiles[unit.id] = nil
                    }.buttonStyle(StudySecondaryButtonStyle())
                        .accessibilityIdentifier("practice.retry")
                }
            }.padding(.top, 8)

        }
    }

    private var isLastMockListeningPart: Bool {
        isMock && unit.skill == "Listening" && !units.dropFirst(position + 1).contains { $0.skill == "Listening" }
    }

    private func beginListeningReview() {
        guard listeningReviewDeadline == nil else { return }
        listeningReviewPart = 0
        listeningReviewDeadline = Date().addingTimeInterval(120)
        speak("That is the end of the listening test. You now have two minutes to check your answers.")
    }

    private func finishListeningReview() {
        guard listeningReviewDeadline != nil else { return }
        listeningReviewDeadline = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if position + 1 < units.count { advance() }
        else { completing = true; endPractice() }
    }

    private func listeningAnswerReview(_ deadline: Date) -> some View {
        let parts = units.filter { $0.skill == "Listening" }
        let part = parts[listeningReviewPart]
        return VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Check listening answers")).font(StudyTypography.heading)
            Picker("Listening", selection: $listeningReviewPart) {
                ForEach(parts.indices, id: \.self) { index in
                    Text(verbatim: parts[index].id.components(separatedBy: " · ")[0]
                        .replacingOccurrences(of: "Listening / ", with: "")).tag(index)
                }
            }.pickerStyle(.segmented)
            ForEach(Array((part.visuals ?? []).enumerated()), id: \.offset) { _, visual in QuestionVisualView(visual: visual) }
            ForEach(part.questions.indices, id: \.self) { index in questionRow(index, for: part) }
                .id(part.id)
            Button(String(localized: "Finish review")) { finishListeningReview() }
                .buttonStyle(StudyPrimaryButtonStyle())
        }
        .task(id: deadline) {
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
            finishListeningReview()
        }
    }

    private func questionRow(_ index: Int, for part: ExamUnit? = nil) -> some View {
        let part = part ?? unit
        return VStack(alignment: .leading, spacing: 20) {
            let item = part.questions[index]
            if index == 0 || part.questions[index-1].instruction != item.instruction {
                VStack(alignment: .leading, spacing: 10) {
                    Label(String(localized: "解答のルール"), systemImage: "info.circle").font(StudyTypography.subheadline.bold())
                        .foregroundStyle(StudyColors.accent)
                    selectable(StudyQuestionLayout(item.instruction).formatted, id: "instruction-\(index)", for: part)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudyColors.reading.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("Question \(part.firstQuestionNumber + index)").font(StudyTypography.subheadline.bold())
                    .foregroundStyle(StudyColors.accent)
                selectable(item.displayPrompt(number: part.firstQuestionNumber + index, localNumber: index + 1), id: "question-\(index)", for: part)
                if !item.choices.isEmpty {
                    Text(String(localized: "丸いボタンをタップして解答")).font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                    ForEach(item.choices, id: \.self) { choice in
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                binding(index, for: part).wrappedValue = choice
                            } label: {
                                Image(systemName: binding(index, for: part).wrappedValue == choice ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).frame(width: 44, height: 44)
                            }.buttonStyle(.plain).foregroundStyle(StudyColors.accent)
                                .disabled(recorded.contains(part.id))
                                .accessibilityLabel(String(format: String(localized: "%@を選択"), item.choiceText(choice)))
                                .accessibilityValue(binding(index, for: part).wrappedValue == choice ? String(localized: "選択済み") : String(localized: "未選択"))
                                .accessibilityIdentifier("answer.choice.\(index).\(choice)")
                            selectable(item.choiceText(choice), id: "choice-\(index)-\(choice)", for: part)
                                .padding(.vertical, 10)
                        }.padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(binding(index, for: part).wrappedValue == choice ? StudyColors.reading.opacity(0.5) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(StudyColors.accent.opacity(binding(index, for: part).wrappedValue == choice ? 0.8 : 0.2)))
                    }
                } else {
                    ShortAnswerField(text: binding(index, for: part))
                        .disabled(recorded.contains(part.id))
                }
            }.padding(16).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40)).foregroundStyle(StudyColors.accent)
                    .padding(16).background(StudyColors.reading, in: RoundedRectangle(cornerRadius: 22))
                Text(isMock ? String(localized: "今回の模試結果") : String(localized: "練習を終了しました"))
                    .font(StudyTypography.japaneseTitle(28))
                Text(String(localized: "技能別の推移は学習記録で確認できます。"))
                    .font(StudyTypography.subheadline).foregroundStyle(StudyColors.secondaryText)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(24).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 24))
                .accessibilityIdentifier("practice.completion")
            if isMock {
                let records = store.records.filter { $0.attemptID == attemptID }
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "推定 IELTS Overall")).font(StudyTypography.headline)
                    Text(StudyBand.label(StudyBand.overall(records)) + "  /  CEFR " + StudyBand.cefr(StudyBand.overall(records))).font(StudyTypography.heading)
                    ForEach(["Listening", "Reading", "Writing", "Speaking"], id: \.self) { skill in
                        HStack { Text(skill); Spacer(); Text(StudyBand.label(StudyBand.skill(skill, records: records))) }
                    }
                    Text(String(localized: "Writing・Speakingの講評後に全体の学習用推定を表示します。発音の評価は含みません。"))
                        .font(StudyTypography.footnote)
                }.padding(20).foregroundStyle(.white).background(StudyColors.levelCard, in: RoundedRectangle(cornerRadius: 20))
            }
            ForEach(units.filter { recorded.contains($0.id) }) { part in
                VStack(alignment: .leading, spacing: 10) {
                    Text(part.id).font(StudyTypography.headline)
                    if !part.questions.isEmpty { scoreSummary(part) }
                    else { Text(String(localized: "学習用推定 ") + StudyBand.label(assessments[part.id]?.estimatedBand)).font(StudyTypography.subheadline) }
                    DisclosureGroup(String(localized: "答えと解説・振り返り")) { reviewContent(part) }
                    if part.skill == "Writing", let response = answers[part.id + "-0"] {
                        DisclosureGroup(String(localized: "あなたの回答")) { Text(response).textSelection(.enabled) }
                    }
                }.padding().background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
            }
            Button(String(localized: "学習記録を見る"), systemImage: "chart.bar.xaxis") { navigation.progress() }
                .buttonStyle(StudyPrimaryButtonStyle())
            Button(String(localized: "ホームに戻る"), systemImage: "house") { navigation.home() }
                .buttonStyle(StudySecondaryButtonStyle())
            Button(String(localized: "もう一度練習する"), systemImage: "arrow.counterclockwise") {
                markedWords = [:]
                position = 0; finished = false; answers = [:]; reviewPresented = false; recorded = []; evaluatingID = nil
                partStarted = Date(); partEnded = nil
                started = partStarted; ended = nil; audio.clear(); attemptID = UUID(); resultIDs = [:]; assessments = [:]; assessmentErrors = [:]; recordingFiles = [:]
            }.buttonStyle(StudySecondaryButtonStyle())
        }
    }

    private func scoreSummary(_ part: ExamUnit) -> some View {
        Text(String(format: String(localized: "%@ / %@ 正解"), String(historyResult?.correct ?? score(part)), String(historyResult?.total ?? part.questions.count)))
            .font(StudyTypography.heading)
            .accessibilityIdentifier("practice.score")
    }

    private func reviewContent(_ part: ExamUnit) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ReadingReviewButton(part: part, store: store)
            ListeningReviewButton(part: part, transcript: $transcripts[part.id], question: nil)
            if let words = markedWords[part.id], !words.isEmpty {
                MarkedWordReview(words: words, store: store)
            }
            if part.questions.isEmpty {
                DisclosureGroup(part.title) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !part.directions.isEmpty { reviewText(part.directions) }
                        ForEach(ExamMaterialBlock.passages(part.passages + part.oral), id: \.offset) { _, text in reviewText(text) }
                        if isMock || historyResult != nil {
                            ForEach(Array((part.visuals ?? []).enumerated()), id: \.offset) { _, visual in QuestionVisualView(visual: visual) }
                        }
                    }.textSelection(.enabled)
                }
            }

            ForEach(part.questions.indices, id: \.self) { index in
                let question = part.questions[index]
                let storedAnswer = answers[part.id + "-\(index)"]
                let answer = storedAnswer ?? ""
                let hasAnswerData = historyResult == nil || storedAnswer != nil
                let resultIcon = question.accepts(answer) ? "checkmark.circle.fill" : "xmark.circle"
                VStack(alignment: .leading, spacing: 8) {
                    Text("Question \(part.firstQuestionNumber + index)").font(StudyTypography.subheadline.bold()).foregroundStyle(StudyColors.accent)
                    Text(question.displayPrompt(number: part.firstQuestionNumber + index, localNumber: index + 1))
                        .font(StudyTypography.headline).textSelection(.enabled)
                    Label(question.answers.map { question.choiceText($0) }.joined(separator: " / "),
                          systemImage: hasAnswerData ? resultIcon : "checklist")
                        .font(StudyTypography.headline)
                    if hasAnswerData {
                        Text(String(localized: "あなたの解答: ") + (answer.isEmpty ? String(localized: "未回答") : answer)).font(StudyTypography.caption)
                    }
                    SelectableStudyText(text: question.explanation, sourceID: part.id + "-explanation-\(index)") { entry in
                        save(entry, paper: part)
                    } onAsk: { entry in openTutor(material(part) + String(localized: "\n選択範囲: ") + entry.expression, selection: entry.expression) }
                    ListeningReviewButton(part: part, transcript: $transcripts[part.id], question: part.firstQuestionNumber + index)
                    QuestionReviewActions(part: part, index: index, answer: answer, store: store)
                }
            }
            if part.questions.isEmpty {
                if let file = recordingFiles[part.id] {
                    Button(String(localized: "保存した録音を聞く"), systemImage: "play.circle") { audio.playArchived(file) }
                }
                if let response = answers[part.id + "-0"], !response.isEmpty {
                    DisclosureGroup(String(localized: "あなたの回答")) { Text(response).textSelection(.enabled) }
                }
                if let assessment = assessments[part.id] {
                    AssessmentContent(assessment: assessment, paper: part, store: store)
                } else {
                    Text(String(localized: "評価の観点")).font(StudyTypography.headline)
                    ForEach(part.skill == "Writing" ? ["Task response", "Coherence and cohesion", "Lexical resource", "Grammatical range and accuracy"] : ["Fluency and coherence", "Lexical resource", "Grammatical range and accuracy", "Pronunciation"], id: \.self) { Text($0).bold() }
                }
                if let error = assessmentErrors[part.id] ?? audio.error { Text(error).foregroundStyle(StudyColors.error) }
                if !store.settings.canPractice { Button(String(localized: "ChatGPTの接続設定"), systemImage: "person.crop.circle") { settings = true }.buttonStyle(StudySecondaryButtonStyle()) }
                if evaluatingID == part.id { ProgressView(String(localized: "回答を講評中…")) }
                Button(assessments[part.id] == nil ? String(localized: "AIの講評を見る") : String(localized: "講評を更新")) {
                    assessmentErrors[part.id] = nil; evaluatingID = part.id
                }.buttonStyle(.borderedProminent)
                    .disabled(evaluatingID != nil || answers[part.id + "-0", default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if answers[part.id + "-0", default: ""].isEmpty {
                    Text(String(localized: "回答がありません。このパートをもう一度練習すると講評を受けられます。"))
                        .font(StudyTypography.footnote).foregroundStyle(StudyColors.secondaryText)
                }
                Text(String(localized: "AIによる学習用の推定です。Speakingは文字起こしを使うため、発音・音声の流暢さは評価に含みません。"))
                    .font(StudyTypography.footnote).foregroundStyle(StudyColors.secondaryText)
                Button(String(localized: "AIに追加で質問")) { openTutor(material(part) + String(localized: "\n学習者の回答:\n") + answers[part.id + "-0", default: ""]) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
        .task(id: part.id) { transcripts[part.id] = ListeningTranscript(part: part) }
    }
    private func reviewText(_ text: String) -> some View {
        ExamMaterialText(text: text) { fragment, _ in Text(verbatim: fragment) }
    }

    private func selectable(_ text: String, id: String, for part: ExamUnit? = nil) -> some View {
        let part = part ?? unit
        return ExamMaterialText(text: text) { fragment, suffix in
            SelectableStudyText(text: fragment, sourceID: part.id + id + suffix, onSave: { entry in
                if !(markedWords[part.id] ?? []).contains(where: { $0.id == entry.id }) {
                    markedWords[part.id, default: []].append(entry)
                }
                save(entry, paper: part)
            },
                onAsk: isMock ? nil : { openTutor(material(part) + String(localized: "\n選択範囲: ") + $0.expression, selection: $0.expression) },
                allowsAI: !isMock, forLaterReview: true)
        }
    }
    private func save(_ entry: SelectableStudyText.Entry, paper: ExamUnit) {
        store.send(.saveExpression(SavedExpression(expression: entry.expression, source: paper.id,
                                                  sourceText: entry.sourceText, meaning: entry.meaning, paper: paper, sourceID: entry.sourceID, selectionLocation: entry.utf16Range.location, selectionLength: entry.utf16Range.length)))
    }
    private func openTutor(_ value: String, selection: String? = nil) {
        tutor = TutorRequest(context: value, selection: selection)
    }
    private func material(_ part: ExamUnit) -> String {
        ([part.id, part.title, part.directions] + part.passages + part.questions.map { $0.prompt + "\n" + $0.explanation } + part.oral + [part.audio ?? ""]).joined(separator: "\n") + QuestionVisual.context(part.visuals)
    }
    private func saveResult(_ part: ExamUnit) {
        guard !recorded.contains(part.id) else { return }
        let id = UUID()
        resultIDs[part.id] = id
        if part.skill == "Speaking", part.id == unit.id, audio.hasRecording, recordingFiles[part.id] == nil {
            do { recordingFiles[part.id] = try audio.archive() }
            catch { assessmentErrors[part.id] = String(localized: "録音の保存に失敗しました: ") + error.localizedDescription }
        }
        store.send(.record(StudyResult(id: id, skill: part.skill, title: part.title,
            correct: score(part), total: part.questions.count, isMock: isMock,
            response: part.questions.isEmpty ? answers[part.id + "-0"] : nil, assessment: assessments[part.id],
            recordingFile: recordingFiles[part.id], paper: part, attemptID: attemptID,
            markedExpressions: markedWords[part.id],
            questionAnswers: part.questions.isEmpty ? nil : part.questions.indices.map { answers[part.id + "-\($0)", default: ""] })))
        recorded.insert(part.id)
    }
    private func endPractice() {
        speaker?.stopSpeaking(at: .immediate)
        audio.stop(); audio.cancelTranscription()
        if completing { units.forEach(saveResult) }
        ended = Date()
        if isMock && completing {
            finished = true
        } else {
            navigation.home()
        }
    }

    private func advance() {
        speaker?.stopSpeaking(at: .immediate); audio.stop()
        // Preserve each speaking recording before moving to a new part.
        if unit.skill == "Speaking", audio.hasRecording, recordingFiles[unit.id] == nil {
            do { recordingFiles[unit.id] = try audio.archive() }
            catch { assessmentErrors[unit.id] = error.localizedDescription }
        }
        if position + 1 < units.count {
            reviewPresented = false
            position += 1
            partStarted = Date()
            partEnded = nil
            audio.clear()
        } else {
            completing = true
            if unsavedUnits.isEmpty { endPractice() } else { confirmEnd = true }
        }
    }
    private func binding(_ index: Int, for part: ExamUnit? = nil) -> Binding<String> {
        let key = (part ?? unit).id + "-\(index)"
        return Binding(get: { answers[key, default: ""] }, set: { answers[key] = $0 })
    }
    private func score(_ part: ExamUnit) -> Int {
        part.questions.enumerated().filter { $0.element.accepts(answers[part.id + "-\($0.offset)", default: ""]) }.count
    }
    private func speak(_ text: String) {
        audio.stop(); speaker?.stopSpeaking(at: .immediate)
        let speech = AVSpeechUtterance(string: text)
        speech.voice = AVSpeechSynthesisVoice(language: "en-GB")
        if speaker == nil { speaker = AVSpeechSynthesizer() }
        speaker?.speak(speech)
    }
    private func duration(_ seconds: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

@MainActor @Observable
final class SpeakingRecorder {
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var file: URL?
    private var recognition: SFSpeechRecognitionTask?
    private var recognitionID: UUID?
    var transcript = ""
    var transcribing = false
    var isRecording = false
    var hasRecording = false
    var error: String?
    var level: CGFloat = 0
    var elapsed: TimeInterval = 0

    func start() async {
        error = nil
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard !Task.isCancelled else { return }
        guard allowed else { error = String(localized: "設定アプリでPokeltsのマイク使用を許可してください。"); return }
        do {
            stop()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let next = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            next.isMeteringEnabled = true
            guard next.record() else { throw StudyError.message(String(localized: "録音を開始できませんでした。")) }
            if let file { try? FileManager.default.removeItem(at: file) }
            file = url; recorder = next; isRecording = true; hasRecording = false; elapsed = 0; transcript = ""
        } catch { self.error = error.localizedDescription }
    }
    func update() {
        guard let recorder, isRecording else { return }
        recorder.updateMeters()
        level = CGFloat(pow(10, recorder.averagePower(forChannel: 0) / 40))
        elapsed = recorder.currentTime
        if !recorder.isRecording { stop() }
    }
    func stop() {
        let ownedAudioSession = isRecording || player?.isPlaying == true
        if isRecording { elapsed = recorder?.currentTime ?? elapsed; recorder?.stop(); hasRecording = elapsed > 0 }
        isRecording = false; level = 0; player?.stop()
        // A covered recorder can disappear after the conversation starts. An idle
        // recorder must not deactivate the process-wide session owned by that conversation.
        if ownedAudioSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    func play() {
        stop()
        guard let file, hasRecording else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: file)
            player?.play()
        } catch { self.error = error.localizedDescription }
    }
    func transcribe() async {
        stop(); cancelTranscription(); error = nil
        guard let file, hasRecording else { return }
        let id = UUID(); recognitionID = id; transcribing = true
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard recognitionID == id, !Task.isCancelled else { return }
        guard permission == .authorized else {
            transcribing = false; recognitionID = nil
            error = String(localized: "設定で音声認識を許可するか、回答をテキストで入力してください。"); return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            transcribing = false; recognitionID = nil
            error = String(localized: "この端末では英語の端末内文字起こしを利用できません。回答をテキストで入力してください。"); return
        }
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let value = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor in
                guard let self, self.recognitionID == id else { return }
                if let value { self.transcript = value }
                if final || failure != nil {
                    self.transcribing = false; self.recognitionID = nil; self.recognition = nil
                    if let failure, self.transcript.isEmpty { self.error = String(localized: "文字起こしに失敗しました。回答を入力できます。\n") + failure }
                }
            }
        }
    }
    func cancelTranscription() {
        recognitionID = nil; recognition?.cancel(); recognition = nil; transcribing = false
    }
    static var archiveDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings", isDirectory: true)
    }
    func archive() throws -> String? {
        stop()
        guard let file, hasRecording else { return nil }
        try FileManager.default.createDirectory(at: Self.archiveDirectory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".m4a"
        try FileManager.default.copyItem(at: file, to: Self.archiveDirectory.appendingPathComponent(name))
        return name
    }
    func playArchived(_ name: String) {
        guard name == URL(fileURLWithPath: name).lastPathComponent else { return }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: Self.archiveDirectory.appendingPathComponent(name))
            player?.play()
        } catch { self.error = error.localizedDescription }
    }
    func clear() {
        cancelTranscription(); transcript = ""
        stop()
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil; hasRecording = false; elapsed = 0
    }
}

struct RecordingScreen: View {
    let recorder: SpeakingRecorder
    let title: String
    let prompt: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                Text(title).font(StudyTypography.heading)
                ScrollView { Text(prompt).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading) }
                Text(recorder.isRecording ? String(localized: "録音中") : String(localized: "録音停止")).bold().foregroundStyle(StudyColors.accent)
                TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                    HStack(spacing: 5) {
                        ForEach(0..<32, id: \.self) { index in
                            Capsule().fill(StudyColors.accent)
                                .frame(height: max(4, recorder.level * CGFloat(25 + (index * 17 % 55))))
                        }
                    }.frame(height: 98).padding(.horizontal, 14)
                        .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
                        .onChange(of: timeline.date) { _, _ in recorder.update() }
                        .accessibilityLabel(String(localized: "録音レベル"))
                }
                Text(String(format: "%02d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60)).monospacedDigit()
                if let error = recorder.error { Text(error).foregroundStyle(StudyColors.error) }
                Button(String(localized: "録音を停止して課題に戻る")) { recorder.stop(); dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(20)
                .toolbar { Button(String(localized: "閉じる")) { recorder.stop(); dismiss() } }
                .task { await recorder.start() }
                .onDisappear { recorder.stop() }
        }
    }
}

struct GeneratedExamScreen: View {
    let templates: [ExamUnit]
    let store: StoreOf<StudyFeature>
    var isMock = false
    @State private var generated: [ExamUnit] = []
    @State private var generationStarted = Date()
    @State private var completionStarted: Date?
    @State private var generationFraction: Double?
    @State private var showQuestions = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var error: String?
    @State private var attempt = 0
    @State private var settings = false
    @Environment(\.dismiss) private var dismiss
    private let sections = SectionPreparation.shared
    private var section: ExamUnit? { isMock ? nil : templates.first }

    init(templates: [ExamUnit], store: StoreOf<StudyFeature>, isMock: Bool = false) {
        self.templates = templates
        self.store = store
        self.isMock = isMock
        if !isMock, let template = templates.first,
           let paper = SectionPreparation.shared.ready[SectionPreparation.shared.key(template)] {
            _generated = State(initialValue: [paper])
            _showQuestions = State(initialValue: true)
        }
    }

    var body: some View {
        ZStack {
            if showQuestions {
                ExamScreen(onFirstReview: {
                    if let section, let paper = generated.first { sections.finished(section, paper: paper) }
                }, units: generated, store: store, isMock: isMock)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if let error {
                                Label(String(localized: "生成を完了できませんでした"), systemImage: "book.closed").font(StudyTypography.heading)
                                Text(error).foregroundStyle(StudyColors.error)
                                Button(String(localized: "もう一度生成"), systemImage: "arrow.clockwise") { self.error = nil; attempt += 1 }.buttonStyle(StudyPrimaryButtonStyle())
                                Button(String(localized: "ChatGPTの接続設定"), systemImage: "person.crop.circle") { settings = true }.buttonStyle(StudySecondaryButtonStyle())
                            } else {
                                GenerationLoadingView(completed: generated.count, total: templates.count,
                                                      started: generationStarted, completionStarted: completionStarted, fraction: section.flatMap { sections.percent[sections.key($0)].map { Double($0) / 100 } } ?? generationFraction)
                                WaitingVocabularyView(words: store.vocabulary)
                            }
                            Button(section != nil && UserDefaults.standard.bool(forKey: SectionPreparation.preference) ? String(localized: "Back to sections") : String(localized: "キャンセルして戻る"), systemImage: "chevron.backward") { dismiss() }
                                .buttonStyle(StudySecondaryButtonStyle())
                        }.padding(24).frame(maxWidth: 480)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                }.transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
        }
        .task(id: attempt) {
            if let section {
                guard !showQuestions else { return }
                do {
                    let paper = try await sections.open(section)
                    try Task.checkCancellation()
                    generated = [paper]
                    generationFraction = 1
                    completionStarted = Date()
                    try await Task.sleep(for: .milliseconds(350))
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.38)) { showQuestions = true }
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                return
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ProcessInfo.processInfo.arguments.contains("--ui-generation-preview") {
                try? await Task.sleep(for: .seconds(120))
                return
            }
            #endif
            guard !templates.isEmpty else { error = String(localized: "教材がありません。"); return }
            do {
                try await BackgroundGeneration.run(title: String(localized: "あなただけの問題を準備中"), total: templates.count, completionDuration: 0.8, onProgress: { generationFraction = $0 }) { progress in
                    progress.update(completed: generated.count, total: templates.count)
                    for template in templates.dropFirst(generated.count) {
                        generationStarted = Date()
                        let unit = try await StudyClient.generateUnit(like: template)
                        try Task.checkCancellation()
                        if generated.count + 1 == templates.count {
                            completionStarted = Date()
                        }
                        generated.append(unit)
                        progress.update(completed: generated.count, total: templates.count)
                    }
                }
                await GenerationNotifications.post(title: String(localized: "問題の準備ができました"), body: String(localized: "模擬テスト"))
                try await Task.sleep(for: .milliseconds(1300))
                try Task.checkCancellation()
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.38)) { showQuestions = true }
            } catch is CancellationError {
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .onDisappear {
            if let section, !showQuestions { sections.leaveLoading(section) }
        }
        .sheet(isPresented: $settings) { SettingsScreen(store: store.scope(state: \.settings, action: \.settings)) }
    }
}

struct AssessmentContent: View {
    let assessment: PracticeAssessment
    let paper: ExamUnit
    let store: StoreOf<StudyFeature>
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(String(localized: "学習用推定 ") + StudyBand.label(assessment.estimatedBand)).font(StudyTypography.roundedTitle(28))
            if assessment.isPartial { Text(String(localized: "発音を除く、回答内容の推定")).font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText) }
            Text(assessment.summary)
            ForEach(assessment.criteria, id: \.name) { criterion in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(criterion.name).bold(); Spacer(); Text(criterion.band.map { String(format: "%.1f", $0) } ?? String(localized: "未評価")) }
                    Text(criterion.feedback).font(StudyTypography.subheadline)
                }.padding(16).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
            }
            Text(String(localized: "改善例")).font(StudyTypography.headline)
            SelectableStudyText(text: assessment.improvedResponse, sourceID: paper.id + "-improved", onSave: { entry in
                store.send(.saveExpression(SavedExpression(expression: entry.expression, source: paper.id,
                    sourceText: entry.sourceText, meaning: entry.meaning, paper: paper,
                    sourceID: entry.sourceID, selectionLocation: entry.utf16Range.location, selectionLength: entry.utf16Range.length)))
            })
        }
    }
}

enum GenerationProgress {
    static func estimate(completed: Int, total: Int, elapsed: Double) -> Double {
        min(0.99, (Double(completed) + min(0.9, 0.9 * (1 - exp(-max(0, elapsed) / 45)))) / Double(max(1, total)))
    }
    static func finish(from: Double, elapsed: Double) -> Double {
        let t = min(1, max(0, elapsed / 0.8))
        return from + (1 - from) * (1 - pow(1 - t, 3))
    }
}

/// An explicitly estimated indicator: only validated units count as completed.
private struct GenerationLoadingView: View {
    let completed: Int
    let total: Int
    let started: Date
    let completionStarted: Date?
    let fraction: Double?
    var body: some View {
        TimelineView(.periodic(from: .now, by: completionStarted == nil ? 1 : 1.0 / 60)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(started))
            let estimate = fraction ?? GenerationProgress.estimate(completed: completed, total: total, elapsed: elapsed)
            VStack(spacing: 24) {
                LoadingBookMascot().scaleEffect(0.5).frame(height: 110)
                VStack(spacing: 10) {
                    Text(completionStarted == nil ? String(localized: "あなただけの問題を準備中") : String(localized: "問題の準備ができました")).font(StudyTypography.ui(24, relativeTo: .title2, bold: true)).multilineTextAlignment(.center)
                    Text(String(localized: "小さな一歩が、大きな自信に。")).font(StudyTypography.subheadline).foregroundStyle(StudyColors.secondaryText)
                }
                VStack(spacing: 12) {
                    HStack {
                        Text(String(localized: "進捗の目安")).font(StudyTypography.subheadline)
                        Spacer()
                        Text(completionStarted == nil ? String(format: String(localized: "約 %@%% "), String(Int(estimate * 100))) : "\(Int(estimate * 100))%")
                            .monospacedDigit().bold().accessibilityIdentifier("generation.percent")
                    }
                    ProgressView(value: estimate).tint(StudyColors.accent)
                    Text(String(format: String(localized: "生成・確認済み %@ / %@ セクション"), String(completed), String(total)))
                        .font(StudyTypography.footnote).foregroundStyle(StudyColors.secondaryText)
                    Text(completionStarted != nil ? String(localized: "準備完了。まもなく問題を開きます。") : elapsed > 90 ? String(localized: "もう少し時間がかかっています。完了までこの画面でお待ちください。") : String(localized: "本文・設問・解説を作成しています。表示は時間に基づく目安です。"))
                        .font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText).multilineTextAlignment(.center)
                }.padding(20).background(StudyColors.reading.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
}

/// Only the illustration updates at display cadence; progress text updates once a second.
private struct LoadingBookMascot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var animationStarted = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0,
                                paused: reduceMotion || scenePhase != .active)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(animationStarted))
                ZStack {
                    Circle().fill(StudyColors.reading).frame(width: 196, height: 196)
                    ForEach(0..<4) { index in
                        Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                            .font(.system(size: index.isMultiple(of: 2) ? 22 : 8))
                            .foregroundStyle(StudyColors.accent.opacity(0.65))
                            .offset(x: index.isMultiple(of: 2) ? -90 : 90,
                                    y: CGFloat(index - 2) * 42 + (reduceMotion ? 0 : sin(elapsed + Double(index)) * 6))
                    }
                    ZStack {
                        Image(systemName: "book.fill")
                            .font(.system(size: 100)).foregroundStyle(StudyColors.accent)
                        HStack(spacing: 38) {
                            Capsule().frame(width: 5, height: 8)
                            Capsule().frame(width: 5, height: 8)
                        }.foregroundStyle(.white).offset(x: 5, y: -10)
                        Text("⌣").font(.system(size: 26, weight: .bold)).foregroundStyle(.white).offset(x: 5, y: 6)
                    }
                    .rotationEffect(.degrees(reduceMotion ? 0 : sin(elapsed * 1.8) * 5))
                    .offset(y: reduceMotion ? 0 : sin(elapsed * 1.8) * 7)
                }.frame(height: 220).accessibilityHidden(true)
        }
    }
}

private extension StudyTextView.Entry {
    var reviewKey: MarkedWordKey {
        MarkedWordKey(expression: expression, context: StudyTextSelection.excerpt(sourceText, range: utf16Range, expression: expression),
                      language: StudyClient.explanationLanguage)
    }
}

extension ExamScreen {
    init(reviewing result: StudyResult, paper: ExamUnit, store: StoreOf<StudyFeature>) {
        self.init(units: [paper], store: store, historyResult: result)
        var responses: [String: String] = [:]
        for (index, answer) in (result.questionAnswers ?? []).enumerated() {
            responses[paper.id + "-\(index)"] = answer
        }
        if let response = result.response { responses[paper.id + "-0"] = response }
        _answers = State(initialValue: responses)
        _markedWords = State(initialValue: [paper.id: result.markedExpressions ?? []])
        _recordingFiles = State(initialValue: result.recordingFile.map { [paper.id: $0] } ?? [:])
        _assessments = State(initialValue: result.assessment.map { [paper.id: $0] } ?? [:])
        _resultIDs = State(initialValue: [paper.id: result.id])
    }
}

private struct MarkedWordReview: View {
    let words: [SelectableStudyText.Entry]
    let store: StoreOf<StudyFeature>
    @State private var settings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Words to review"), systemImage: "bookmark.fill").font(StudyTypography.heading)
            ForEach(words) { word in
                let key = word.reviewKey
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: word.expression).bold()
                    switch store.markedMeanings[key] {
                    case let .ready(meaning): Text(verbatim: meaning).textSelection(.enabled)
                    case let .failed(message):
                        Text(verbatim: message).foregroundStyle(StudyColors.error)
                        if store.settings.canPractice {
                            Button(String(localized: "もう一度生成")) { store.send(.explainMarkedWord(key)) }
                        }
                    case .loading: ProgressView()
                    case nil:
                        if key.language == "English", let match = StarterWord.all.first(where: { $0.expression.caseInsensitiveCompare(word.expression) == .orderedSame }) {
                            Text(verbatim: match.definition)
                        }
                    }
                    Text(verbatim: key.context).font(StudyTypography.subheadline).foregroundStyle(StudyColors.secondaryText)
                }
                .task(id: store.settings.canPractice) {
                    if store.markedMeanings[key] == nil { store.send(.explainMarkedWord(key)) }
                }
            }
            if !store.settings.canPractice { Button(String(localized: "ChatGPTの接続設定")) { settings = true } }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding()
        .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $settings) { SettingsScreen(store: store.scope(state: \.settings, action: \.settings)) }
    }
}

/// Each review row owns its presentation so dismissal returns to the same answer.
struct QuestionReviewActions: View {
    let part: ExamUnit
    let index: Int
    let answer: String
    let store: StoreOf<StudyFeature>
    private enum Destination: Int, Identifiable {
        case source, tutor
        var id: Int { rawValue }
    }
    @State private var destination: Destination?
    private var question: ReadingSet.Question { part.questions[index] }
    private var context: String {
        ([part.title, part.directions] + part.passages + [part.audio ?? "", QuestionVisual.context(part.visuals),
          "Question \(part.firstQuestionNumber + index)", question.instruction, question.prompt,
          "Accepted answers: " + question.answers.map(question.choiceText).joined(separator: " / "),
          "Learner answer: " + (answer.isEmpty ? "Unanswered" : question.choiceText(answer)),
          "Provided explanation: " + question.explanation]).joined(separator: "\n")
    }
    var body: some View {
        HStack {
            Button { destination = .source } label: {
                Label(String(localized: "全文を見る"), systemImage: "text.magnifyingglass")
            }.accessibilityIdentifier("review.source.\(index)")
            Button {
                destination = .tutor
                store.send(.ask(context, String(localized: "この問題の正解の根拠を、本文の該当箇所を示して説明してください。")))
            } label: { Label(String(localized: "AIに質問"), systemImage: "bubble.left.and.bubble.right") }.accessibilityIdentifier("review.tutor.\(index)")
        }.buttonStyle(.bordered)
        .sheet(item: $destination, onDismiss: { store.send(.closeQuestion) }) { route in
            if route == .tutor {
                TutorScreen(store: store, context: context, selectedText: question.prompt)
            } else {
                ReviewSourceSheet(part: part, index: index, store: store)
            }
        }
    }
}

struct ReadingReviewButton: View {
    let part: ExamUnit
    let store: StoreOf<StudyFeature>
    @State private var presented = false

    var body: some View {
        if part.skill == "Reading", !part.passages.isEmpty {
            Button(String(localized: "全文を見る"), systemImage: "text.book.closed") { presented = true }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("review.reading.fullText")
                .sheet(isPresented: $presented) { ReviewSourceSheet(part: part, index: nil, store: store) }
        }
    }
}

private struct ReviewSourceSheet: View {
    let part: ExamUnit
    let index: Int?
    let store: StoreOf<StudyFeature>
    @State private var selection: SelectableStudyText.Entry?
    @Environment(\.dismiss) private var dismiss
    private let localization = Bundle.main.preferredLocalizations.first ?? "en"
    private var translatesReading: Bool { Locale.Language(identifier: localization).languageCode?.identifier != "en" }
    private var question: ReadingSet.Question? { index.map { part.questions[$0] } }

    private var paragraphs: [ExamMaterialBlock] {
        ExamMaterialBlock.passages([part.directions] + part.passages + [part.audio ?? ""]).flatMap { passage in
            ExamMaterialBlock.parse(passage.text).flatMap { block -> [ExamMaterialBlock] in
                if case let .prose(value) = block {
                    let lines = value.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                    let groups = lines.split(whereSeparator: \.isEmpty)
                    // A blank line separates paragraphs even when the prose inside one wraps across lines.
                    let paragraphs = part.skill == "Reading" && groups.count > 1 ? groups.map { $0.joined(separator: "\n") } : lines.filter { !$0.isEmpty }
                    return paragraphs.map(ExamMaterialBlock.prose)
                }
                return [block]
            }
        }
    }
    private var target: Int? {
        guard let quote = question?.evidenceQuote?.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty else { return nil }
        return paragraphs.firstIndex { block in
            switch block {
            case let .prose(text): return text.localizedCaseInsensitiveContains(quote)
            case let .table(rows): return rows.contains { $0.joined(separator: " ").localizedCaseInsensitiveContains(quote) }
            }
        }
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let question {
                            Text(question.prompt).font(StudyTypography.headline)
                            ExamMaterialText(text: StudyQuestionLayout(question.instruction).formatted) { fragment, _ in Text(verbatim: fragment) }
                            ForEach(StudyQuestionLayout(question.prompt).options, id: \.label) { option in Text(option.label + ". " + option.text) }
                        }
                        ForEach(Array((part.visuals ?? []).enumerated()), id: \.offset) { _, visual in QuestionVisualView(visual: visual) }
                        let paragraphs = self.paragraphs
                        let target = self.target
                        ForEach(paragraphs.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 4) {
                                ExamMaterialText(blocks: [paragraphs[i]]) { fragment, suffix in
                                    if part.skill == "Reading" {
                                        SelectableStudyText(text: fragment, sourceID: "\(part.id)-review-\(i)\(suffix)", onSave: { entry in
                                            store.send(.saveExpression(SavedExpression(expression: entry.expression, source: part.id,
                                                sourceText: entry.sourceText, meaning: entry.meaning, paper: part, sourceID: entry.sourceID,
                                                selectionLocation: entry.utf16Range.location, selectionLength: entry.utf16Range.length)))
                                        }, onAsk: { selection = $0 })
                                    } else {
                                        Text(verbatim: fragment).textSelection(.enabled)
                                    }
                                }
                                .accessibilityIdentifier(i == target ? "review.source.target" : "review.source.paragraph")
                                if part.skill == "Reading", translatesReading, !paragraphs[i].isParagraphLabel {
                                    ParagraphTranslation(block: paragraphs[i], localization: localization, index: i)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(i == target ? StudyColors.reading : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            .id(i)
                        }
                    }.padding()
                }.task {
                    await Task.yield()
                    if let target { proxy.scrollTo(target, anchor: .top) }
                }
            }.navigationTitle(index.map { "Question \(part.firstQuestionNumber + $0)" } ?? part.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { Button(String(localized: "完了")) { dismiss() } }
        }
        .sheet(item: $selection, onDismiss: { store.send(.closeQuestion) }) { entry in
            let context = ([part.title, question?.prompt, entry.sourceText].compactMap { $0 }.joined(separator: "\n\n")
                + String(localized: "\n選択範囲: ") + entry.expression)
            TutorScreen(store: store, context: context, selectedText: entry.expression)
        }
    }
}

private struct ParagraphTranslation: View {
    let block: ExamMaterialBlock
    let localization: String
    let index: Int
    @State private var expanded = false
    @State private var translation: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                error = nil
                expanded.toggle()
            } label: {
                Label(expanded ? String(localized: "訳を隠す") : String(localized: "翻訳を表示"), systemImage: "translate")
                    .font(.footnote).frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(StudyColors.accent)
            .accessibilityIdentifier("review.reading.translate.\(index)")
            if expanded {
                if let translation {
                    ExamMaterialText(text: translation) { fragment, _ in Text(verbatim: fragment) }
                        .textSelection(.enabled).foregroundStyle(.secondary)
                } else { ProgressView().controlSize(.small) }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(StudyColors.error) }
        }
        .task(id: expanded) {
            guard expanded, translation == nil else { return }
            let source: String
            switch block {
            case .prose(let text): source = text
            case .table(let rows): source = rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
            }
            do {
                let result = try await StudyClient.translateExcerpt(source, localization: localization)
                try Task.checkCancellation()
                translation = result
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                expanded = false
            }
        }
    }
}

/// Generated papers can contain a Markdown table inside otherwise plain, selectable prose.
enum ExamMaterialBlock: Equatable {
    case prose(String)
    case table([[String]])

    var isParagraphLabel: Bool {
        guard case .prose(let text) = self else { return false }
        return text.range(of: "^[A-Z][.)]?$", options: .regularExpression) != nil
    }

    static func parse(_ text: String) -> [Self] {
        guard text.contains("|") else { return [.prose(text)] }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var blocks: [Self] = []
        var start = 0
        var index = 0
        func appendProse(until end: Int) {
            let value = lines[start..<end].joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !value.isEmpty { blocks.append(.prose(value)) }
        }
        while index + 1 < lines.count {
            let header = cells(lines[index])
            let next = cells(lines[index + 1])
            guard header.count >= 2, next.count == header.count else {
                index += 1
                continue
            }
            appendProse(until: index)
            let hasSeparator = next.allSatisfy { $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }
            var rows = hasSeparator ? [header] : [header, next]
            index += 2
            while index < lines.count {
                let row = cells(lines[index])
                guard row.count == header.count else { break }
                rows.append(row)
                index += 1
            }
            blocks.append(.table(rows))
            start = index
        }
        guard !blocks.isEmpty else { return [.prose(text)] }
        appendProse(until: lines.count)
        return blocks
    }

    // A generated passage array can split one table across consecutive strings.
    // Retain original indices so unrelated saved text selections keep their source IDs.
    static func passages(_ values: [String]) -> [(offset: Int, text: String)] {
        var result: [(offset: Int, text: String)] = []
        var previousColumns = 0
        for (index, value) in values.enumerated() {
            guard value.contains("|") else {
                result.append((index, value))
                previousColumns = 0
                continue
            }
            let trimmed = value.trimmingCharacters(in: .newlines)
            let lines = trimmed.split(whereSeparator: \.isNewline)
            let first = lines.first ?? ""
            if previousColumns >= 2, cells(String(first)).count == previousColumns {
                result[result.count - 1].text += "\n" + trimmed
            } else {
                result.append((index, trimmed))
            }
            previousColumns = cells(String(lines.last ?? "")).count
        }
        return result
    }

    private static func cells(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)[...]
        if row.first == "|" { row.removeFirst() }
        if row.last == "|" { row.removeLast() }
        return row.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }
}

struct ExamMaterialText<Cell: View>: View {
    let blocks: [ExamMaterialBlock]
    @ViewBuilder let cell: (String, String) -> Cell

    init(text: String, @ViewBuilder cell: @escaping (String, String) -> Cell) {
        self.init(blocks: ExamMaterialBlock.parse(text), cell: cell)
    }

    init(blocks: [ExamMaterialBlock], @ViewBuilder cell: @escaping (String, String) -> Cell) {
        self.blocks = blocks
        self.cell = cell
    }
    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth: CGFloat = 95

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks.indices, id: \.self) { index in
                switch blocks[index] {
                case let .prose(value):
                    cell(value, blocks.count == 1 ? "" : "-text-\(index)")
                case let .table(rows):
                    let minimumWidth = CGFloat(rows[0].count) * minimumColumnWidth
                    ViewThatFits(in: .horizontal) {
                        table(rows, index: index).frame(minWidth: minimumWidth)
                        ScrollView(.horizontal) { table(rows, index: index).frame(width: minimumWidth) }
                    }
                }
            }
        }
    }

    private func table(_ rows: [[String]], index: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { row in
                if row > 0 { Divider() }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(rows[row].indices, id: \.self) { column in
                        cell(rows[row][column], "-table-\(index)-\(row)-\(column)")
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(row == 0 ? StudyColors.reading : Color.clear)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.35)) }
    }
}
