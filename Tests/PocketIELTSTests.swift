import AVFoundation
import XCTest
import UIKit
import ComposableArchitecture
@testable import PocketIELTS

@MainActor
final class PocketIELTSTests: XCTestCase {
    func testLoopbackAuthenticationSurvivesInvalidRequestAndCompletes() async throws {
        let opened = expectation(description: "Browser opens only after listener is ready")
        var redirect: URL?
        let browser = SignInBrowser(presentForTesting: { redirect = $0; opened.fulfill() })
        let task = Task { try await browser.authorize(state: "test-state") { $0 } }
        defer { task.cancel() }
        await fulfillment(of: [opened], timeout: 5)
        let base = try XCTUnwrap(redirect)
        XCTAssertEqual(base.host, "127.0.0.1")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        // A stale browser tab cannot consume the active sign-in attempt.
        let invalid = URL(string: base.absoluteString + "?state=wrong&code=fixture")!
        _ = try? await session.data(from: invalid)
        let valid = URL(string: base.absoluteString + "?state=test-state&code=fixture")!
        let (data, response) = try await session.data(from: valid)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Pocket IELTS"))
        let (callback, returnedRedirect) = try await task.value
        XCTAssertEqual(callback, valid)
        XCTAssertEqual(returnedRedirect, base)
    }

    func testOfflineLibraryHasAllPartsAndIndependentVocabulary() throws {
        let units = try ExamUnit.load()
        XCTAssertEqual(units.count, 12)
        XCTAssertEqual(units.filter { $0.skill == "Reading" }.flatMap(\.questions).count, 40)
        XCTAssertEqual(units.filter { $0.skill == "Listening" }.flatMap(\.questions).count, 40)
        XCTAssertEqual(StarterWord.all.count, 1000)
        XCTAssertEqual(Set(StarterWord.all.map(\.id)).count, 1000)
        for level in 0..<3 { XCTAssertGreaterThanOrEqual(StarterWord.all.filter { $0.level == level }.count, 90) }
        XCTAssertTrue(StarterWord.all.allSatisfy { !$0.definition.isEmpty })
    }

    func testGeneralTrainingCoverageAndWaitingMeanings() throws {
        for topic in StarterWord.topics {
            XCTAssertEqual(StarterWord.all.filter { $0.topic == topic }.count, 100)
        }
        XCTAssertTrue(StarterWord.all.allSatisfy { !$0.example.isEmpty && $0.example.localizedCaseInsensitiveContains($0.expression) })
        let saved = SavedExpression(expression: "accommodation", source: "Reading", sourceText: "Find accommodation near work.")
        let deck = VocabularyCard.waitingDeck([saved])
        XCTAssertEqual(deck.count, 1000)
        XCTAssertEqual(deck.first?.word, "accommodation")
        XCTAssertFalse(try XCTUnwrap(deck.first).meaning.isEmpty)
        XCTAssertTrue(try XCTUnwrap(deck.first).personal)
        let unknown = SavedExpression(expression: "xyz unknown", source: "manual", sourceText: "")
        let withUnknown = VocabularyCard.waitingDeck([unknown])
        XCTAssertEqual(withUnknown.first?.word, "xyz unknown")
        XCTAssertTrue(try XCTUnwrap(withUnknown.first).personal)
        XCTAssertTrue(try XCTUnwrap(withUnknown.first).meaning.isEmpty)
        XCTAssertEqual(withUnknown.count, 1001)
        XCTAssertTrue(withUnknown.dropFirst().allSatisfy { !$0.meaning.isEmpty && !$0.personal })
        XCTAssertTrue(deck.dropFirst().allSatisfy { !$0.personal && $0.word.lowercased() != "accommodation" })
        XCTAssertTrue(VocabularyCard.waitingDeck([]).allSatisfy { !$0.personal })
        XCTAssertNil(VocabularyCard(SavedExpression(expression: "  ", source: "manual", sourceText: "")))
    }

    func testWaitingDeckShowsAllPersonalWordsBeforeUniqueBundledWords() {
        let saved = ["available", "ventilation", "AVAILABLE", "my own phrase", "  "].map {
            SavedExpression(expression: $0, source: "manual", sourceText: "")
        }
        // Assert ordering and membership independently of each random shuffle.
        for _ in 0..<10 {
            let deck = VocabularyCard.waitingDeck(saved)
            XCTAssertEqual(Set(deck.prefix(3).map { $0.word.lowercased() }), ["available", "ventilation", "my own phrase"])
            XCTAssertTrue(deck.prefix(3).allSatisfy(\.personal))
            XCTAssertTrue(deck.dropFirst(3).allSatisfy { !$0.personal })
            XCTAssertEqual(Set(deck.map { $0.word.lowercased() }).count, deck.count)
            XCTAssertEqual(deck.count, 1001)
            for pair in zip(deck, deck.dropFirst()) { XCTAssertNotEqual(pair.0.word.lowercased(), pair.1.word.lowercased()) }
        }
    }

    func testPronunciationUsesEnglishAndStopsCleanly() {
        let utterance = WordPronouncer.utterance(for: "accommodation")
        XCTAssertEqual(utterance.speechString, "accommodation")
        XCTAssertTrue(utterance.voice?.language.hasPrefix("en") == true)
        XCTAssertLessThan(utterance.rate, AVSpeechUtteranceDefaultSpeechRate)
        let pronouncer = WordPronouncer()
        pronouncer.stop()
        XCTAssertNil(pronouncer.activeWord)
    }

    func testSpeakingReceivedAudioActuallyRendersAndInterruptionClearsIt() throws {
        // Exercise the real AVAudioEngine graph offline: no microphone, key, or API call.
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false))
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        try engine.start()
        let session = SpeakingConversation(phase: .listening, engine: engine, output: player)
        defer { session.stop() }
        var pcm = Data()
        for i in 0..<12000 {
            var sample = Int16(sin(Double(i) * 2 * .pi * 440 / 24000) * 16000).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        session.handle(["type": "response.created"])
        session.handle(["type": "response.output_audio.delta", "item_id": "audio", "delta": pcm.base64EncodedString()])
        XCTAssertTrue(player.isPlaying)
        let rendered = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        var peak: Float = 0
        for _ in 0..<4 {
            XCTAssertEqual(try engine.renderOffline(1024, to: rendered), .success)
            for i in 0..<Int(rendered.frameLength) { peak = max(peak, abs(rendered.floatChannelData![0][i])) }
        }
        XCTAssertGreaterThan(peak, 0.1, "Received PCM must produce non-silent output, not just a speaking label")
        session.handle(["type": "input_audio_buffer.speech_started"])
        XCTAssertFalse(player.isPlaying)
        session.handle(["type": "response.output_audio.delta", "item_id": "audio", "delta": pcm.base64EncodedString()])
        XCTAssertFalse(player.isPlaying, "Late audio from the interrupted response must stay discarded")
        session.stop()
        XCTAssertFalse(engine.isRunning)
    }

    func testSpeakingPermissionDialogDoesNotCancelStartup() {
        let session = SpeakingConversation(phase: .connecting)
        session.sceneChanged(.inactive)
        session.audioInterrupted(.ended)
        session.sceneChanged(.active)
        XCTAssertEqual(session.phase, .connecting)
        XCTAssertTrue(session.active)
        session.sceneChanged(.background)
        XCTAssertEqual(session.phase, .ended)
        session.sceneChanged(.active)
        XCTAssertFalse(session.active)
    }

    func testSpeakingOnlyStopsForBeginningOfAnAudioInterruption() {
        let session = SpeakingConversation(phase: .listening)
        session.audioInterrupted(.ended)
        XCTAssertTrue(session.active)
        session.audioInterrupted(.began)
        XCTAssertFalse(session.active)
        session.audioInterrupted(.ended)
        XCTAssertFalse(session.active)
    }

    func testSpeakingAPIErrorMessagesIdentifyCauseWithoutEchoingSecrets() {
        let generic = SpeakingProtocol.errorDescription([:])
        for code in ["invalid_api_key", "insufficient_quota", "model_not_found"] {
            let message = SpeakingProtocol.errorDescription(["code": code, "message": "secret"])
            XCTAssertNotEqual(message, generic)
            XCTAssertFalse(message.contains("secret"))
        }
        XCTAssertNotEqual(SpeakingProtocol.errorDescription(["param": "session.audio.input.transcription.model"]), generic)
    }

    func testSpeakingDefaultsToMiniAndBuildsSelectedModelSession() throws {
        XCTAssertEqual(SpeakingModel.resolve(nil), .mini)
        XCTAssertEqual(SpeakingModel.resolve("unknown"), .mini)
        XCTAssertEqual(SpeakingModel.resolve(SpeakingModel.standard.rawValue), .standard)
        let unit = try XCTUnwrap(ExamUnit.load().first { $0.skill == "Speaking" })
        for model in SpeakingModel.allCases {
            let request = SpeakingProtocol.request(model: model, key: "test-only")
            XCTAssertTrue(request.url!.absoluteString.contains(model.rawValue))
            let event = SpeakingProtocol.configuration(unit: unit, model: model)
            let session = try XCTUnwrap(event["session"] as? [String: Any])
            XCTAssertEqual(session["model"] as? String, model.rawValue)
            let audio = try XCTUnwrap(session["audio"] as? [String: Any])
            let input = try XCTUnwrap(audio["input"] as? [String: Any])
            let vad = try XCTUnwrap(input["turn_detection"] as? [String: Any])
            XCTAssertEqual(vad["type"] as? String, "semantic_vad")
            XCTAssertEqual(vad["interrupt_response"] as? Bool, true)
            XCTAssertNoThrow(try SpeakingProtocol.encode(event))
        }
    }

    func testSpeakingTranscriptUsesCommittedOrderAndOnlyCandidateAnswers() {
        let session = SpeakingConversation(phase: .listening)
        session.handle(["type": "input_audio_buffer.committed", "item_id": "first"])
        session.handle(["type": "input_audio_buffer.committed", "item_id": "second"])
        session.handle(["type": "conversation.item.input_audio_transcription.completed", "item_id": "second", "transcript": "Second answer"])
        session.handle(["type": "response.output_audio_transcript.done", "item_id": "examiner", "transcript": "Where do you live?"])
        session.handle(["type": "conversation.item.input_audio_transcription.completed", "item_id": "first", "transcript": "First answer"])
        XCTAssertEqual(session.userTranscript, "First answer\n\nSecond answer")
        session.handle(["type": "conversation.item.input_audio_transcription.completed", "item_id": "first", "transcript": "Corrected answer"])
        XCTAssertEqual(session.turns.count, 3)
        XCTAssertEqual(session.userTranscript, "Corrected answer\n\nSecond answer")
        session.stop()
        session.handle(["type": "conversation.item.input_audio_transcription.completed", "item_id": "late", "transcript": "Ignored"])
        XCTAssertEqual(session.phase, .ended)
        XCTAssertEqual(session.turns.count, 3)
        session.stop() // Dismissal and interruption may both stop a session.
    }

    func testSpeakingErrorsEndSessionWithoutExposingServerPayload() {
        let session = SpeakingConversation(phase: .thinking)
        session.handle(["type": "error", "error": ["message": "sensitive server payload"]])
        XCTAssertFalse(session.active)
        XCTAssertNotNil(session.error)
        XCTAssertFalse(session.error!.contains("sensitive"))
        XCTAssertThrowsError(try SpeakingProtocol.decode(.string("[]")))
    }

    func testAnswerAcceptsAlternativeSpellingAndWhitespace() {
        let question = ReadingSet.Question(instruction: "Write two words.", prompt: "Where?",
                                          answers: ["town centre", "town center"], explanation: "Location")
        XCTAssertTrue(question.accepts("  TOWN   Center\n"))
        XCTAssertFalse(question.accepts("town"))
        XCTAssertFalse(question.accepts(""))
    }

    func testChatGPTOnlyPracticeGate() {
        var state = SettingsFeature.State()
        XCTAssertFalse(state.canPractice)
        state.account.active = "profile"
        XCTAssertTrue(state.canPractice)
        state.account.active = nil
        XCTAssertFalse(state.canPractice)
    }

    func testAccountRefresh() async {
        let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() }
            withDependencies: { $0[AccountClient.self] = AccountClient(status: { .init(active: "profile") }, signIn: { _ in }, signOut: {}) }
        await store.send(.refreshAccount)
        await store.receive(\.accountChanged) { $0.account.active = "profile" }
    }

    func testReadingSessionLoadsGradesOnceAndFinishes() async {
        let question = ReadingSet.Question(instruction: "Write one word.", prompt: "When?",
                                           answers: ["Monday"], explanation: "Opening day")
        let paper = ReadingSet(title: "Opening hours", passages: ["We open on Monday."], questions: [question])
        let store = TestStore(initialState: StudyFeature.State()) {
            StudyFeature()
        } withDependencies: {
            $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0[StudyClient.self].generate = { section in
                XCTAssertEqual(section, 2)
                return paper
            }
        }
        await store.send(.start(2)) {
            $0.section = 2
            $0.loading = true
        }
        await store.receive(\.loaded) {
            $0.loading = false
            $0.session = paper
        }
        await store.send(.answer(0, "monday")) { $0.answers = [0: "monday"] }
        let history = try! StudyPersistence.encode(["Section 2 · Opening hours · 1/1"])
        await store.send(.review) {
            $0.reviewed = true
            $0.$history.withLock { $0 = history }
            let record = StudyResult(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: Date(timeIntervalSince1970: 0),
                                     skill: "Reading", title: "Opening hours", correct: 1, total: 1,
                                     paper: ExamUnit(id: "Reading / Section 2 · Opening hours", skill: "Reading", title: paper.title,
                                                     directions: "", passages: paper.passages, questions: paper.questions, audio: nil, oral: []),
                                     questionAnswers: ["monday"])
            $0.$resultData.withLock { $0 = try! StudyPersistence.encode([record]) }
        }
        await store.send(.review)
        await store.send(.answer(0, "Tuesday"))
        await store.send(.finish) {
            $0.reviewed = false
            $0.session = nil
            $0.answers = [:]
        }
    }
    func testSavedPaperAndExpressionKeepSource() async throws {
        let paper = ExamUnit(id: "Reading / Section 1", skill: "Reading", title: "Library", directions: "Read",
                             passages: ["Return books beside the entrance."], questions: [], audio: nil, oral: [])
        let entry = SavedExpression(expression: "beside", source: paper.id, sourceText: paper.passages[0], paper: paper)
        let store = TestStore(initialState: StudyFeature.State()) { StudyFeature() }
        let paperData = try StudyPersistence.encode([paper])
        await store.send(.savePaper(paper)) { $0.$paperData.withLock { $0 = paperData } }
        await store.send(.savePaper(paper))
        let entryData = try StudyPersistence.encode([entry])
        await store.send(.saveExpression(entry)) { $0.$vocabularyData.withLock { $0 = entryData } }
        await store.send(.saveExpression(entry))
        XCTAssertEqual(store.state.vocabulary.first?.paper, paper)
        XCTAssertEqual(store.state.vocabulary.first?.sourceText, paper.passages[0])
    }

    func testResultsDoNotDuplicateSameAttempt() async throws {
        let result = StudyResult(skill: "Listening", title: "Booking", correct: 7, total: 10, isMock: true)
        let store = TestStore(initialState: StudyFeature.State()) { StudyFeature() }
        let data = try StudyPersistence.encode([result])
        await store.send(.record(result)) { $0.$resultData.withLock { $0 = data } }
        await store.send(.record(result))
        XCTAssertEqual(store.state.records.count, 1)
    }

    func testBundledMaterialsDecode() throws {
        let units = try ExamUnit.load()
        XCTAssertEqual(Set(units.map(\.skill)), Set(["Reading", "Listening", "Writing", "Speaking"]))
        XCTAssertEqual(Set(units.map(\.id)).count, units.count)
        for unit in units where unit.skill == "Reading" || unit.skill == "Listening" {
            XCTAssertFalse(unit.questions.isEmpty)
            XCTAssertTrue(unit.questions.allSatisfy { !$0.answers.isEmpty && !$0.explanation.isEmpty })
        }
    }

    func testSelectionExcerptRetainsUnicodeAndChosenOccurrence() {
        let text = "📚 Read this first. Put the book beside the door. Then close it."
        let range = (text as NSString).range(of: "beside")
        XCTAssertEqual(StudyTextSelection.excerpt(text, range: range, expression: "beside"), "Put the book beside the door.")
        XCTAssertEqual(StudyTextSelection.excerpt(text, range: NSRange(location: 9999, length: 1), expression: "beside"), text)
        XCTAssertEqual(SavedExpression.legacy("beside").id, SavedExpression.legacy("beside").id)
        XCTAssertNotEqual(SavedExpression.legacy("beside").id, SavedExpression.legacy("instead of").id)
    }

    func testMeaningEditOnlyChangesSelectedSource() async throws {
        let first = SavedExpression(expression: "book", source: "Reading", sourceText: "Read a book.")
        let second = SavedExpression(expression: "book", source: "Listening", sourceText: "Book a room.")
        let state = StudyFeature.State()
        state.$vocabularyData.withLock { $0 = try! StudyPersistence.encode([first, second]) }
        let store = TestStore(initialState: state) { StudyFeature() }
        var edited = second; edited.meaning = "予約する"
        let expected = try StudyPersistence.encode([first, edited])
        await store.send(.updateMeaning(second.id, "予約する")) { $0.$vocabularyData.withLock { $0 = expected } }
        XCTAssertEqual(store.state.vocabulary[0].meaning, "")
        XCTAssertEqual(store.state.vocabulary[1].meaning, "予約する")
    }

    func testFigmaFontsAreBundledAndRegistered() {
        _ = StudyTypography.japaneseTitle(30)
        _ = StudyTypography.roundedTitle(24)
        XCTAssertNotNil(UIFont(name: "ZenMaruGothic-Black", size: 30))
        XCTAssertNotNil(UIFont(name: "Nunito-Black", size: 24))
    }

    func testPracticeBandNeedsEnoughEvidenceAndUsesSkillSpecificAnchors() {
        XCTAssertNil(StudyBand.objective(skill: "Reading", correct: 3, total: 3))
        XCTAssertEqual(StudyBand.objective(skill: "Reading", correct: 30, total: 40), 6)
        XCTAssertEqual(StudyBand.objective(skill: "Listening", correct: 30, total: 40), 7)
        XCTAssertNil(StudyBand.objective(skill: "Reading", correct: 41, total: 40))
        XCTAssertEqual(StudyBand.cefr(6), "B2")
        XCTAssertNil(StudyBand.overall([]))
    }

    func testAssessmentAndRecordingSurvivePersistence() throws {
        let assessment = PracticeAssessment(criteria: [
            .init(name: "Coherence", band: 6, feedback: "具体例を追加"),
            .init(name: "Pronunciation", band: nil, feedback: "音声未評価")
        ], summary: "内容の評価", improvedResponse: "An improved response.")
        let original = StudyResult(skill: "Speaking", title: "Home", correct: 0, total: 0,
            response: "I live near the park.", assessment: assessment, recordingFile: "recording.m4a", attemptID: UUID())
        let restored = try JSONDecoder().decode(StudyResult.self, from: StudyPersistence.encode(original))
        XCTAssertEqual(restored, original)
        XCTAssertTrue(restored.assessment!.isPartial)
        XCTAssertEqual(restored.assessment?.estimatedBand, 6)
        let legacy = Data(#"{"id":"00000000-0000-0000-0000-000000000001","date":0,"skill":"Reading","title":"Old","correct":3,"total":10,"isMock":false}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(StudyResult.self, from: legacy).assessment)
    }

    func testJSONCodeFenceIsAcceptedWithoutTruncatingContent() throws {
        let data = StudyClient.jsonData("```json\n{\"title\":\"Example\"}\n```")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? [String:String], ["title":"Example"])
    }

    func testFullPaperQuestionNumbersAndChoices() throws {
        let units = try ExamUnit.load()
        XCTAssertEqual(units.first { $0.id == "Reading / Section 2" }?.firstQuestionNumber, 14)
        XCTAssertEqual(units.first { $0.id == "Listening / Part 4" }?.firstQuestionNumber, 31)
        XCTAssertEqual(units.first { $0.id == "Reading / Section 1" }?.questions.first?.choices, ["TRUE", "FALSE", "NOT GIVEN"])
        XCTAssertEqual(units.first { $0.id == "Listening / Part 2" }?.questions.first?.choices, ["A", "B", "C"])
        XCTAssertTrue(units.flatMap(\.questions).allSatisfy { !$0.prompt.contains("\\n") })
    }

    func testInlineOptionsPreserveSemicolonsAndRemoveDuplicateNumber() {
        let instruction = "Choose the correct letter, A, B or C. Write ONE LETTER only. A. Mill Lane Repair Morning; B. Oakfield Library; Collecting Reserved Books; C. Community Garden."
        let layout = StudyQuestionLayout(instruction)
        XCTAssertEqual(layout.options.map(\.label), ["A", "B", "C"])
        XCTAssertEqual(layout.options[1].text, "Oakfield Library; Collecting Reserved Books")
        XCTAssertTrue(layout.formatted.contains("\n\nB. Oakfield"))
        let question = ReadingSet.Question(instruction: instruction, prompt: "1. 1. how to collect a reserved item", answers: ["B"], explanation: "")
        XCTAssertEqual(question.displayPrompt(number: 14, localNumber: 1), "how to collect a reserved item")
        XCTAssertEqual(question.choiceText("B"), "B. Oakfield Library; Collecting Reserved Books")
    }

    func testQuestionLayoutHandlesBundledOptionsAndPreservesOrdinaryProse() throws {
        let units = try ExamUnit.load()
        let choice = try XCTUnwrap(units.first { $0.id == "Listening / Part 2" }?.questions.first)
        XCTAssertEqual(StudyQuestionLayout(choice.prompt).options.map(\.label), ["A", "B", "C"])
        XCTAssertEqual(choice.choiceText("B"), "B. Beside the fountain")
        let heading = try XCTUnwrap(units.first { $0.id == "Reading / Section 3" }?.questions.first)
        XCTAssertEqual(StudyQuestionLayout(heading.instruction).options.count, 6)
        let prose = "A library needs space. B. Smith manages it; opening times vary."
        XCTAssertEqual(StudyQuestionLayout(prose).formatted, prose)
        let decimal = ReadingSet.Question(instruction: "", prompt: "1.5 metres is the minimum distance.", answers: ["TRUE"], explanation: "")
        XCTAssertEqual(decimal.displayPrompt(number: 1, localNumber: 1), decimal.prompt)
    }

    func testBrandFontsLoadWithoutFallback() {
        _ = StudyTypography.body
        for name in ["ZenMaruGothic-Regular", "ZenMaruGothic-Bold", "ZenMaruGothic-Black", "Nunito-Regular", "Nunito-Bold", "Nunito-Black"] {
            XCTAssertNotNil(UIFont(name: name, size: 17), "Bundled font must load: \(name)")
        }
    }

    func testQuestionAnswersPreserveGapsAndDecodeLegacyHistory() throws {
        let result = StudyResult(skill: "Reading", title: "Practice", correct: 1, total: 3,
                                 questionAnswers: ["TRUE", "", "C"])
        let encoded = try StudyPersistence.encode(result)
        XCTAssertEqual(try JSONDecoder().decode(StudyResult.self, from: encoded).questionAnswers, ["TRUE", "", "C"])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "questionAnswers")
        legacy["response"] = "TRUE"
        let decoded = try JSONDecoder().decode(StudyResult.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.questionAnswers)
        XCTAssertEqual(decoded.response, "TRUE")
    }

    func testAdditionalLocalizationsAreBundledAndSelectExplanationLanguage() throws {
        let expected = ["zh-Hans": "设置", "zh-Hant": "設定", "ko": "설정", "es": "Ajustes",
                        "pt-BR": "Ajustes", "vi": "Cài đặt", "id": "Pengaturan", "th": "การตั้งค่า",
                        "hi": "सेटिंग", "ar": "الإعدادات"]
        for (language, settings) in expected {
            let bundle = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))))
            XCTAssertEqual(bundle.localizedString(forKey: "設定", value: nil, table: nil), settings, language)
            XCTAssertNotEqual(StudyClient.explanationLanguage(for: language), "English", language)
            let permission = bundle.localizedString(forKey: "NSMicrophoneUsageDescription", value: nil, table: "InfoPlist")
            XCTAssertTrue(permission.contains("OpenAI"), language)
            let format = bundle.localizedString(forKey: "生成・確認済み %@ / %@ セクション", value: nil, table: nil)
            let rendered = String(format: format, "1", "3")
            XCTAssertTrue(rendered.contains("1") && rendered.contains("3"), language)
        }
        XCTAssertEqual(StudyClient.explanationLanguage(for: "unknown"), "English")
    }

    func testEnglishAndJapaneseCatalogsAreBundled() throws {
        let english = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))))
        let japanese = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: "ja", ofType: "lproj"))))
        XCTAssertEqual(english.localizedString(forKey: "設定", value: nil, table: nil), "Settings")
        XCTAssertEqual(japanese.localizedString(forKey: "設定", value: nil, table: nil), "設定")
        let format = english.localizedString(forKey: "生成・確認済み %@ / %@ セクション", value: nil, table: nil)
        XCTAssertEqual(String(format: format, "1", "3"), "Sections ready: 1 / 3")
        XCTAssertTrue(english.localizedString(forKey: "NSMicrophoneUsageDescription", value: nil, table: "InfoPlist").contains("Voice conversations send audio to OpenAI"))
        XCTAssertEqual(english.localizedString(forKey: "音声会話を始める", value: nil, table: nil), "Start voice conversation")
        XCTAssertEqual(japanese.localizedString(forKey: "音声会話を始める", value: nil, table: nil), "音声会話を始める")
    }

    func testCloudMergePreservesOfflineAdditionsAndLatestMeaning() throws {
        let word = SavedExpression(expression: "library", source: "Reading", sourceText: "The library is open.")
        var phone = CloudStudyJournal(), tablet = CloudStudyJournal()
        try phone.capture(.init(vocabulary: [word]), at: Date(timeIntervalSince1970: 1))
        tablet.merge(Array(phone.items.values))
        var updated = word; updated.meaning = "図書館"
        let other = SavedExpression(expression: "course", source: "Listening", sourceText: "A new course.")
        try phone.capture(.init(vocabulary: [word, other]), at: Date(timeIntervalSince1970: 2))
        try tablet.capture(.init(vocabulary: [updated]), at: Date(timeIntervalSince1970: 3))
        let before = phone
        phone.merge(Array(tablet.items.values)); tablet.merge(Array(before.items.values))
        XCTAssertEqual(try phone.snapshot(), try tablet.snapshot())
        XCTAssertEqual(try phone.snapshot().vocabulary.count, 2)
        XCTAssertEqual(try phone.snapshot().vocabulary.first { $0.id == word.id }?.meaning, "図書館")
        let revision = phone.items.values.first { $0.kind == "word" && $0.modified == Date(timeIntervalSince1970: 3) }?.revision
        try phone.capture(phone.snapshot(), at: Date(timeIntervalSince1970: 10))
        XCTAssertTrue(phone.items.values.contains { $0.revision == revision })
    }

    func testCloudJournalRoundTripPreservesAnswersPapersAndAudioReference() throws {
        let paper = try XCTUnwrap(ExamUnit.load().first)
        let result = StudyResult(skill: "Speaking", title: "Practice", correct: 0, total: 0, response: "I take the bus.", recordingFile: "answer.m4a", paper: paper)
        var journal = CloudStudyJournal()
        try journal.capture(.init(results: [result], papers: [paper]))
        let restored = try JSONDecoder().decode(CloudStudyJournal.self, from: StudyPersistence.encode(journal))
        XCTAssertEqual(try restored.snapshot().results, [result])
        XCTAssertEqual(try restored.snapshot().papers, [paper])
        XCTAssertEqual(restored.items.values.first { $0.kind == "result" }?.recording, "answer.m4a")
    }

    func testCloudEqualTimestampMergeConvergesAndAccountsStaySeparate() throws {
        let word = SavedExpression(expression: "book", source: "Reading", sourceText: "A book.")
        var left = CloudStudyJournal(); try left.capture(.init(vocabulary: [word]))
        var first = try XCTUnwrap(left.items.values.first), second = first
        first.revision = "a"; second.revision = "b"
        var right = CloudStudyJournal(); right.merge([second, first]); left.merge([first, second])
        XCTAssertEqual(left.items, right.items)
        XCTAssertTrue(CloudStudyJournal.accepts(account: "A", previous: nil))
        XCTAssertTrue(CloudStudyJournal.accepts(account: "A", previous: "A"))
        XCTAssertFalse(CloudStudyJournal.accepts(account: "B", previous: "A"))
        let folder = URL(fileURLWithPath: "/tmp/Recordings")
        XCTAssertNil(CloudStudyJournal.safeRecordingURL("../secret.m4a", directory: folder))
        XCTAssertNotNil(CloudStudyJournal.safeRecordingURL("answer.m4a", directory: folder))
    }

}


extension PocketIELTSTests {
    func testGenerationCompletionReachesExactly100WithoutRegression() {
        for count in [0, 1, 11] {
            let from = GenerationProgress.estimate(completed: count, total: 12, elapsed: 60)
            let values = (0...100).map { GenerationProgress.finish(from: from, elapsed: Double($0) / 100) }
            XCTAssertEqual(values.first!, from)
            XCTAssertEqual(values.last!, 1)
            XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        }
        XCTAssertLessThan(GenerationProgress.estimate(completed: 1, total: 1, elapsed: 1000), 1)
    }
    func testAudioChunkingPreservesScriptAndAPIRequest() throws {
        let script = String(repeating: "Speaker A: Hello. Speaker B: Good morning!\n", count: 400)
        let chunks = SpeechAudio.chunks(script)
        XCTAssertEqual(chunks.joined(), script)
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 2800 })
        XCTAssertEqual(SpeechAudio.chunks(String(repeating: "a", count: 6000)).joined().count, 6000)
        let request = try SpeechAudio.request(text: chunks[0], key: "test-only-not-a-key")
        XCTAssertEqual(request.url?.path, "/v1/audio/speech")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(json["response_format"], "pcm")
        XCTAssertEqual(json["input"], chunks[0])
        XCTAssertThrowsError(try SpeechAudio.validate(HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, data: Data()))
    }
    @MainActor func testAudioStopRejectsLateGenerationAndResetsPlayback() async throws {
        let player = ListeningPlayer()
        let pcm = Data(repeating: 0, count: 48000)
        let wave = SpeechAudio.wave(pcm)
        let decoded = try AVAudioPlayer(data: wave)
        XCTAssertEqual(decoded.duration, 1, accuracy: 0.01)
        player.play(script: "Test") { _, _ in
            try? await Task.sleep(for: .milliseconds(100))
            return wave
        }
        XCTAssertTrue(player.generating)
        player.stop()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(player.generating)
        XCTAssertNil(player.player)
        player.play(script: "Test") { _, _ in wave }
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertNotNil(player.player)
        player.stop()
        XCTAssertFalse(player.player?.isPlaying ?? true)
        XCTAssertEqual(player.player?.currentTime, 0)
    }
}

extension PocketIELTSTests {
    func testCloudDeletionDoesNotResurrectOfflineVocabulary() throws {
        let entry = SavedExpression(expression: "ordinary", source: "Reading", sourceText: "An ordinary day.")
        var left = CloudStudyJournal(), right = CloudStudyJournal()
        try left.capture(.init(vocabulary: [entry]), at: Date(timeIntervalSince1970: 1))
        right.merge(Array(left.items.values))
        try left.capture(.init(deletedVocabulary: [.init(id: entry.id, date: Date(timeIntervalSince1970: 2))]), at: Date(timeIntervalSince1970: 2))
        left.merge(Array(right.items.values)); right.merge(Array(left.items.values))
        XCTAssertTrue(try left.snapshot().vocabulary.isEmpty)
        XCTAssertTrue(try right.snapshot().vocabulary.isEmpty)
        XCTAssertEqual(try right.snapshot().deletedVocabulary.map(\.id), [entry.id])
        var relaunched = try JSONDecoder().decode(CloudStudyJournal.self, from: StudyPersistence.encode(right))
        try relaunched.capture(try right.snapshot(), at: Date(timeIntervalSince1970: 3))
        XCTAssertTrue(try relaunched.snapshot().vocabulary.isEmpty)
    }
}

extension PocketIELTSTests {
    func testLicensePlistNoticesAreBundledAndReadable() throws {
        let notices = try OSSNotice.load()
        XCTAssertGreaterThanOrEqual(notices.count, 17)
        XCTAssertTrue(notices.contains { $0.title.contains("Nunito") })
        XCTAssertTrue(notices.contains { $0.title.contains("swift-composable-architecture") })
        XCTAssertTrue(notices.allSatisfy { $0.text.count > 100 })
    }
}

extension PocketIELTSTests {
    @MainActor func testMarkdownRendersStructureAndPreservesVisibleSelectionOffsets() {
        let source = "## Meaning\n\n**Buying** means buying.\n\n- First item\n- Second item\n\n1. Example one\n2. Example two\n\n`purchase`"
        let rendered = StudyMarkdown.render(source)
        XCTAssertFalse(rendered.string.contains("**"))
        XCTAssertFalse(rendered.string.contains("##"))
        XCTAssertTrue(rendered.string.contains("•  First item"))
        XCTAssertTrue(rendered.string.contains("2.  Example two"))
        let range = (rendered.string as NSString).range(of: "Buying")
        XCTAssertEqual((rendered.string as NSString).substring(with: range), "Buying")
        let font = rendered.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertTrue(rendered.string.contains("purchase"))
        XCTAssertFalse(rendered.string.contains("`"))
    }
    func testSavedPapersGroupByRealSkillPartNotTitle() throws {
        let papers = try ExamUnit.load()
        XCTAssertEqual(Set(papers.filter { $0.skill == "Reading" }.map(SavedPaperGrouping.part)), ["Section 1", "Section 2", "Section 3"])
        XCTAssertEqual(Set(papers.filter { $0.skill == "Listening" }.map(SavedPaperGrouping.part)), ["Part 1", "Part 2", "Part 3", "Part 4"])
        let paper = ExamUnit(id: "Reading / Section 1 · Section 3 of the museum", skill: "Reading", title: "Section 3 of the museum", directions: "", passages: [], questions: [], audio: nil, oral: [])
        XCTAssertEqual(SavedPaperGrouping.part(paper), "Section 1")
    }
}


extension PocketIELTSTests {
    func testDialogueAudioRemovesLabelsAndKeepsVoicesStable() throws {
        let parts = SpeechAudio.segments("Receptionist: Welcome.\nCaller: Hello!\nReceptionist: We open at 9:30.\nPlease arrive early.")
        XCTAssertEqual(parts.map(\.text), ["Welcome.", "Hello!", "We open at 9:30.\nPlease arrive early."])
        XCTAssertEqual(parts[0].voice, parts[2].voice)
        XCTAssertNotEqual(parts[0].voice, parts[1].voice)
        let request = try SpeechAudio.request(text: parts[1].text, key: "test", voice: parts[1].voice)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(json["voice"], parts[1].voice)
        XCTAssertEqual(json["input"], "Hello!")
        XCTAssertEqual(SpeechAudio.segments("We open at 9:30. Bring this: your card.").first?.text, "We open at 9:30. Bring this: your card.")
        XCTAssertEqual(SpeechAudio.segments("**Emma:** Good morning.\n**Tom:** Hello.").map(\.text), ["Good morning.", "Hello."])
        XCTAssertTrue(SpeechAudio.segments("  ").isEmpty)
    }
}

extension PocketIELTSTests {
    func testDeleteSavedPaperPreservesHistoryVocabularyAndCanSaveAgain() async throws {
        let paper = try XCTUnwrap(ExamUnit.load().first)
        let entry = SavedExpression(expression: "ordinary", source: paper.id, sourceText: "ordinary", paper: paper)
        let result = StudyResult(skill: paper.skill, title: paper.title, correct: 1, total: 1, paper: paper)
        let date = Date(timeIntervalSince1970: 10)
        var initial = StudyFeature.State()
        initial.$paperData.withLock { $0 = try! StudyPersistence.encode([paper]) }
        initial.$vocabularyData.withLock { $0 = try! StudyPersistence.encode([entry]) }
        initial.$resultData.withLock { $0 = try! StudyPersistence.encode([result]) }
        let store = TestStore(initialState: initial) { StudyFeature() } withDependencies: { $0.date.now = date }
        await store.send(.deletePaper(paper.id)) {
            $0.$paperData.withLock { $0 = try! StudyPersistence.encode([ExamUnit]()) }
            $0.$deletedPaperData.withLock { $0 = try! StudyPersistence.encode([DeletedPaper(id: paper.id, date: date)]) }
        }
        XCTAssertTrue(store.state.papers.isEmpty)
        XCTAssertEqual(store.state.records, [result])
        XCTAssertEqual(store.state.vocabulary, [entry])
        await store.send(.deletePaper(paper.id))
        await store.send(.savePaper(paper)) {
            $0.$deletedPaperData.withLock { $0 = try! StudyPersistence.encode([DeletedPaper]()) }
            $0.$paperData.withLock { $0 = try! StudyPersistence.encode([paper]) }
        }
        XCTAssertEqual(store.state.papers, [paper])
    }

    func testDeletedSavedPaperSurvivesOfflineMergeAndExplicitResave() throws {
        let paper = try XCTUnwrap(ExamUnit.load().first)
        var left = CloudStudyJournal(), right = CloudStudyJournal()
        try left.capture(.init(papers: [paper]), at: Date(timeIntervalSince1970: 1))
        right.merge(Array(left.items.values))
        try left.capture(.init(deletedPapers: [.init(id: paper.id, date: Date(timeIntervalSince1970: 2))]), at: Date(timeIntervalSince1970: 2))
        try right.capture(.init(papers: [paper]), at: Date(timeIntervalSince1970: 3))
        left.merge(Array(right.items.values)); right.merge(Array(left.items.values))
        XCTAssertTrue(try left.snapshot().papers.isEmpty)
        XCTAssertTrue(try right.snapshot().papers.isEmpty)
        var relaunched = try JSONDecoder().decode(CloudStudyJournal.self, from: StudyPersistence.encode(left))
        XCTAssertEqual(try relaunched.snapshot().deletedPapers.map(\.id), [paper.id])
        try relaunched.capture(.init(papers: [paper]), at: Date(timeIntervalSince1970: 4))
        right.merge(Array(relaunched.items.values))
        XCTAssertEqual(try right.snapshot().papers, [paper])
        XCTAssertTrue(try right.snapshot().deletedPapers.isEmpty)
    }
}


extension PocketIELTSTests {
    func testBackgroundGenerationClampsProgressAndFinishes() async throws {
        var observed: BackgroundGeneration?
        let result = try await BackgroundGeneration.run(title: "Fixture", total: 3, useSystemScheduler: false) { job in
            observed = job
            job.update(completed: 2, total: 3)
            job.update(completed: 1, total: 3)
            XCTAssertEqual(job.completed, 2)
            job.update(completed: 9, total: 3)
            XCTAssertEqual(job.completed, 3)
            return 42
        }
        XCTAssertEqual(result, 42)
        XCTAssertTrue(try XCTUnwrap(observed).finished)
    }

    func testBackgroundExpirationCancelsWorkAndRejectsLateResult() async throws {
        var observed: BackgroundGeneration?
        do {
            _ = try await BackgroundGeneration.run(title: "Fixture", total: 3, useSystemScheduler: false) { job in
                observed = job
                job.update(completed: 1, total: 3)
                job.interrupt()
                // A transport that ignores cancellation cannot mark the job complete.
                return 42
            }
            XCTFail("Interrupted work must not succeed")
        } catch {
            XCTAssertFalse(error is CancellationError, "System cancellation needs an actionable retry message")
        }
        XCTAssertTrue(try XCTUnwrap(observed).finished)
        XCTAssertEqual(observed?.completed, 1)
    }

    func testBackgroundGenerationPropagatesOwnerCancellation() async throws {
        let started = expectation(description: "Started")
        let cancelled = expectation(description: "Cancelled")
        let task = Task {
            try await BackgroundGeneration.run(title: "Fixture", total: 1, useSystemScheduler: false) { _ in
                started.fulfill()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { cancelled.fulfill(); throw error }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [cancelled], timeout: 2)
    }

    func testPausingListeningDoesNotCancelAudioGeneration() async throws {
        let player = ListeningPlayer()
        let started = expectation(description: "Audio started")
        player.play(script: "Fixture") { _, progress in
            await progress(0, 1)
            started.fulfill()
            try await Task.sleep(for: .milliseconds(100))
            return SpeechAudio.wave(Data(repeating: 0, count: 48000))
        }
        await fulfillment(of: [started], timeout: 2)
        player.pause() // Called when the app resigns active.
        XCTAssertTrue(player.generating)
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertNotNil(player.player)
        XCTAssertFalse(player.player?.isPlaying ?? true, "Returning to the app must not autoplay background-generated audio")
        player.stop() // Explicit stop / leaving the question still cancels.
        XCTAssertFalse(player.generating)
    }
}


extension PocketIELTSTests {
    func testSharedProgressDoesNotJumpWithLargePayloads() async throws {
        var displayed = 0.0
        var observed: BackgroundGeneration?
        try await BackgroundGeneration.run(title: "Fixture", total: 2, useSystemScheduler: false,
                                           onProgress: { displayed = $0 }) { job in
            observed = job
            await GenerationTransferProgress.received(10_000_000)
            XCTAssertLessThan(job.fraction, 0.02, "Payload bytes must not push progress to 89%")
            XCTAssertEqual(displayed, job.fraction)
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertGreaterThan(job.fraction, 0)
            XCTAssertEqual(displayed, job.fraction)
            job.update(completed: 1, total: 2)
            XCTAssertEqual(job.fraction, 0.5, accuracy: 0.001)
            await GenerationTransferProgress.received(50_000_000)
            XCTAssertLessThan(job.fraction, 0.52)
            XCTAssertEqual(displayed, job.fraction)
        }
        XCTAssertEqual(displayed, 1)
        XCTAssertEqual(displayed, observed?.fraction)
        XCTAssertNil(GenerationTransferProgress.report)
    }

    func testSharedCompletionReaches100BeforeReturning() async throws {
        var displayed = 0.0
        var values: [Double] = []
        try await BackgroundGeneration.run(title: "Fixture", total: 1, useSystemScheduler: false,
                                           completionDuration: 0.3,
                                           onProgress: { displayed = $0; values.append($0) }) { job in
            job.update(completed: 1, total: 1)
            XCTAssertLessThan(displayed, 1)
        }
        XCTAssertEqual(displayed, 1)
        XCTAssertTrue(values.contains { $0 > 0.1 && $0 < 1 })
        XCTAssertEqual(values, values.sorted())
    }
}


extension PocketIELTSTests {
    func testListeningRewindClampsAtStartAndPreservesPause() async throws {
        let player = ListeningPlayer()
        player.rewindTenSeconds() // Safe before audio exists.
        player.play(script: "Fixture") { _, _ in
            SpeechAudio.wave(Data(repeating: 0, count: 48000 * 20))
        }
        player.pause()
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertNotNil(player.player)
        player.seek(15)
        player.rewindTenSeconds()
        XCTAssertEqual(try XCTUnwrap(player.player).currentTime, 5, accuracy: 0.05)
        XCTAssertFalse(player.player?.isPlaying ?? true)
        player.rewindTenSeconds()
        XCTAssertEqual(player.player?.currentTime, 0)
        player.rewindTenSeconds()
        XCTAssertEqual(player.player?.currentTime, 0)
        player.stop()
    }
}


extension PocketIELTSTests {
    func testQuestionVisualsPersistAndOldPapersStillDecode() throws {
        let papers = try ExamUnit.load()
        let paper = try XCTUnwrap(papers.first { $0.id == "Listening / Part 2" })
        XCTAssertEqual(paper.visuals?.count, 1)
        try QuestionVisual.validate(paper.visuals)
        XCTAssertEqual(try JSONDecoder().decode(ExamUnit.self, from: JSONEncoder().encode(paper)), paper)
        XCTAssertTrue(QuestionVisual.context(paper.visuals).contains("Fountain"))
        XCTAssertNil(papers.first { $0.id == "Listening / Part 1" }?.visuals)
    }

    func testQuestionVisualRejectsInvalidGeometryAndMissingFigure() throws {
        let paper = try XCTUnwrap(try ExamUnit.load().first { $0.id == "Listening / Part 2" })
        var figure = try XCTUnwrap(paper.visuals?.first)
        figure.elements[0].width = 200
        XCTAssertThrowsError(try QuestionVisual.validate([figure]))
        figure.elements[0].width = .infinity
        XCTAssertThrowsError(try QuestionVisual.validate([figure]))
        XCTAssertThrowsError(try QuestionVisual.validate(nil, instructions: ["Label the map below."]))
        XCTAssertThrowsError(try QuestionVisual.validate([], instructions: ["Study the chart above."]))
        XCTAssertNoThrow(try QuestionVisual.validate(nil, instructions: ["What does the speaker plan to do?"]))
    }
}
