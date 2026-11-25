import ActivityKit
import AVFoundation
import SwiftUI
import Testing
import UIKit
import ComposableArchitecture
@testable import PocketIELTS

@Suite(.serialized)
@MainActor
struct PocketIELTSTests {
    @Test
    func vocabularySuggestionsKeepCompleteDistinctCards() throws {
        let reply = """
        {"suggestions":[{"expression":" leave ","meaning":"休暇","example":"I am on leave."},
        {"expression":"LEAVE","meaning":"休み","example":"She took leave."},
        {"expression":"day off","meaning":"","example":"I have a day off."},
        {"expression":"take time off","meaning":"休みを取る","example":"Can I take time off?"}]}
        """
        let cards = try VocabularySuggestion.parse(reply)
        #expect(cards.map(\.expression) == ["leave", "take time off"])
        #expect(cards.first?.meaning == "休暇")
        #expect(cards.first?.example == "I am on leave.")
        #expect(throws: StudyError.self) { try VocabularySuggestion.parse("{}") }
    }

    @Test
    func testExamMaterialPreservesTableBlanksAndSurroundingDirections() {
        let material = """
        Complete the table.

        | Event | Detail | Information |
        | :--- | :---: | ---: |
        | Dawn bird walk | Meeting point | (1) _____ |
        | Lantern workshop | Cost per person | £(6) _____ |

        Questions 7–10
        """
        #expect(ExamMaterialBlock.parse(material.replacingOccurrences(of: "\n", with: "\r\n")) == [
            .prose("Complete the table."),
            .table([["Event", "Detail", "Information"], ["Dawn bird walk", "Meeting point", "(1) _____"],
                    ["Lantern workshop", "Cost per person", "£(6) _____"]]),
            .prose("Questions 7–10")
        ])
        let plain = "Choose A | B.\n---"
        #expect(ExamMaterialBlock.parse(plain) == [.prose(plain)])
    }

    @Test
    func testListeningTableWithoutMarkdownSeparator() {
        let material = """
        Sources for the Millbank washhouse exhibition
        Source | Detail to include in the exhibition
        Opening leaflet | Item customers had to bring: (21) _____
        Caretaker’s notebook | Day reserved for washing blankets: (22) _____
        Council accounts | Item that accounted for most of the annual running costs: (23) _____
        Building inspector’s report | Reason for fitting new windows: better (24) _____
        Staff photograph | Feature used to identify the building: (25) _____
        Closing notice | New location of the washhouse equipment: (26) _____

        Questions 27–30
        """
        let blocks = ExamMaterialBlock.parse(material)
        #expect(blocks.first == .prose("Sources for the Millbank washhouse exhibition"))
        #expect(blocks.last == .prose("Questions 27–30"))
        guard blocks.count == 3, case let .table(rows) = blocks[1] else {
            Issue.record("Expected a two-column table between the title and the next instructions")
            return
        }
        #expect(rows.count == 7)
        #expect(rows.allSatisfy { $0.count == 2 })
        let fragments = material.components(separatedBy: "\n")
        let grouped = ExamMaterialBlock.passages(fragments)
        #expect(ExamMaterialBlock.parse(grouped[1].text) == [.table(rows)])
        #expect(grouped.last?.offset == fragments.count - 1)
        #expect(rows[0] == ["Source", "Detail to include in the exhibition"])
        #expect(rows[1] == ["Opening leaflet", "Item customers had to bring: (21) _____"])
        #expect(rows[6] == ["Closing notice", "New location of the washhouse equipment: (26) _____"])
    }

    @Test
    func testExamTablePlacesSelectableWordsUnderTheirHeaders() throws {
        try checkTableLayout("| Event | Detail | Information |\n| --- | --- | --- |\n| Dawn bird walk | Meeting point | (1) _____ |",
                             width: 375, firstHeader: "Event", answerHeader: "Information", answerCell: "(1) _____")
        try checkTableLayout("Source | Detail to include in the exhibition\nOpening leaflet | Item customers had to bring: (21) _____",
                             width: 760, firstHeader: "Source", answerHeader: "Detail to include in the exhibition",
                             answerCell: "Item customers had to bring: (21) _____")
    }

    private func checkTableLayout(_ material: String, width: CGFloat, firstHeader: String, answerHeader: String, answerCell: String) throws {
        let view = ExamMaterialText(text: material) { value, id in
            SelectableStudyText(text: value, sourceID: id, onSave: { _ in })
        }
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 600))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        func textViews(in view: UIView) -> [UITextView] {
            view.subviews.flatMap { child in
                if let text = child as? UITextView { return [text] }
                return textViews(in: child)
            }
        }
        let cells = textViews(in: host.view)
        func rect(_ value: String) throws -> CGRect {
            let cell = try #require(cells.first { $0.text == value && $0.window != nil })
            return cell.convert(cell.bounds, to: host.view)
        }
        let event = try rect(firstHeader)
        let blank = try rect(answerCell)
        #expect(blank.minX > event.maxX)
        #expect(blank.minY >= event.maxY)
        #expect(abs(blank.minX - (try rect(answerHeader).minX)) <= 1)
        #expect(blank.maxX <= window.bounds.width)
    }

    @Test
    func testSectionPreparesOnceAndRefillsAfterExit() async throws {
        let template = try #require(ExamUnit.load().first)
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var requests = 0
        let sections = SectionPreparation(directory: directory) { template in
            requests += 1
            return template
        }
        let id = sections.key(template)
        sections.configure([template], enabled: false, active: true)
        #expect(sections.percent[id] == nil)
        sections.configure([template], enabled: true, active: true)
        #expect(sections.percent[id] == 0)
        let first = try await sections.open(template)
        #expect(sections.ready[id] == first)
        #expect(requests == 1)
        let restored = SectionPreparation(directory: directory) { _ in Issue.record("Unexpected request"); return template }
        let cached = try await restored.open(template)
        #expect(cached == first)
        sections.finished(template, paper: first)
        #expect(sections.ready[id] == nil)
        #expect(sections.percent[id] == 0)
        _ = try await sections.open(template)
        #expect(requests == 2)
        sections.configure([template], enabled: false, active: true)
        sections.finished(template, paper: template)
        #expect(sections.percent[id] == nil)
        #expect(sections.ready[id] == nil)
    }

    @Test
    func completionNotificationsOnlyPresentWhileActive() {
        #expect(GenerationNotifications.presentationOptions(for: .active).contains(.banner))
        #expect(GenerationNotifications.presentationOptions(for: .inactive).isEmpty)
        #expect(GenerationNotifications.presentationOptions(for: .background).isEmpty)
    }

    #if targetEnvironment(simulator)
    @Test(.enabled(if: ActivityAuthorizationInfo().areActivitiesEnabled))
    func reviewedSectionRefillKeepsLiveActivityWhenSceneLeavesForeground() async throws {
        let template = try #require(ExamUnit.load().first)
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var gate: CheckedContinuation<Void, Never>?
        var requests = 0
        let sections = SectionPreparation(directory: directory) { template in
            requests += 1
            if requests == 2 { await withCheckedContinuation { gate = $0 } }
            return template
        }
        sections.configure([template], enabled: true, active: true)
        let first = try await sections.open(template)
        sections.finished(template, paper: first)
        await waitUntil(timeout: .seconds(5)) { gate != nil }
        defer { gate?.resume() }
        let activity = try #require(Activity<GenerationActivity>.activities.first {
            $0.content.state.title == template.id && $0.activityState == .active
        })
        sections.configure([template], enabled: true, active: false)
        #expect(Activity<GenerationActivity>.activities.contains { $0.id == activity.id })
        gate?.resume()
        gate = nil
        _ = try await sections.open(template)
        #expect(requests == 2)
    }
    #endif

    @Test
    func testAllSectionsStartBeforeAnyCompletesAndFailIndependently() async throws {
        let templates = try ExamUnit.load()
        #expect(templates.count == 12)
        let first = try #require(templates.first)
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        var gates: [String: CheckedContinuation<Void, Never>] = [:]
        var calls: [String: Int] = [:]
        let sections = SectionPreparation(directory: directory) { template in
            calls[template.id, default: 0] += 1
            if calls[template.id] == 1 {
                await withCheckedContinuation { gate in
                    gates[template.id] = gate
                }
                if template.id == first.id { throw StudyError.message("Test failure") }
            }
            return template
        }
        sections.configure(templates, enabled: true, active: true)
        await waitUntil(timeout: .seconds(5)) { gates.count == templates.count }
        guard gates.count == templates.count else {
            sections.configure(templates, enabled: false, active: true)
            for gate in gates.values { gate.resume() }
            return
        }
        Task { for gate in gates.values { gate.resume() } }
        do {
            _ = try await sections.open(first)
            Issue.record("The simulated failure must reach the section that failed")
        } catch {}
        for template in templates.dropFirst() {
            let paper = try await sections.open(template)
            #expect(paper == template)
            #expect(calls[template.id] == 1)
        }
        #expect(sections.errors.count == 1)
        #expect(sections.ready.count == templates.count - 1)
        _ = try await sections.open(first)
        #expect(calls[first.id] == 2)
        #expect(sections.errors.isEmpty)
        #expect(sections.ready.count == templates.count)
    }

    @Test
    func testLoopbackAuthenticationSurvivesInvalidRequestAndCompletes() async throws {
        var redirect: URL?
        let browser = SignInBrowser(presentForTesting: { redirect = $0 })
        let task = Task { try await browser.authorize(state: "test-state") { $0 } }
        defer { task.cancel() }
        await waitUntil(timeout: .seconds(5)) { redirect != nil }
        let base = try #require(redirect)
        #expect(base.host == "127.0.0.1")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        // A stale browser tab cannot consume the active sign-in attempt.
        let invalid = URL(string: base.absoluteString + "?state=wrong&code=fixture")!
        _ = try? await session.data(from: invalid)
        let valid = URL(string: base.absoluteString + "?state=test-state&code=fixture")!
        let (data, response) = try await session.data(from: valid)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("Pokelts"))
        let (callback, returnedRedirect) = try await task.value
        #expect(callback == valid)
        #expect(returnedRedirect == base)
    }

    @Test
    func testOfflineLibraryHasAllPartsAndIndependentVocabulary() throws {
        let units = try ExamUnit.load()
        #expect(units.count == 12)
        #expect(units.filter { $0.skill == "Reading" }.flatMap(\.questions).count == 40)
        #expect(units.filter { $0.skill == "Listening" }.flatMap(\.questions).count == 40)
        #expect(StarterWord.all.count == 1000)
        #expect(Set(StarterWord.all.map(\.id)).count == 1000)
        for level in 0..<3 { #expect(StarterWord.all.filter { $0.level == level }.count >= 90) }
        #expect(StarterWord.all.allSatisfy { !$0.definition.isEmpty })
    }

    @Test
    func testGeneralTrainingCoverageAndWaitingMeanings() throws {
        for topic in StarterWord.topics {
            #expect(StarterWord.all.filter { $0.topic == topic }.count == 100)
        }
        #expect(StarterWord.all.allSatisfy { !$0.example.isEmpty && $0.example.localizedCaseInsensitiveContains($0.expression) })
        let saved = SavedExpression(expression: "accommodation", source: "Reading", sourceText: "Find accommodation near work.")
        let deck = VocabularyCard.waitingDeck([saved])
        #expect(deck.count == 1000)
        #expect(deck.first?.word == "accommodation")
        let first = try #require(deck.first)
        #expect(!first.meaning.isEmpty)
        #expect(first.personal)
        let unknown = SavedExpression(expression: "xyz unknown", source: "manual", sourceText: "")
        let withUnknown = VocabularyCard.waitingDeck([unknown])
        #expect(withUnknown.first?.word == "xyz unknown")
        let firstUnknown = try #require(withUnknown.first)
        #expect(firstUnknown.personal)
        #expect(firstUnknown.meaning.isEmpty)
        #expect(withUnknown.count == 1001)
        #expect(withUnknown.dropFirst().allSatisfy { !$0.meaning.isEmpty && !$0.personal })
        #expect(deck.dropFirst().allSatisfy { !$0.personal && $0.word.lowercased() != "accommodation" })
        #expect(VocabularyCard.waitingDeck([]).allSatisfy { !$0.personal })
        #expect(VocabularyCard(SavedExpression(expression: "  ", source: "manual", sourceText: "")) == nil)
    }

    @Test
    func testWaitingDeckShowsAllPersonalWordsBeforeUniqueBundledWords() {
        let saved = ["available", "ventilation", "AVAILABLE", "my own phrase", "  "].map {
            SavedExpression(expression: $0, source: "manual", sourceText: "")
        }
        // Assert ordering and membership independently of each random shuffle.
        for _ in 0..<10 {
            let deck = VocabularyCard.waitingDeck(saved)
            #expect(Set(deck.prefix(3).map { $0.word.lowercased() }) == ["available", "ventilation", "my own phrase"])
            #expect(deck.prefix(3).allSatisfy { $0.personal })
            #expect(deck.dropFirst(3).allSatisfy { !$0.personal })
            #expect(Set(deck.map { $0.word.lowercased() }).count == deck.count)
            #expect(deck.count == 1001)
            for pair in zip(deck, deck.dropFirst()) { #expect(pair.0.word.lowercased() != pair.1.word.lowercased()) }
        }
    }

    @Test
    func testPronunciationUsesEnglishAndStopsCleanly() {
        let utterance = WordPronouncer.utterance(for: "accommodation")
        #expect(utterance.speechString == "accommodation")
        #expect(utterance.voice?.language.hasPrefix("en") == true)
        #expect(utterance.rate < AVSpeechUtteranceDefaultSpeechRate)
        let pronouncer = WordPronouncer()
        pronouncer.stop()
        #expect(pronouncer.activeWord == nil)
    }

    @Test
    func testSpeakingReceivedAudioActuallyRendersAndInterruptionClearsIt() throws {
        // Exercise the real AVAudioEngine graph offline: no microphone, key, or API call.
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false))
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
        #expect(player.isPlaying)
        let rendered = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        var peak: Float = 0
        for _ in 0..<4 {
            #expect(try engine.renderOffline(1024, to: rendered) == .success)
            for i in 0..<Int(rendered.frameLength) { peak = max(peak, abs(rendered.floatChannelData![0][i])) }
        }
        #expect(peak > 0.1, "Received PCM must produce non-silent output, not just a speaking label")
        session.handle(["type": "input_audio_buffer.speech_started"])
        #expect(!player.isPlaying)
        session.handle(["type": "response.output_audio.delta", "item_id": "audio", "delta": pcm.base64EncodedString()])
        #expect(!player.isPlaying, "Late audio from the interrupted response must stay discarded")
        session.stop()
        #expect(!engine.isRunning)
    }

    @Test
    func testSpeakingPermissionDialogDoesNotCancelStartup() {
        let session = SpeakingConversation(phase: .connecting)
        session.sceneChanged(.inactive)
        session.audioInterrupted(.ended)
        session.sceneChanged(.active)
        #expect(session.phase == .connecting)
        #expect(session.active)
        session.sceneChanged(.background)
        #expect(session.phase == .ended)
        session.sceneChanged(.active)
        #expect(!session.active)
    }

    @Test
    func testSpeakingOnlyStopsForBeginningOfAnAudioInterruption() {
        let session = SpeakingConversation(phase: .listening)
        session.audioInterrupted(.ended)
        #expect(session.active)
        session.audioInterrupted(.began)
        #expect(!session.active)
        session.audioInterrupted(.ended)
        #expect(!session.active)
    }

    @Test
    func testSpeakingAPIErrorMessagesIdentifyCauseWithoutEchoingSecrets() {
        let generic = SpeakingProtocol.errorDescription([:])
        for code in ["invalid_api_key", "insufficient_quota", "model_not_found"] {
            let message = SpeakingProtocol.errorDescription(["code": code, "message": "secret"])
            #expect(message != generic)
            #expect(!message.contains("secret"))
        }
        #expect(SpeakingProtocol.errorDescription(["param": "session.audio.input.transcription.model"]) != generic)
    }

    @Test
    func testSpeakingDefaultsToMiniAndBuildsSelectedModelSession() throws {
        #expect(SpeakingModel.resolve(nil) == .mini)
        #expect(SpeakingModel.resolve("unknown") == .mini)
        #expect(SpeakingModel.resolve(SpeakingModel.standard.rawValue) == .standard)
        let unit = try #require(ExamUnit.load().first { $0.skill == "Speaking" })
        for model in SpeakingModel.allCases {
            let request = SpeakingProtocol.request(model: model, key: "test-only")
            #expect(request.url!.absoluteString.contains(model.rawValue))
            let event = SpeakingProtocol.configuration(unit: unit, model: model)
            let session = try #require(event["session"] as? [String: Any])
            #expect(session["model"] as? String == model.rawValue)
            let audio = try #require(session["audio"] as? [String: Any])
            let input = try #require(audio["input"] as? [String: Any])
            let vad = try #require(input["turn_detection"] as? [String: Any])
            #expect(vad["type"] as? String == "semantic_vad")
            #expect(vad["interrupt_response"] as? Bool == true)
            _ = try SpeakingProtocol.encode(event)
        }
    }

    @Test
    func testSpeakingTranscriptUsesCommittedOrderAndOnlyCandidateAnswers() {
        let session = SpeakingConversation(phase: .listening)
        session.handle(["type": "input_audio_buffer.committed", "item_id": "first"])
        session.handle(["type": "input_audio_buffer.committed", "item_id": "second"])
        session.handle(["type": "conversation.item.input_audio_transcription.completed", "item_id": "second", "transcript": "Second answer"])
        session.handle(["type": "response.output_audio_transcript.done", "item_id": "examiner", "transcript": "Where do you live?"])
        session.handle(["type": "conversation.item.input_audio_transcription.completed", "item_id": "first", "transcript": "First answer"])
        #expect(session.userTranscript == "First answer\n\nSecond answer")
        session.handle(["type": "conversation.item.input_audio_transcription.completed", "item_id": "first", "transcript": "Corrected answer"])
        #expect(session.turns.count == 3)
        #expect(session.userTranscript == "Corrected answer\n\nSecond answer")
        session.stop()
        session.handle(["type": "conversation.item.input_audio_transcription.completed", "item_id": "late", "transcript": "Ignored"])
        #expect(session.phase == .ended)
        #expect(session.turns.count == 3)
        session.stop() // Dismissal and interruption may both stop a session.
    }

    @Test
    func testSpeakingErrorsEndSessionWithoutExposingServerPayload() {
        let session = SpeakingConversation(phase: .thinking)
        session.handle(["type": "error", "error": ["message": "sensitive server payload"]])
        #expect(!session.active)
        #expect(session.error != nil)
        #expect(!session.error!.contains("sensitive"))
        #expect(throws: (any Error).self) { try SpeakingProtocol.decode(.string("[]")) }
    }

    @Test
    func testAnswerAcceptsAlternativeSpellingAndWhitespace() {
        let question = ReadingSet.Question(instruction: "Write two words.", prompt: "Where?",
                                          answers: ["town centre", "town center"], explanation: "Location")
        #expect(question.accepts("  TOWN   Center\n"))
        #expect(!question.accepts("town"))
        #expect(!question.accepts(""))
    }

    @Test
    func testChatGPTOnlyPracticeGate() {
        var state = SettingsFeature.State()
        #expect(!state.canPractice)
        state.account.active = "profile"
        #expect(state.canPractice)
        state.account.active = nil
        #expect(!state.canPractice)
    }

    @Test
    func testAccountRefresh() async {
        let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() }
            withDependencies: { $0[AccountClient.self] = AccountClient(status: { .init(active: "profile") }, signIn: { _ in }, signOut: {}) }
        await store.send(.refreshAccount)
        await store.receive(\.accountChanged) { $0.account.active = "profile" }
    }

    @Test
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
                #expect(section == 2)
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
    @Test
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
        #expect(store.state.vocabulary.first?.paper == paper)
        #expect(store.state.vocabulary.first?.sourceText == paper.passages[0])
    }

    @Test
    func testResultsDoNotDuplicateSameAttempt() async throws {
        let result = StudyResult(skill: "Listening", title: "Booking", correct: 7, total: 10, isMock: true)
        let store = TestStore(initialState: StudyFeature.State()) { StudyFeature() }
        let data = try StudyPersistence.encode([result])
        await store.send(.record(result)) { $0.$resultData.withLock { $0 = data } }
        await store.send(.record(result))
        #expect(store.state.records.count == 1)
    }

    @Test
    func testBundledMaterialsDecode() throws {
        let units = try ExamUnit.load()
        #expect(Set(units.map(\.skill)) == Set(["Reading", "Listening", "Writing", "Speaking"]))
        #expect(Set(units.map(\.id)).count == units.count)
        for unit in units where unit.skill == "Reading" || unit.skill == "Listening" {
            #expect(!unit.questions.isEmpty)
            #expect(unit.questions.allSatisfy { !$0.answers.isEmpty && !$0.explanation.isEmpty })
        }
    }

    @Test
    func testSelectionExcerptRetainsUnicodeAndChosenOccurrence() {
        let text = "📚 Read this first. Put the book beside the door. Then close it."
        let range = (text as NSString).range(of: "beside")
        #expect(StudyTextSelection.excerpt(text, range: range, expression: "beside") == "Put the book beside the door.")
        #expect(StudyTextSelection.excerpt(text, range: NSRange(location: 9999, length: 1), expression: "beside") == text)
        #expect(SavedExpression.legacy("beside").id == SavedExpression.legacy("beside").id)
        #expect(SavedExpression.legacy("beside").id != SavedExpression.legacy("instead of").id)
    }

    @Test
    func testMarkedMeaningUsesDisplayLanguageAndSavesToTheWord() async throws {
        let paper = try #require(try ExamUnit.load().first)
        let entry = SavedExpression(expression: "courtyard", source: paper.id,
                                    sourceText: "Cross the courtyard.", paper: paper)
        let key = MarkedWordKey(expression: entry.expression, context: entry.contextExcerpt,
                                language: StudyClient.explanationLanguage(for: "ja"))
        let meaning = "中庭。この文は「中庭を横切ってください」という意味です。"
        var initial = StudyFeature.State()
        initial.settings.account.active = "profile"
        initial.$vocabularyData.withLock { $0 = try! StudyPersistence.encode([entry]) }
        let store = TestStore(initialState: initial) { StudyFeature() } withDependencies: {
            $0[StudyClient.self].explain = { context, prompt in
                #expect(prompt.contains("Japanese"))
                #expect(context.contains("Cross the courtyard."))
                return meaning
            }
        }
        var updated = entry
        updated.meaning = meaning
        updated.meaningLanguage = "Japanese"
        let data = try StudyPersistence.encode([updated])
        await store.send(.explainMarkedWord(key)) { $0.markedMeanings[key] = .loading }
        await store.receive(\.markedMeaningResult) {
            $0.markedMeanings[key] = .ready(meaning)
            $0.$vocabularyData.withLock { $0 = data }
        }
    }

    @Test
    func testMeaningEditOnlyChangesSelectedSource() async throws {
        let first = SavedExpression(expression: "book", source: "Reading", sourceText: "Read a book.")
        let second = SavedExpression(expression: "book", source: "Listening", sourceText: "Book a room.")
        let state = StudyFeature.State()
        state.$vocabularyData.withLock { $0 = try! StudyPersistence.encode([first, second]) }
        let store = TestStore(initialState: state) { StudyFeature() }
        var edited = second; edited.meaning = "予約する"
        let expected = try StudyPersistence.encode([first, edited])
        await store.send(.updateMeaning(second.id, "予約する")) { $0.$vocabularyData.withLock { $0 = expected } }
        #expect(store.state.vocabulary[0].meaning == "")
        #expect(store.state.vocabulary[1].meaning == "予約する")
    }

    @Test
    func testFigmaFontsAreBundledAndRegistered() {
        _ = StudyTypography.japaneseTitle(30)
        _ = StudyTypography.roundedTitle(24)
        #expect(UIFont(name: "ZenMaruGothic-Black", size: 30) != nil)
        #expect(UIFont(name: "Nunito-Black", size: 24) != nil)
    }

    @Test
    func testPracticeBandNeedsEnoughEvidenceAndUsesSkillSpecificAnchors() {
        #expect(StudyBand.objective(skill: "Reading", correct: 3, total: 3) == nil)
        #expect(StudyBand.objective(skill: "Reading", correct: 30, total: 40) == 6)
        #expect(StudyBand.objective(skill: "Listening", correct: 30, total: 40) == 7)
        #expect(StudyBand.objective(skill: "Reading", correct: 41, total: 40) == nil)
        #expect(StudyBand.cefr(6) == "B2")
        #expect(StudyBand.overall([]) == nil)
    }

    @Test
    func testAssessmentAndRecordingSurvivePersistence() throws {
        let assessment = PracticeAssessment(criteria: [
            .init(name: "Coherence", band: 6, feedback: "具体例を追加"),
            .init(name: "Pronunciation", band: nil, feedback: "音声未評価")
        ], summary: "内容の評価", improvedResponse: "An improved response.")
        let original = StudyResult(skill: "Speaking", title: "Home", correct: 0, total: 0,
            response: "I live near the park.", assessment: assessment, recordingFile: "recording.m4a", attemptID: UUID())
        let restored = try JSONDecoder().decode(StudyResult.self, from: StudyPersistence.encode(original))
        #expect(restored == original)
        #expect(restored.assessment!.isPartial)
        #expect(restored.assessment?.estimatedBand == 6)
        let legacy = Data(#"{"id":"00000000-0000-0000-0000-000000000001","date":0,"skill":"Reading","title":"Old","correct":3,"total":10,"isMock":false}"#.utf8)
        #expect(try JSONDecoder().decode(StudyResult.self, from: legacy).assessment == nil)
    }

    @Test
    func testJSONCodeFenceIsAcceptedWithoutTruncatingContent() throws {
        let data = StudyClient.jsonData("```json\n{\"title\":\"Example\"}\n```")
        #expect(try JSONSerialization.jsonObject(with: data) as? [String:String] == ["title":"Example"])
    }

    @Test
    func testFullPaperQuestionNumbersAndChoices() throws {
        let units = try ExamUnit.load()
        #expect(units.first { $0.id == "Reading / Section 2" }?.firstQuestionNumber == 14)
        #expect(units.first { $0.id == "Listening / Part 4" }?.firstQuestionNumber == 31)
        #expect(units.first { $0.id == "Reading / Section 1" }?.questions.first?.choices == ["TRUE", "FALSE", "NOT GIVEN"])
        #expect(units.first { $0.id == "Listening / Part 2" }?.questions.first?.choices == ["A", "B", "C"])
        #expect(units.flatMap(\.questions).allSatisfy { !$0.prompt.contains("\\n") })
    }

    @Test
    func testInlineOptionsPreserveSemicolonsAndRemoveDuplicateNumber() {
        let instruction = "Choose the correct letter, A, B or C. Write ONE LETTER only. A. Mill Lane Repair Morning; B. Oakfield Library; Collecting Reserved Books; C. Community Garden."
        let layout = StudyQuestionLayout(instruction)
        #expect(layout.options.map(\.label) == ["A", "B", "C"])
        #expect(layout.options[1].text == "Oakfield Library; Collecting Reserved Books")
        #expect(layout.formatted.contains("\n\nB. Oakfield"))
        let question = ReadingSet.Question(instruction: instruction, prompt: "1. 1. how to collect a reserved item", answers: ["B"], explanation: "")
        #expect(question.displayPrompt(number: 14, localNumber: 1) == "how to collect a reserved item")
        #expect(question.choiceText("B") == "B. Oakfield Library; Collecting Reserved Books")
    }

    @Test
    func testHeadingChoicesIncludeTheEntireRomanRange() {
        let labels = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii"]
        var question = ReadingSet.Question(instruction: "Write the correct Roman numeral, i–viii.", prompt: "Paragraph A", answers: ["vii"], explanation: "")
        #expect(question.choices == labels)
        question.instruction += "\n" + labels.map { $0 + ". Heading " + $0 }.joined(separator: "\n")
        #expect(question.choices == labels)
        #expect(question.choiceText("vii") == "vii. Heading vii")
        #expect(question.accepts("vii"))
    }

    @Test
    func testQuestionLayoutHandlesBundledOptionsAndPreservesOrdinaryProse() throws {
        let units = try ExamUnit.load()
        let choice = try #require(units.first { $0.id == "Listening / Part 2" }?.questions.first)
        #expect(StudyQuestionLayout(choice.prompt).options.map(\.label) == ["A", "B", "C"])
        #expect(choice.choiceText("B") == "B. Beside the fountain")
        let heading = try #require(units.first { $0.id == "Reading / Section 3" }?.questions.first)
        #expect(StudyQuestionLayout(heading.instruction).options.count == 6)
        let prose = "A library needs space. B. Smith manages it; opening times vary."
        #expect(StudyQuestionLayout(prose).formatted == prose)
        let decimal = ReadingSet.Question(instruction: "", prompt: "1.5 metres is the minimum distance.", answers: ["TRUE"], explanation: "")
        #expect(decimal.displayPrompt(number: 1, localNumber: 1) == decimal.prompt)
    }

    @Test
    func testBrandFontsLoadWithoutFallback() {
        _ = StudyTypography.body
        for name in ["ZenMaruGothic-Regular", "ZenMaruGothic-Bold", "ZenMaruGothic-Black", "Nunito-Regular", "Nunito-Bold", "Nunito-Black"] {
            #expect(UIFont(name: name, size: 17) != nil, "Bundled font must load: \(name)")
        }
    }

    @Test
    func testQuestionAnswersPreserveGapsAndDecodeLegacyHistory() throws {
        let result = StudyResult(skill: "Reading", title: "Practice", correct: 1, total: 3,
                                 questionAnswers: ["TRUE", "", "C"])
        let encoded = try StudyPersistence.encode(result)
        #expect(try JSONDecoder().decode(StudyResult.self, from: encoded).questionAnswers == ["TRUE", "", "C"])
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "questionAnswers")
        legacy["response"] = "TRUE"
        let decoded = try JSONDecoder().decode(StudyResult.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.questionAnswers == nil)
        #expect(decoded.response == "TRUE")
    }

    @Test
    func testAdditionalLocalizationsAreBundledAndSelectExplanationLanguage() throws {
        let expected = ["zh-Hans": "设置", "zh-Hant": "設定", "ko": "설정", "es": "Ajustes",
                        "pt-BR": "Ajustes", "vi": "Cài đặt", "id": "Pengaturan", "th": "การตั้งค่า",
                        "hi": "सेटिंग", "ar": "الإعدادات"]
        for (language, settings) in expected {
            let bundlePath = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: bundlePath))
            #expect(bundle.localizedString(forKey: "設定", value: nil, table: nil) == settings, "\(language)")
            #expect(StudyClient.explanationLanguage(for: language) != "English", "\(language)")
            let permission = bundle.localizedString(forKey: "NSMicrophoneUsageDescription", value: nil, table: "InfoPlist")
            #expect(permission.contains("OpenAI"), "\(language)")
            let format = bundle.localizedString(forKey: "生成・確認済み %@ / %@ セクション", value: nil, table: nil)
            let rendered = String(format: format, "1", "3")
            #expect(rendered.contains("1") && rendered.contains("3"), "\(language)")
        }
        #expect(StudyClient.explanationLanguage(for: "unknown") == "English")
    }

    @Test
    func testEnglishAndJapaneseCatalogsAreBundled() throws {
        let englishPath = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try #require(Bundle(path: englishPath))
        let japanesePath = try #require(Bundle.main.path(forResource: "ja", ofType: "lproj"))
        let japanese = try #require(Bundle(path: japanesePath))
        #expect(english.localizedString(forKey: "設定", value: nil, table: nil) == "Settings")
        #expect(japanese.localizedString(forKey: "設定", value: nil, table: nil) == "設定")
        let format = english.localizedString(forKey: "生成・確認済み %@ / %@ セクション", value: nil, table: nil)
        #expect(String(format: format, "1", "3") == "Sections ready: 1 / 3")
        #expect(english.localizedString(forKey: "NSMicrophoneUsageDescription", value: nil, table: "InfoPlist").contains("Voice conversations send audio to OpenAI"))
        #expect(english.localizedString(forKey: "音声会話を始める", value: nil, table: nil) == "Start voice conversation")
        #expect(japanese.localizedString(forKey: "音声会話を始める", value: nil, table: nil) == "音声会話を始める")
    }

    @Test
    func testCloudResetRejectsOldOfflineItemsAndPreservesNewStudy() throws {
        var phone = CloudStudyJournal(), tablet = CloudStudyJournal()
        let before = Date(timeIntervalSince1970: 100)
        let after = before.addingTimeInterval(20)
        let paper = try #require(ExamUnit.load().first)
        try tablet.capture(.init(vocabulary: [.legacy("old")], results: [
            StudyResult(skill: paper.skill, title: paper.title, correct: 1, total: 2, recordingFile: "test.m4a")
        ], papers: [paper]), at: before)
        phone.reset(at: before.addingTimeInterval(10))
        try phone.capture(.init(vocabulary: [.legacy("new")]), at: after)
        phone.merge(Array(tablet.items.values))
        tablet.merge(Array(phone.items.values))
        #expect(try phone.snapshot() == (try tablet.snapshot()))
        #expect(try tablet.snapshot().vocabulary.map(\.expression) == ["new"])
        #expect(try tablet.snapshot().results.isEmpty)
        #expect(try tablet.snapshot().papers.isEmpty)
        #expect(tablet.items.values.allSatisfy { $0.recording == nil })
    }

    @Test
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
        #expect(try phone.snapshot() == (try tablet.snapshot()))
        #expect(try phone.snapshot().vocabulary.count == 2)
        #expect(try phone.snapshot().vocabulary.first { $0.id == word.id }?.meaning == "図書館")
        let revision = phone.items.values.first { $0.kind == "word" && $0.modified == Date(timeIntervalSince1970: 3) }?.revision
        try phone.capture(phone.snapshot(), at: Date(timeIntervalSince1970: 10))
        #expect(phone.items.values.contains { $0.revision == revision })
    }

    @Test
    func testCloudJournalRoundTripPreservesAnswersPapersAndAudioReference() throws {
        let paper = try #require(ExamUnit.load().first)
        let result = StudyResult(skill: "Speaking", title: "Practice", correct: 0, total: 0, response: "I take the bus.", recordingFile: "answer.m4a", paper: paper)
        var journal = CloudStudyJournal()
        try journal.capture(.init(results: [result], papers: [paper]))
        let restored = try JSONDecoder().decode(CloudStudyJournal.self, from: StudyPersistence.encode(journal))
        #expect(try restored.snapshot().results == [result])
        #expect(try restored.snapshot().papers == [paper])
        #expect(restored.items.values.first { $0.kind == "result" }?.recording == "answer.m4a")
    }

    @Test
    func testCloudEqualTimestampMergeConvergesAndAccountsStaySeparate() throws {
        let word = SavedExpression(expression: "book", source: "Reading", sourceText: "A book.")
        var left = CloudStudyJournal(); try left.capture(.init(vocabulary: [word]))
        var first = try #require(left.items.values.first), second = first
        first.revision = "a"; second.revision = "b"
        var right = CloudStudyJournal(); right.merge([second, first]); left.merge([first, second])
        #expect(left.items == right.items)
        #expect(CloudStudyJournal.accepts(account: "A", previous: nil))
        #expect(CloudStudyJournal.accepts(account: "A", previous: "A"))
        #expect(!CloudStudyJournal.accepts(account: "B", previous: "A"))
        let folder = URL(fileURLWithPath: "/tmp/Recordings")
        #expect(CloudStudyJournal.safeRecordingURL("../secret.m4a", directory: folder) == nil)
        #expect(CloudStudyJournal.safeRecordingURL("answer.m4a", directory: folder) != nil)
    }

}


extension PocketIELTSTests {
    @Test
    func testGenerationCompletionReachesExactly100WithoutRegression() {
        for count in [0, 1, 11] {
            let from = GenerationProgress.estimate(completed: count, total: 12, elapsed: 60)
            let values = (0...100).map { GenerationProgress.finish(from: from, elapsed: Double($0) / 100) }
            #expect(values.first! == from)
            #expect(values.last! == 1)
            #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        }
        #expect(GenerationProgress.estimate(completed: 1, total: 1, elapsed: 1000) < 1)
    }
    @Test
    func testAudioChunkingPreservesScriptAndAPIRequest() throws {
        let script = String(repeating: "Speaker A: Hello. Speaker B: Good morning!\n", count: 400)
        let chunks = SpeechAudio.chunks(script)
        #expect(chunks.joined() == script)
        #expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 2800 })
        #expect(SpeechAudio.chunks(String(repeating: "a", count: 6000)).joined().count == 6000)
        let request = try SpeechAudio.request(text: chunks[0], key: "test-only-not-a-key")
        #expect(request.url?.path == "/v1/audio/speech")
        let requestBody = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: String])
        #expect(json["response_format"] == "pcm")
        #expect(json["input"] == chunks[0])
        #expect(throws: (any Error).self) { try SpeechAudio.validate(HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, data: Data()) }
    }
    @Test
    func testAudioStopRejectsLateGenerationAndResetsPlayback() async throws {
        let player = ListeningPlayer()
        let pcm = Data(repeating: 0, count: 48000)
        let wave = SpeechAudio.wave(pcm)
        let decoded = try AVAudioPlayer(data: wave)
        #expect(abs(decoded.duration - 1) <= 0.01)
        player.play(script: "Test") { _, _ in
            try? await Task.sleep(for: .milliseconds(100))
            return wave
        }
        #expect(player.generating)
        player.stop()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!player.generating)
        #expect(player.player == nil)
        player.play(script: "Test") { _, _ in wave }
        try await Task.sleep(for: .milliseconds(850))
        #expect(player.player != nil)
        player.stop()
        #expect(player.player?.isPlaying == false)
        #expect(player.player?.currentTime == 0)
    }
}

extension PocketIELTSTests {
    @Test
    func testCloudDeletionDoesNotResurrectOfflineVocabulary() throws {
        let entry = SavedExpression(expression: "ordinary", source: "Reading", sourceText: "An ordinary day.")
        var left = CloudStudyJournal(), right = CloudStudyJournal()
        try left.capture(.init(vocabulary: [entry]), at: Date(timeIntervalSince1970: 1))
        right.merge(Array(left.items.values))
        try left.capture(.init(deletedVocabulary: [.init(id: entry.id, date: Date(timeIntervalSince1970: 2))]), at: Date(timeIntervalSince1970: 2))
        left.merge(Array(right.items.values)); right.merge(Array(left.items.values))
        #expect(try left.snapshot().vocabulary.isEmpty)
        #expect(try right.snapshot().vocabulary.isEmpty)
        #expect(try right.snapshot().deletedVocabulary.map(\.id) == [entry.id])
        var relaunched = try JSONDecoder().decode(CloudStudyJournal.self, from: StudyPersistence.encode(right))
        try relaunched.capture(try right.snapshot(), at: Date(timeIntervalSince1970: 3))
        #expect(try relaunched.snapshot().vocabulary.isEmpty)
    }
}

extension PocketIELTSTests {
    @Test
    func testLicensePlistNoticesAreBundledAndReadable() throws {
        let notices = try OSSNotice.load()
        #expect(notices.count >= 17)
        #expect(notices.contains { $0.title.contains("Nunito") })
        #expect(notices.contains { $0.title.contains("swift-composable-architecture") })
        #expect(notices.allSatisfy { $0.text.count > 100 })
    }
}

extension PocketIELTSTests {
    @Test
    func testMarkdownRendersStructureAndPreservesVisibleSelectionOffsets() {
        let source = "## Meaning\n\n**Buying** means buying.\n\n- First item\n- Second item\n\n1. Example one\n2. Example two\n\n`purchase`"
        let rendered = StudyMarkdown.render(source)
        #expect(!rendered.string.contains("**"))
        #expect(!rendered.string.contains("##"))
        #expect(rendered.string.contains("•  First item"))
        #expect(rendered.string.contains("2.  Example two"))
        let range = (rendered.string as NSString).range(of: "Buying")
        #expect((rendered.string as NSString).substring(with: range) == "Buying")
        let font = rendered.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(rendered.string.contains("purchase"))
        #expect(!rendered.string.contains("`"))
    }
    @Test
    func testSavedPapersGroupByRealSkillPartNotTitle() throws {
        let papers = try ExamUnit.load()
        #expect(Set(papers.filter { $0.skill == "Reading" }.map(SavedPaperGrouping.part)) == ["Section 1", "Section 2", "Section 3"])
        #expect(Set(papers.filter { $0.skill == "Listening" }.map(SavedPaperGrouping.part)) == ["Part 1", "Part 2", "Part 3", "Part 4"])
        let paper = ExamUnit(id: "Reading / Section 1 · Section 3 of the museum", skill: "Reading", title: "Section 3 of the museum", directions: "", passages: [], questions: [], audio: nil, oral: [])
        #expect(SavedPaperGrouping.part(paper) == "Section 1")
    }
}


extension PocketIELTSTests {
    @Test
    func testDialogueAudioRemovesLabelsAndKeepsVoicesStable() throws {
        let parts = SpeechAudio.segments("Receptionist: Welcome.\nCaller: Hello!\nReceptionist: We open at 9:30.\nPlease arrive early.")
        #expect(parts.map(\.text) == ["Welcome.", "Hello!", "We open at 9:30.\nPlease arrive early."])
        #expect(parts[0].voice == parts[2].voice)
        #expect(parts[0].voice != parts[1].voice)
        let request = try SpeechAudio.request(text: parts[1].text, key: "test", voice: parts[1].voice)
        let requestBody = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: String])
        #expect(json["voice"] == parts[1].voice)
        #expect(json["input"] == "Hello!")
        #expect(SpeechAudio.segments("We open at 9:30. Bring this: your card.").first?.text == "We open at 9:30. Bring this: your card.")
        #expect(SpeechAudio.segments("**Emma:** Good morning.\n**Tom:** Hello.").map(\.text) == ["Good morning.", "Hello."])
        #expect(SpeechAudio.segments("  ").isEmpty)
    }
}

extension PocketIELTSTests {
    @Test
    func testDeleteSavedPaperPreservesHistoryVocabularyAndCanSaveAgain() async throws {
        let paper = try #require(ExamUnit.load().first)
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
        #expect(store.state.papers.isEmpty)
        #expect(store.state.records == [result])
        #expect(store.state.vocabulary == [entry])
        await store.send(.deletePaper(paper.id))
        await store.send(.savePaper(paper)) {
            $0.$deletedPaperData.withLock { $0 = try! StudyPersistence.encode([DeletedPaper]()) }
            $0.$paperData.withLock { $0 = try! StudyPersistence.encode([paper]) }
        }
        #expect(store.state.papers == [paper])
    }

    @Test
    func testDeletedSavedPaperSurvivesOfflineMergeAndExplicitResave() throws {
        let paper = try #require(ExamUnit.load().first)
        var left = CloudStudyJournal(), right = CloudStudyJournal()
        try left.capture(.init(papers: [paper]), at: Date(timeIntervalSince1970: 1))
        right.merge(Array(left.items.values))
        try left.capture(.init(deletedPapers: [.init(id: paper.id, date: Date(timeIntervalSince1970: 2))]), at: Date(timeIntervalSince1970: 2))
        try right.capture(.init(papers: [paper]), at: Date(timeIntervalSince1970: 3))
        left.merge(Array(right.items.values)); right.merge(Array(left.items.values))
        #expect(try left.snapshot().papers.isEmpty)
        #expect(try right.snapshot().papers.isEmpty)
        var relaunched = try JSONDecoder().decode(CloudStudyJournal.self, from: StudyPersistence.encode(left))
        #expect(try relaunched.snapshot().deletedPapers.map(\.id) == [paper.id])
        try relaunched.capture(.init(papers: [paper]), at: Date(timeIntervalSince1970: 4))
        right.merge(Array(relaunched.items.values))
        #expect(try right.snapshot().papers == [paper])
        #expect(try right.snapshot().deletedPapers.isEmpty)
    }
}


extension PocketIELTSTests {
    @Test
    func testBackgroundGenerationClampsProgressAndFinishes() async throws {
        var observed: BackgroundGeneration?
        let result = try await BackgroundGeneration.run(title: "Fixture", total: 3, useSystemScheduler: false) { job in
            observed = job
            job.update(completed: 2, total: 3)
            job.update(completed: 1, total: 3)
            #expect(job.completed == 2)
            job.update(completed: 9, total: 3)
            #expect(job.completed == 3)
            return 42
        }
        #expect(result == 42)
        #expect(try #require(observed).finished)
    }

    @Test
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
            Issue.record("Interrupted work must not succeed")
        } catch {
            #expect(!(error is CancellationError), "System cancellation needs an actionable retry message")
        }
        #expect(try #require(observed).finished)
        #expect(observed?.completed == 1)
    }

    @Test
    func testBackgroundGenerationPropagatesOwnerCancellation() async throws {
        var started = false
        var cancelled = false
        let task = Task {
            try await BackgroundGeneration.run(title: "Fixture", total: 1, useSystemScheduler: false) { _ in
                started = true
                do { try await Task.sleep(for: .seconds(60)) }
                catch { cancelled = true; throw error }
            }
        }
        await waitUntil { started }
        task.cancel()
        do { try await task.value; Issue.record("Expected cancellation") } catch { #expect(error is CancellationError) }
        #expect(cancelled)
    }

    @Test
    func testPausingListeningDoesNotCancelAudioGeneration() async throws {
        let player = ListeningPlayer()
        var started = false
        player.play(script: "Fixture") { _, progress in
            await progress(0, 1)
            started = true
            try await Task.sleep(for: .milliseconds(100))
            return SpeechAudio.wave(Data(repeating: 0, count: 48000))
        }
        await waitUntil { started }
        player.pause() // Called when the app resigns active.
        #expect(player.generating)
        try await Task.sleep(for: .milliseconds(850))
        #expect(player.player != nil)
        #expect(player.player?.isPlaying == false, "Returning to the app must not autoplay background-generated audio")
        player.stop() // Explicit stop / leaving the question still cancels.
        #expect(!player.generating)
    }
}


extension PocketIELTSTests {
    @Test
    func testSharedProgressDoesNotJumpWithLargePayloads() async throws {
        var displayed = 0.0
        var observed: BackgroundGeneration?
        try await BackgroundGeneration.run(title: "Fixture", total: 2, useSystemScheduler: false,
                                           onProgress: { displayed = $0 }) { job in
            observed = job
            await GenerationTransferProgress.received(10_000_000)
            #expect(job.fraction < 0.02, "Payload bytes must not push progress to 89%")
            #expect(displayed == job.fraction)
            try await Task.sleep(for: .milliseconds(250))
            #expect(job.fraction > 0)
            #expect(displayed == job.fraction)
            job.update(completed: 1, total: 2)
            #expect(abs(job.fraction - 0.5) <= 0.001)
            await GenerationTransferProgress.received(50_000_000)
            #expect(job.fraction < 0.52)
            #expect(displayed == job.fraction)
        }
        #expect(displayed == 1)
        #expect(displayed == observed?.fraction)
        #expect(GenerationTransferProgress.report == nil)
    }

    @Test
    func testSharedCompletionReaches100BeforeReturning() async throws {
        var displayed = 0.0
        var values: [Double] = []
        try await BackgroundGeneration.run(title: "Fixture", total: 1, useSystemScheduler: false,
                                           completionDuration: 0.3,
                                           onProgress: { displayed = $0; values.append($0) }) { job in
            job.update(completed: 1, total: 1)
            #expect(displayed < 1)
        }
        #expect(displayed == 1)
        #expect(values.contains { $0 > 0.1 && $0 < 1 })
        #expect(values == values.sorted())
    }
}


extension PocketIELTSTests {
    @Test
    func testListeningRewindClampsAtStartAndPreservesPause() async throws {
        let player = ListeningPlayer()
        player.rewindTenSeconds() // Safe before audio exists.
        player.play(script: "Fixture") { _, _ in
            SpeechAudio.wave(Data(repeating: 0, count: 48000 * 20))
        }
        player.pause()
        try await Task.sleep(for: .milliseconds(850))
        #expect(player.player != nil)
        player.seek(15)
        player.rewindTenSeconds()
        #expect(abs(try #require(player.player).currentTime - 5) <= 0.05)
        #expect(player.player?.isPlaying == false)
        player.rewindTenSeconds()
        #expect(player.player?.currentTime == 0)
        player.rewindTenSeconds()
        #expect(player.player?.currentTime == 0)
        player.stop()
    }
}


extension PocketIELTSTests {
    @Test
    func testQuestionVisualsPersistAndOldPapersStillDecode() throws {
        let papers = try ExamUnit.load()
        let paper = try #require(papers.first { $0.id == "Listening / Part 2" })
        #expect(paper.visuals?.count == 1)
        try QuestionVisual.validate(paper.visuals)
        #expect(try JSONDecoder().decode(ExamUnit.self, from: JSONEncoder().encode(paper)) == paper)
        #expect(QuestionVisual.context(paper.visuals).contains("Fountain"))
        #expect(papers.first { $0.id == "Listening / Part 1" }?.visuals == nil)
    }

    @Test
    func testQuestionVisualRejectsInvalidGeometryAndMissingFigure() throws {
        let paper = try #require(try ExamUnit.load().first { $0.id == "Listening / Part 2" })
        var figure = try #require(paper.visuals?.first)
        figure.elements[0].width = 200
        #expect(throws: (any Error).self) { try QuestionVisual.validate([figure]) }
        figure.elements[0].width = .infinity
        #expect(throws: (any Error).self) { try QuestionVisual.validate([figure]) }
        #expect(throws: (any Error).self) { try QuestionVisual.validate(nil, instructions: ["Label the map below."]) }
        #expect(throws: (any Error).self) { try QuestionVisual.validate([], instructions: ["Study the chart above."]) }
        try QuestionVisual.validate(nil, instructions: ["What does the speaker plan to do?"])
    }
}


extension PocketIELTSTests {
    @Test
    func testCachedListeningLoadsReadyWithoutGenerationOrAutoplay() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = "Guide: Welcome to the centre."
        let part = try #require(SpeechAudio.segments(script).first)
        try Data(repeating: 0, count: 48000).write(to: SpeechAudio.segmentURL(part, directory: folder))
        let player = ListeningPlayer(script: script, cacheDirectory: folder)
        #expect(player.player != nil, "Legacy cached segments should be ready on initialization")
        #expect(!player.generating)
        #expect(player.player?.isPlaying == false)
        #expect(player.generationFraction == 1)
        #expect(player.player?.currentTime == 0)
        let complete = SpeechAudio.completeURL(script, directory: folder)
        #expect(FileManager.default.fileExists(atPath: complete.path))
        try FileManager.default.removeItem(at: SpeechAudio.segmentURL(part, directory: folder))
        #expect(ListeningPlayer(script: script, cacheDirectory: folder).player != nil, "Complete audio remains reusable without segment files")
    }

    @Test
    func testPartialOrInvalidAudioCacheDoesNotPretendToBeReady() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = "Guide: Welcome.\nVisitor: Thank you."
        let parts = SpeechAudio.segments(script)
        try Data(repeating: 0, count: 48000).write(to: SpeechAudio.segmentURL(parts[0], directory: folder))
        #expect(SpeechAudio.cachedAudioURL(script, directory: folder) == nil)
        try Data([1]).write(to: SpeechAudio.segmentURL(parts[1], directory: folder))
        let player = ListeningPlayer(script: script, cacheDirectory: folder)
        #expect(player.player == nil)
        #expect(!player.generating)
    }
}

extension PocketIELTSTests {
    @Test
    func testReadingPlanHasMatchingBlanksAndAnswers() throws {
        let paper = try #require(try ExamUnit.load().first { $0.id == "Reading / Section 2" })
        let visual = try #require(paper.visuals?.first)
        try QuestionVisual.validate([visual], instructions: paper.questions.map(\.instruction))
        #expect(paper.questions.count == 13)
        #expect(paper.questions.prefix(3).map { $0.answers.first! } == ["reception", "changing rooms", "equipment store"])
        for number in 14...16 { #expect(visual.elements.contains { $0.label == "\(number) _____" }) }
        #expect(!visual.elements.contains { $0.label == "reception" })
        #expect(try JSONDecoder().decode(ExamUnit.self, from: JSONEncoder().encode(paper)) == paper)
    }

    @Test
    func testImageRequestAndBoundedPersistence() throws {
        var visual = try #require(try ExamUnit.load().first { $0.id == "Reading / Section 2" }?.visuals?.first)
        let request = try QuestionImage.request(visual: visual, key: "fixture-key")
        let requestBody = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        #expect(body["model"] as? String == QuestionImage.model)
        #expect(body["response_format"] == nil)
        let fixture = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }.pngData()!
        let payload = try JSONSerialization.data(withJSONObject: ["data": [["b64_json": fixture.base64EncodedString()]]])
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let bytes = try QuestionImage.decode(payload, response: response)
        #expect(bytes.count <= QuestionImage.maximumStoredBytes)
        #expect(UIImage(data: bytes) != nil)
        visual.imageData = bytes
        #expect(!QuestionVisual.context([visual]).contains("imageData"))
        #expect(try JSONDecoder().decode(QuestionVisual.self, from: JSONEncoder().encode(visual)) == visual)
        #expect(throws: (any Error).self) { try QuestionImage.decode(Data("{}".utf8), response: response) }
    }

    @Test
    func testListeningPreparationUsesPreferenceAndPlaybackCache() async throws {
        let papers = try ExamUnit.load()
        let paper = try #require(papers.first { $0.skill == "Listening" })
        let script = try #require(paper.audio)
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let reading = try #require(papers.first { $0.skill == "Reading" })
        for (unit, enabled) in [(reading, true), (paper, false)] {
            let result = try await SpeechAudio.prepare(for: unit, enabled: enabled, directory: folder) { _, _ in
                Issue.record("Unexpected audio generation"); return Data()
            }
            #expect(result == unit)
        }
        let failed = try await SpeechAudio.prepare(for: paper, enabled: true, directory: folder) { _, _ in
            throw URLError(.notConnectedToInternet)
        }
        #expect(failed.audioPreparationFailed == true)
        #expect(failed.questions == paper.questions)
        let prepared = try await SpeechAudio.prepare(for: paper, enabled: true, directory: folder) { text, _ in
            #expect(text == script)
            let wav = SpeechAudio.wave(Data(repeating: 0, count: 48000))
            try wav.write(to: SpeechAudio.completeURL(text, directory: folder))
            return wav
        }
        #expect(prepared == paper)
        _ = try await SpeechAudio.prepare(for: paper, enabled: true, directory: folder) { _, _ in
            Issue.record("Cached audio should be reused"); return Data()
        }
        #expect(ListeningPlayer(script: script, cacheDirectory: folder).player != nil)
    }

    @Test
    func testImageOptOutFallbackAndCancellation() async throws {
        let visuals = try #require(try ExamUnit.load().first { $0.id == "Reading / Section 2" }?.visuals)
        let unchanged = try await QuestionImage.prepare(visuals, enabled: false) { _ in
            Issue.record("Opt-out must not call the image API"); return Data()
        }
        #expect(unchanged == visuals)
        let failed = try await QuestionImage.prepare(visuals, enabled: true) { _ in throw URLError(.notConnectedToInternet) }
        #expect(failed?.first?.elements == visuals.first?.elements)
        #expect(failed?.first?.imageGenerationFailed == true)
        do {
            _ = try await QuestionImage.prepare(visuals, enabled: true) { _ in throw CancellationError() }
            Issue.record("Cancellation must propagate")
        } catch is CancellationError { }
    }
}


extension PocketIELTSTests {
    @Test
    func testFigureFitsPortraitLandscapeAndBoundsPan() {
        for viewport in [CGSize(width: 390, height: 700), CGSize(width: 800, height: 320)] {
            let fit = FigureViewport.fit(in: viewport)
            #expect(fit.width <= viewport.width)
            #expect(fit.height <= viewport.height)
            #expect(FigureViewport.clamp(CGSize(width: 900, height: -900), fit: fit, viewport: viewport, scale: 1) == .zero)
            let panned = FigureViewport.clamp(CGSize(width: 9000, height: -9000), fit: fit, viewport: viewport, scale: 5)
            #expect(panned.width == max(0, (fit.width * 5 - viewport.width) / 2))
        }
    }

    @Test
    func testVarietyAvoidsRecentTopicsAndPersistsHistory() async {
        let suite = "variety-tests-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let planner = ExerciseVariety(suiteName: suite)
        var topics = Set<String>()
        for _ in 0..<12 {
            let prompt = await planner.next(for: "Reading / Section 2")
            let topic = String(prompt.split(separator: ".")[0])
            #expect(topics.insert(topic).inserted)
        }
        await planner.record(title: "Fixture workplace", for: "Reading / Section 2")
        let restored = ExerciseVariety(suiteName: suite)
        let next = await restored.next(for: "Reading / Section 2")
        #expect(next.contains("Fixture workplace"))
        let writing = await restored.next(for: "Writing / Task 1")
        #expect(writing.contains("letter"))
    }
}

extension PocketIELTSTests {
    @Test
    func testReadingRepairsShortPaperWithSpecificFeedback() async throws {
        let unit = try #require(try ExamUnit.load().first { $0.id == "Reading / Section 2" })
        let valid = ReadingSet(title: unit.title, passages: unit.passages, questions: unit.questions, visuals: unit.visuals)
        #expect(StudyClient.readingIssues(valid, section: 2).isEmpty)
        var short = valid
        short.passages = ["Short passage."]
        short.questions.removeLast()
        var calls = 0
        let result = try await StudyClient.completeReading(section: 2) { input in
            calls += 1
            if calls == 2 {
                #expect(input.contains("Expected 2 passages; received 1"))
                #expect(input.contains("Expected exactly 13 questions; received 12"))
                #expect(input.contains("at least 680 passage words"))
            }
            return String(decoding: try JSONEncoder().encode(calls == 1 ? short : valid), as: UTF8.self)
        }
        #expect(calls == 2)
        #expect(result == valid)
    }

    @Test
    func testReadingRepairIsBoundedAndDoesNotRetryNetworkErrors() async {
        var calls = 0
        do {
            _ = try await StudyClient.completeReading(section: 1) { _ in calls += 1; return "{}" }
            Issue.record("Invalid papers must not be accepted")
        } catch { #expect(calls == 2) }
        calls = 0
        do {
            _ = try await StudyClient.completeReading(section: 1) { _ in calls += 1; throw URLError(.notConnectedToInternet) }
            Issue.record("Network failure must propagate")
        } catch { #expect(calls == 1) }
    }
}


@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting for the expected state", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

extension PocketIELTSTests {
    @Test
    func everyBundledListeningQuestionHasAPlayableEvidenceRow() throws {
        for part in try ExamUnit.load() where part.skill == "Listening" {
            let transcript = try #require(ListeningTranscript(part: part))
            #expect(transcript.evidence.count == part.questions.count)
            for i in part.questions.indices {
                let row = try #require(transcript.evidence[part.firstQuestionNumber + i])
                let quote = try #require(part.questions[i].evidenceQuote)
                let segment = transcript.rows[row]
                #expect([segment.speaker, segment.text].compactMap { $0 }.joined(separator: ": ").contains(quote))
            }
        }
    }

    @Test
    func listeningReviewSeeksUsingAudioLengthsAndInterTurnSilence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = "Guide: First.\nVisitor: Second.\nGuide: Third."
        let parts = SpeechAudio.segments(script)
        for (index, part) in parts.enumerated() {
            try Data(repeating: 0, count: 48000 * (index + 1)).write(to: SpeechAudio.segmentURL(part, directory: directory))
        }
        let playback = ListeningPlayer(script: script, cacheDirectory: directory)
        #expect(playback.times == [0, 1.15, 3.3])
        for part in parts { try FileManager.default.removeItem(at: SpeechAudio.segmentURL(part, directory: directory)) }
        let reopened = ListeningPlayer(script: script, cacheDirectory: directory)
        #expect(reopened.times == playback.times)
        #expect(reopened.player?.isPlaying == false)
        for row in [2, 1, 1] {
            reopened.play(script: script, row: row)
            let audio = try #require(reopened.player)
            #expect(audio.isPlaying)
            #expect(abs(audio.currentTime - [0, 1.15, 3.3][row]) < 0.1)
        }
        reopened.stop()
    }
}


extension PocketIELTSTests {
    @Test
    func listeningEvidenceLookupVerifiesTheSelectedTurn() throws {
        let rows = SpeechAudio.segments("Guide: Welcome.\nStudent: I booked for Tuesday.")
        #expect(try StudyClient.verifiedEvidence(in: #"{"row":1,"quote":"booked for Tuesday"}"#, rows: rows) == 1)
        for invalid in [#"{"row":0,"quote":"Tuesday"}"#, #"{"row":5,"quote":"Welcome"}"#, "{}"] {
            #expect(throws: (any Error).self) { try StudyClient.verifiedEvidence(in: invalid, rows: rows) }
        }
    }
}
