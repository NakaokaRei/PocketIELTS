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
    var firstQuestionNumber: Int {
        if skill == "Reading" { return id.contains("Section 3") ? 27 : id.contains("Section 2") ? 14 : 1 }
        if skill == "Listening", let part = (1...4).first(where: { id.contains("Part \($0)") }) { return (part - 1) * 10 + 1 }
        return 1
    }
    static func load() throws -> [ExamUnit] {
        guard let url = Bundle.main.url(forResource: "GeneralTraining", withExtension: "json") else {
            throw StudyError.message("教材が見つかりません。")
        }
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
    }
}

struct MockIntroScreen: View {
    let units: [ExamUnit]
    let store: StoreOf<StudyFeature>
    @State private var started = false
    @State private var generate = false
    private var ordered: [ExamUnit] {
        ["Listening", "Reading", "Writing", "Speaking"].flatMap { skill in units.filter { $0.skill == skill } }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("模擬テスト").font(.system(.largeTitle, design: .rounded, weight: .black))
                VStack(alignment: .leading, spacing: 20) {
                    Text("Full mock").font(.largeTitle.bold())
                    Text("時間を計って4技能に挑戦。\n解説はテスト終了後に確認できます。")
                    Text(generate ? "新しい問題を生成します。" : "収録問題を使用します。Writing・Speakingは終了後にAI講評を確認できます。")
                        .font(.footnote)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudyColors.reading, in: RoundedRectangle(cornerRadius: 20))
                ForEach(Array(["Listening", "Reading", "Writing", "Speaking"].enumerated()), id: \.offset) { index, skill in
                    Text(String(format: "%02d     %@", index + 1, skill)).font(.title2.bold()).padding(.vertical, 8)
                }
                Toggle("新しい問題を生成する", isOn: $generate)
                Button("模試を始める") { started = true }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(units.isEmpty)
            }.padding(20)
        }.navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $started) {
                IELTSPracticeSession(title: "模擬テスト", finish: {}) {
                    if generate { GeneratedExamScreen(templates: ordered, store: store, isMock: true) }
                    else { ExamScreen(units: ordered, store: store, isMock: true) }
                }
            }
    }
}

struct ExamScreen: View {
    let units: [ExamUnit]
    let store: StoreOf<StudyFeature>
    var isMock = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.studyNavigation) private var navigation
    @State private var confirmEnd = false
    @FocusState private var answerFocused: Bool
    @State private var position = 0
    @State private var attemptID = UUID()
    @State private var resultIDs: [String: UUID] = [:]
    @State private var assessments: [String: PracticeAssessment] = [:]
    @State private var assessmentErrors: [String: String] = [:]
    @State private var evaluatingID: String?
    @State private var recordingFiles: [String: String] = [:]
    @State private var finished = false
    @State private var answers: [String: String] = [:]
    @State private var reviewed: Set<String> = []
    @State private var recorded: Set<String> = []
    @State private var speaker = AVSpeechSynthesizer()
    @State private var started = Date()
    @State private var ended: Date?
    @State private var tutor = false
    @State private var context = ""
    @State private var saved = false
    @State private var recording = false
    @State private var settings = false
    @State private var audio = SpeakingRecorder()
    private var unit: ExamUnit { units[position] }
    private var showingReview: Bool { reviewed.contains(unit.id) && !isMock }

    var body: some View {
        Group {
            if units.isEmpty {
                ContentUnavailableView("教材がありません", systemImage: "book")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: StudySpacing.section) {
                        if isMock {
                            HStack {
                                Text("模擬テスト").bold(); Spacer()
                                if let ended { Text(duration(ended.timeIntervalSince(started))).monospacedDigit() }
                                else { Text(started, style: .timer).monospacedDigit() }
                            }.foregroundStyle(StudyColors.accent)
                        }
                        if finished { results } else { exercise }
                    }.padding(StudySpacing.screenInset).frame(maxWidth: 800).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .foregroundStyle(StudyColors.ink)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("入力を完了") {
                    answerFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            if !isMock { ToolbarItem(placement: .topBarTrailing) { Button("終了", systemImage: "xmark") { confirmEnd = true }.labelStyle(.iconOnly).accessibilityIdentifier("practice.finish") } }
        }
        .confirmationDialog("練習を終了しますか？", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("練習を終了") { finished = true; ended = Date() }
            Button("続ける", role: .cancel) {}
        } message: { Text("採点済みの結果と保存した表現は残ります。") }
        .onDisappear { speaker.stopSpeaking(at: .immediate); audio.stop(); audio.cancelTranscription() }
        .onChange(of: audio.transcript) { _, text in
            if unit.skill == "Speaking", !text.isEmpty { answers[unit.id + "-0"] = text }
        }
        .task(id: evaluatingID) {
            guard let id = evaluatingID, let part = units.first(where: { $0.id == id }) else { return }
            do {
                let result = try await StudyClient.assess(part, response: answers[id + "-0", default: ""])
                try Task.checkCancellation()
                assessments[id] = result
                if let resultID = resultIDs[id] { store.send(.updateAssessment(resultID, result)) }
            } catch { if !Task.isCancelled { assessmentErrors[id] = error.localizedDescription } }
            if evaluatingID == id { evaluatingID = nil }
        }
        .alert("保存しました", isPresented: $saved) { Button("学習を続ける", role: .cancel) {} }
        .sheet(isPresented: $tutor, onDismiss: { store.send(.closeQuestion) }) {
            TutorScreen(store: store, context: context)
        }
        .sheet(isPresented: $settings) { SettingsScreen(store: store.scope(state: \.settings, action: \.settings)) }
        .sheet(isPresented: $recording, onDismiss: { audio.stop() }) {
            RecordingScreen(recorder: audio, title: unit.id, prompt: ([unit.title] + unit.passages + unit.oral).joined(separator: "\n\n"))
        }
    }

    private var exercise: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(unit.id).font(.subheadline.bold()).foregroundStyle(StudyColors.accent)
            Text(showingReview ? "答えと解説" : unit.title).font(showingReview ? StudyTypography.japaneseTitle(30) : .system(size: 24, weight: .bold))
            if showingReview {
                reviewContent(unit)
            } else {
                if !unit.directions.isEmpty { selectable(unit.directions, id: "directions") }
                ForEach(Array(unit.passages.enumerated()), id: \.offset) { index, text in selectable(text, id: "passage-\(index)") }
                if let script = unit.audio {
                    HStack {
                        Button("音声を再生", systemImage: "headphones") { speak(script) }
                        Button("停止", systemImage: "stop.fill") { speaker.stopSpeaking(at: .immediate) }
                    }
                }
                ForEach(unit.questions.indices, id: \.self) { index in
                    let item = unit.questions[index]
                    VStack(alignment: .leading, spacing: 12) {
                        if index == 0 || unit.questions[index-1].instruction != item.instruction {
                            selectable(item.instruction, id: "instruction-\(index)")
                        }
                        selectable("\(unit.firstQuestionNumber + index). " + item.prompt, id: "question-\(index)")
                        if !item.choices.isEmpty {
                            Picker("解答", selection: binding(index)) {
                                Text("選択してください").tag("")
                                ForEach(item.choices, id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.menu)
                        } else {
                            TextField("解答", text: binding(index)).textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                    }.padding(16).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
                }
                if unit.skill == "Writing" {
                    Text("Your response").font(.headline)
                    TextEditor(text: binding(0)).focused($answerFocused).keyboardType(.asciiCapable).frame(minHeight: 220)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                        .accessibilityLabel("英作文の回答")
                    Text("\(binding(0).wrappedValue.split(whereSeparator: \.isWhitespace).count) words").font(.caption)
                }
                ForEach(unit.oral.indices, id: \.self) { index in
                    selectable(unit.oral[index], id: "oral-\(index)")
                    Button("質問を聞く", systemImage: "speaker.wave.2") { speak(unit.oral[index]) }
                }
                if unit.skill == "Speaking" {
                    Button("マイクで回答", systemImage: "mic.fill") {
                        speaker.stopSpeaking(at: .immediate)
                        recording = true
                    }
                    if audio.hasRecording {
                        HStack {
                            Button("録音を聞く", systemImage: "play.fill") { audio.play() }
                            Button("文字起こし", systemImage: "text.bubble") { Task { await audio.transcribe() } }
                                .disabled(audio.transcribing)
                        }
                    }
                    if audio.transcribing { ProgressView("端末内で文字起こし中…") }
                    Text("回答の文字起こし").font(.headline)
                    TextEditor(text: binding(0)).focused($answerFocused).keyboardType(.asciiCapable).frame(minHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                        .accessibilityLabel("スピーキングの文字起こし")
                    Text("文字起こしを確認・修正してから講評へ進めます。認識できない場合は回答を入力してください。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = audio.error { Text(error).foregroundStyle(StudyColors.error) }
                }
            }
            if !isMock {
                Button("この問題を保存", systemImage: "bookmark") { store.send(.savePaper(unit)); saved = true }
                Button("この問題をAIに質問") { openTutor(material(unit)) }
            }
            Button(isMock ? (position + 1 < units.count ? "次のパートへ" : "テストを終了して結果を見る") : showingReview ? (position + 1 < units.count ? "次のパートへ" : "結果を見る") : "解答・振り返りを確認") {
                answerFocused = false
                if !isMock && !showingReview {
                    reviewed.insert(unit.id)
                    saveResult(unit)
                } else { advance() }
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(audio.transcribing || audio.isRecording)
                .accessibilityIdentifier("practice.review")
            if showingReview {
                Button("このパートをもう一度") {
                    reviewed.remove(unit.id); recorded.remove(unit.id)
                    answers = answers.filter { !$0.key.hasPrefix(unit.id + "-") }
                    audio.clear(); assessments[unit.id] = nil; assessmentErrors[unit.id] = nil
                    resultIDs[unit.id] = nil; recordingFiles[unit.id] = nil
                }.accessibilityIdentifier("practice.retry")
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(isMock ? "今回の模試結果" : "練習を終了しました").font(StudyTypography.japaneseTitle(30))
            if isMock {
                let records = store.records.filter { $0.attemptID == attemptID }
                VStack(alignment: .leading, spacing: 16) {
                    Text("推定 IELTS Overall").font(.headline)
                    Text(StudyBand.label(StudyBand.overall(records)) + "  /  CEFR " + StudyBand.cefr(StudyBand.overall(records))).font(.title2.bold())
                    ForEach(["Listening", "Reading", "Writing", "Speaking"], id: \.self) { skill in
                        HStack { Text(skill); Spacer(); Text(StudyBand.label(StudyBand.skill(skill, records: records))) }
                    }
                    Text("Writing・Speakingの講評後に全体の学習用推定を表示します。発音の評価は含みません。")
                        .font(.footnote)
                }.padding(20).foregroundStyle(.white).background(StudyColors.levelCard, in: RoundedRectangle(cornerRadius: 20))
            }
            ForEach(units.filter { recorded.contains($0.id) }) { part in
                VStack(alignment: .leading, spacing: 10) {
                    Text(part.id).font(.headline)
                    if !part.questions.isEmpty { Text("\(score(part)) / \(part.questions.count) 正解").font(.title2.bold()) }
                    else { Text("学習用推定 " + StudyBand.label(assessments[part.id]?.estimatedBand)).font(.subheadline) }
                    DisclosureGroup("答えと解説・振り返り") { reviewContent(part) }
                    if part.skill == "Writing", let response = answers[part.id + "-0"] {
                        DisclosureGroup("あなたの回答") { Text(response).textSelection(.enabled) }
                    }
                }.padding().background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
            }
            Text("技能別の推移は学習記録で確認できます。").foregroundStyle(.secondary)
            Button("学習記録を見る") { dismiss(); navigation.progress() }.buttonStyle(.borderedProminent)
            Button("ホームに戻る") { dismiss(); navigation.home() }
            Button("もう一度練習する") {
                position = 0; finished = false; answers = [:]; reviewed = []; recorded = []; evaluatingID = nil
                started = Date(); ended = nil; audio.clear(); attemptID = UUID(); resultIDs = [:]; assessments = [:]; assessmentErrors = [:]; recordingFiles = [:]
            }
        }
    }

    private func reviewContent(_ part: ExamUnit) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let script = part.audio { DisclosureGroup("スクリプト") { SelectableStudyText(text: script, sourceID: part.id + "-script", onSave: { save($0, paper: part) }, onSavePaper: { store.send(.savePaper(part)) }) } }
            ForEach(part.questions.indices, id: \.self) { index in
                let question = part.questions[index]
                let answer = answers[part.id + "-\(index)", default: ""]
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(part.firstQuestionNumber + index). " + question.answers.joined(separator: " / "),
                          systemImage: question.accepts(answer) ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.headline)
                    Text("あなたの解答: " + (answer.isEmpty ? "未回答" : answer)).font(.caption)
                    SelectableStudyText(text: question.explanation, sourceID: part.id + "-explanation-\(index)") { entry in
                        save(entry, paper: part)
                    } onAsk: { entry in openTutor(material(part) + "\n選択範囲: " + entry.expression) }
                }
            }
            if part.questions.isEmpty {
                if let file = recordingFiles[part.id] {
                    Button("保存した録音を聞く", systemImage: "play.circle") { audio.playArchived(file) }
                }
                if let response = answers[part.id + "-0"], !response.isEmpty {
                    DisclosureGroup("あなたの回答") { Text(response).textSelection(.enabled) }
                }
                if let assessment = assessments[part.id] {
                    AssessmentContent(assessment: assessment, paper: part, store: store)
                } else {
                    Text("評価の観点").font(.headline)
                    ForEach(part.skill == "Writing" ? ["Task response", "Coherence and cohesion", "Lexical resource", "Grammatical range and accuracy"] : ["Fluency and coherence", "Lexical resource", "Grammatical range and accuracy", "Pronunciation"], id: \.self) { Text($0).bold() }
                }
                if let error = assessmentErrors[part.id] { Text(error).foregroundStyle(StudyColors.error) }
                if !store.settings.canPractice { Button("ChatGPTの接続設定") { settings = true } }
                if evaluatingID == part.id { ProgressView("回答を講評中…") }
                Button(assessments[part.id] == nil ? "AIの講評を見る" : "講評を更新") {
                    assessmentErrors[part.id] = nil; evaluatingID = part.id
                }.buttonStyle(.borderedProminent)
                    .disabled(evaluatingID != nil || answers[part.id + "-0", default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if answers[part.id + "-0", default: ""].isEmpty {
                    Text("回答がありません。このパートをもう一度練習すると講評を受けられます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("AIによる学習用の推定です。Speakingは文字起こしを使うため、発音・音声の流暢さは評価に含みません。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("AIに追加で質問") { openTutor(material(part) + "\n学習者の回答:\n" + answers[part.id + "-0", default: ""]) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
    private func selectable(_ text: String, id: String) -> some View {
        SelectableStudyText(text: text, sourceID: unit.id + id, onSave: { save($0, paper: unit) },
            onAsk: isMock ? nil : { openTutor(material(unit) + "\n選択範囲: " + $0.expression) },
            onSavePaper: { store.send(.savePaper(unit)) }, allowsAI: !isMock)
    }
    private func save(_ entry: SelectableStudyText.Entry, paper: ExamUnit) {
        store.send(.saveExpression(SavedExpression(expression: entry.expression, source: paper.id,
                                                  sourceText: entry.sourceText, meaning: entry.meaning, paper: paper, sourceID: entry.sourceID, selectionLocation: entry.utf16Range.location, selectionLength: entry.utf16Range.length)))
    }
    private func openTutor(_ value: String) { context = value; tutor = true }
    private func material(_ part: ExamUnit) -> String {
        ([part.id, part.title, part.directions] + part.passages + part.questions.map { $0.prompt + "\n" + $0.explanation } + part.oral + [part.audio ?? ""]).joined(separator: "\n")
    }
    private func saveResult(_ part: ExamUnit) {
        guard !recorded.contains(part.id) else { return }
        let id = UUID()
        resultIDs[part.id] = id
        if part.skill == "Speaking", part.id == unit.id, audio.hasRecording, recordingFiles[part.id] == nil {
            do { recordingFiles[part.id] = try audio.archive() }
            catch { assessmentErrors[part.id] = "録音の保存に失敗しました: " + error.localizedDescription }
        }
        store.send(.record(StudyResult(id: id, skill: part.skill, title: part.title,
            correct: score(part), total: part.questions.count, isMock: isMock,
            response: answers[part.id + "-0"], assessment: assessments[part.id],
            recordingFile: recordingFiles[part.id], paper: part, attemptID: attemptID)))
        recorded.insert(part.id)
    }
    private func advance() {
        speaker.stopSpeaking(at: .immediate); audio.stop()
        // Preserve each speaking recording before moving to a new part.
        if unit.skill == "Speaking", audio.hasRecording, recordingFiles[unit.id] == nil {
            do { recordingFiles[unit.id] = try audio.archive() }
            catch { assessmentErrors[unit.id] = error.localizedDescription }
        }
        if position + 1 < units.count { position += 1; audio.clear() }
        else {
            units.forEach(saveResult)
            ended = Date(); finished = true
        }
    }
    private func binding(_ index: Int) -> Binding<String> {
        let key = unit.id + "-\(index)"
        return Binding(get: { answers[key, default: ""] }, set: { answers[key] = $0 })
    }
    private func score(_ part: ExamUnit) -> Int {
        part.questions.enumerated().filter { $0.element.accepts(answers[part.id + "-\($0.offset)", default: ""]) }.count
    }
    private func speak(_ text: String) {
        audio.stop(); speaker.stopSpeaking(at: .immediate)
        let speech = AVSpeechUtterance(string: text)
        speech.voice = AVSpeechSynthesisVoice(language: "en-GB")
        speaker.speak(speech)
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
        guard allowed else { error = "設定アプリでPocket IELTSのマイク使用を許可してください。"; return }
        do {
            stop()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let next = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            next.isMeteringEnabled = true
            guard next.record() else { throw StudyError.message("録音を開始できませんでした。") }
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
        if isRecording { elapsed = recorder?.currentTime ?? elapsed; recorder?.stop(); hasRecording = elapsed > 0 }
        isRecording = false; level = 0; player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
            error = "設定で音声認識を許可するか、回答をテキストで入力してください。"; return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            transcribing = false; recognitionID = nil
            error = "この端末では英語の端末内文字起こしを利用できません。回答をテキストで入力してください。"; return
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
                    if let failure, self.transcript.isEmpty { self.error = "文字起こしに失敗しました。回答を入力できます。\n" + failure }
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
                Text(title).font(.title2.bold())
                ScrollView { Text(prompt).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading) }
                Text(recorder.isRecording ? "録音中" : "録音停止").bold().foregroundStyle(StudyColors.accent)
                TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                    HStack(spacing: 5) {
                        ForEach(0..<32, id: \.self) { index in
                            Capsule().fill(StudyColors.accent)
                                .frame(height: max(4, recorder.level * CGFloat(25 + (index * 17 % 55))))
                        }
                    }.frame(height: 98).padding(.horizontal, 14)
                        .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
                        .onChange(of: timeline.date) { _, _ in recorder.update() }
                        .accessibilityLabel("録音レベル")
                }
                Text(String(format: "%02d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60)).monospacedDigit()
                if let error = recorder.error { Text(error).foregroundStyle(StudyColors.error) }
                Button("録音を停止して課題に戻る") { recorder.stop(); dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(20)
                .toolbar { Button("閉じる") { recorder.stop(); dismiss() } }
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
    @State private var error: String?
    @State private var attempt = 0
    @State private var settings = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if generated.count == templates.count && !generated.isEmpty {
                ExamScreen(units: generated, store: store, isMock: isMock)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if let error {
                                Label("生成を完了できませんでした", systemImage: "book.closed").font(.title2.bold())
                                Text(error).foregroundStyle(StudyColors.error)
                                Button("もう一度生成") { self.error = nil; attempt += 1 }
                                Button("ChatGPTの接続設定") { settings = true }
                            } else {
                                GenerationLoadingView(completed: generated.count, total: templates.count,
                                                      started: generationStarted)
                            }
                            Button("キャンセルして戻る") { dismiss() }
                        }.padding(24).frame(maxWidth: 480)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                }
            }
        }
        .task(id: attempt) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ProcessInfo.processInfo.arguments.contains("--ui-generation-preview") {
                try? await Task.sleep(for: .seconds(120))
                return
            }
            #endif
            guard !templates.isEmpty else { error = "教材がありません。"; return }
            do {
                for template in templates.dropFirst(generated.count) {
                    generationStarted = Date()
                    let unit = try await StudyClient.generateUnit(like: template)
                    try Task.checkCancellation()
                    generated.append(unit)
                }
            } catch is CancellationError {
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
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
            Text("学習用推定 " + StudyBand.label(assessment.estimatedBand)).font(StudyTypography.roundedTitle(28))
            if assessment.isPartial { Text("発音を除く、回答内容の推定").font(.caption).foregroundStyle(.secondary) }
            Text(assessment.summary)
            ForEach(assessment.criteria, id: \.name) { criterion in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(criterion.name).bold(); Spacer(); Text(criterion.band.map { String(format: "%.1f", $0) } ?? "未評価") }
                    Text(criterion.feedback).font(.subheadline)
                }.padding(16).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
            }
            Text("改善例").font(.headline)
            SelectableStudyText(text: assessment.improvedResponse, sourceID: paper.id + "-improved", onSave: { entry in
                store.send(.saveExpression(SavedExpression(expression: entry.expression, source: paper.id,
                    sourceText: entry.sourceText, meaning: entry.meaning, paper: paper,
                    sourceID: entry.sourceID, selectionLocation: entry.utf16Range.location, selectionLength: entry.utf16Range.length)))
            }, onSavePaper: { store.send(.savePaper(paper)) })
        }
    }
}

/// An explicitly estimated indicator: only validated units count as completed.
private struct GenerationLoadingView: View {
    let completed: Int
    let total: Int
    let started: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(started))
            let estimate = (Double(completed) + min(0.9, 0.9 * (1 - exp(-elapsed / 45)))) / Double(max(1, total))
            VStack(spacing: 24) {
                LoadingBookMascot()
                VStack(spacing: 10) {
                    Text("あなただけの問題を準備中").font(StudyTypography.roundedTitle(24))
                    Text("小さな一歩が、大きな自信に。").font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    HStack {
                        Text("進捗の目安").font(.subheadline)
                        Spacer()
                        Text("約 \(Int(estimate * 100))% ").monospacedDigit().bold()
                    }
                    ProgressView(value: estimate).tint(StudyColors.accent)
                    Text("生成・確認済み \(completed) / \(total) セクション")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(elapsed > 90 ? "もう少し時間がかかっています。完了までこの画面でお待ちください。" : "本文・設問・解説を作成しています。表示は時間に基づく目安です。")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
