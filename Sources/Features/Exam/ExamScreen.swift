import AVFoundation
import SwiftUI
import ComposableArchitecture

struct ExamUnit: Codable, Equatable, Identifiable, Sendable {
    let id, skill, title, directions: String
    let passages: [String]
    let questions: [ReadingSet.Question]
    let audio: String?
    let oral: [String]
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
                    Text("収録問題を使用します。Writing・Speakingは評価の観点で振り返ります。")
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
    @State private var position = 0
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
                    }.padding(StudySpacing.screenInset)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speaker.stopSpeaking(at: .immediate); audio.stop() }
        .alert("保存しました", isPresented: $saved) { Button("学習を続ける", role: .cancel) {} }
        .sheet(isPresented: $tutor, onDismiss: { store.send(.closeQuestion) }) {
            TutorScreen(store: store, context: context)
        }
        .sheet(isPresented: $recording, onDismiss: { audio.stop() }) {
            RecordingScreen(recorder: audio, title: unit.id, prompt: unit.directions)
        }
    }

    private var exercise: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(unit.id).font(.subheadline.bold()).foregroundStyle(StudyColors.accent)
            Text(showingReview ? "答えと解説" : unit.title).font(StudyTypography.title)
            if showingReview {
                reviewContent(unit)
            } else {
                selectable(unit.directions, id: "directions")
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
                        selectable("\(index+1). " + item.prompt, id: "question-\(index)")
                        TextField("解答", text: binding(index)).textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }.padding(16).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
                }
                if unit.skill == "Writing" {
                    Text("Your response").font(.headline)
                    TextEditor(text: binding(0)).frame(minHeight: 220)
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
                    if audio.hasRecording { Button("録音を聞く", systemImage: "play.fill") { audio.play() } }
                    if let error = audio.error { Text(error).foregroundStyle(StudyColors.error) }
                }
            }
            if !isMock {
                Button("この問題を保存", systemImage: "bookmark") { store.send(.savePaper(unit)); saved = true }
                Button("この問題をAIに質問") { openTutor(material(unit)) }
            }
            Button(isMock ? (position + 1 < units.count ? "次のパートへ" : "テストを終了して結果を見る") : showingReview ? (position + 1 < units.count ? "次のパートへ" : "結果を見る") : "解答・振り返りを確認") {
                if !isMock && !showingReview {
                    reviewed.insert(unit.id)
                    saveResult(unit)
                } else { advance() }
            }.buttonStyle(.borderedProminent).controlSize(.large)
            if showingReview {
                Button("このパートをもう一度") {
                    reviewed.remove(unit.id); recorded.remove(unit.id)
                    answers = answers.filter { !$0.key.hasPrefix(unit.id + "-") }
                    audio.clear()
                }
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(isMock ? "今回の模試結果" : "練習が終わりました").font(StudyTypography.title)
            ForEach(units) { part in
                VStack(alignment: .leading, spacing: 10) {
                    Text(part.id).font(.headline)
                    if !part.questions.isEmpty { Text("\(score(part)) / \(part.questions.count) 正解").font(.title2.bold()) }
                    else { Text("練習完了 · バンド判定は未実施").font(.subheadline) }
                    DisclosureGroup("答えと解説・振り返り") { reviewContent(part) }
                    if part.skill == "Writing", let response = answers[part.id + "-0"] {
                        DisclosureGroup("あなたの回答") { Text(response).textSelection(.enabled) }
                    }
                }.padding().background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
            }
            NavigationLink("学習記録を見る") { ProgressScreen(store: store).navigationTitle("学習記録") }
            Button("もう一度練習する") {
                position = 0; finished = false; answers = [:]; reviewed = []; recorded = []
                started = Date(); ended = nil; audio.clear()
            }
        }
    }

    private func reviewContent(_ part: ExamUnit) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let script = part.audio { DisclosureGroup("スクリプト") { Text(script).textSelection(.enabled) } }
            ForEach(part.questions.indices, id: \.self) { index in
                let question = part.questions[index]
                let answer = answers[part.id + "-\(index)", default: ""]
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(index + 1). " + question.answers.joined(separator: " / "),
                          systemImage: question.accepts(answer) ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.headline)
                    Text("あなたの解答: " + (answer.isEmpty ? "未回答" : answer)).font(.caption)
                    SelectableStudyText(text: question.explanation, sourceID: part.id + "-explanation-\(index)") { entry in
                        save(entry, paper: part)
                    } onAsk: { entry in openTutor(material(part) + "\n選択範囲: " + entry.expression) }
                }
            }
            if part.questions.isEmpty {
                Text("評価の観点").font(.headline)
                ForEach(part.skill == "Writing" ? ["Task response", "Coherence and cohesion", "Lexical resource", "Grammatical range and accuracy"] : ["Fluency and coherence", "Lexical resource", "Grammatical range and accuracy", "Pronunciation"], id: \.self) {
                    Text($0).bold()
                }
                Text("この観点で回答を振り返り、もう一度練習しましょう。").foregroundStyle(.secondary)
                if part.skill == "Writing" {
                    Button("AIに講評を相談") { openTutor(material(part) + "\n学習者の回答:\n" + answers[part.id + "-0", default: ""]) }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
    private func selectable(_ text: String, id: String) -> some View {
        SelectableStudyText(text: text, sourceID: unit.id + id, onSave: { save($0, paper: unit) },
            onAsk: isMock ? nil : { openTutor(material(unit) + "\n選択範囲: " + $0.expression) })
    }
    private func save(_ entry: SelectableStudyText.Entry, paper: ExamUnit) {
        store.send(.saveExpression(SavedExpression(expression: entry.expression, source: paper.id,
                                                  sourceText: entry.sourceText, paper: paper)))
        saved = true
    }
    private func openTutor(_ value: String) { context = value; tutor = true }
    private func material(_ part: ExamUnit) -> String {
        ([part.id, part.title, part.directions] + part.passages + part.questions.map { $0.prompt + "\n" + $0.explanation } + part.oral + [part.audio ?? ""]).joined(separator: "\n")
    }
    private func saveResult(_ part: ExamUnit) {
        guard !recorded.contains(part.id) else { return }
        store.send(.record(StudyResult(skill: part.skill, title: part.title, correct: score(part), total: part.questions.count, isMock: isMock)))
        recorded.insert(part.id)
    }
    private func advance() {
        speaker.stopSpeaking(at: .immediate); audio.stop()
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
            file = url; recorder = next; isRecording = true; hasRecording = false; elapsed = 0
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
    func clear() {
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
    @State private var error: String?
    @State private var attempt = 0
    @State private var settings = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if generated.count == templates.count && !generated.isEmpty {
                ExamScreen(units: generated, store: store, isMock: isMock)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    Text("問題を生成中…").font(StudyTypography.title)
                    if let error {
                        Text(error).foregroundStyle(StudyColors.error)
                        Button("もう一度生成") { self.error = nil; attempt += 1 }
                        Button("ChatGPTの接続設定") { settings = true }
                    } else { ProgressView("新しい問題を準備しています。\(generated.count) / \(templates.count)") }
                    Button("キャンセルして戻る") { dismiss() }
                }.padding(20)
            }
        }
        .task(id: attempt) {
            guard !templates.isEmpty else { error = "教材がありません。"; return }
            do {
                for template in templates.dropFirst(generated.count) {
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
