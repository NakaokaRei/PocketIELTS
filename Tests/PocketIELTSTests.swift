import XCTest
import UIKit
import ComposableArchitecture
@testable import PocketIELTS

@MainActor
final class PocketIELTSTests: XCTestCase {
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
                                     skill: "Reading", title: "Opening hours", correct: 1, total: 1)
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

    func testEnglishAndJapaneseCatalogsAreBundled() throws {
        let english = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))))
        let japanese = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: "ja", ofType: "lproj"))))
        XCTAssertEqual(english.localizedString(forKey: "設定", value: nil, table: nil), "Settings")
        XCTAssertEqual(japanese.localizedString(forKey: "設定", value: nil, table: nil), "設定")
        let format = english.localizedString(forKey: "生成・確認済み %@ / %@ セクション", value: nil, table: nil)
        XCTAssertEqual(String(format: format, "1", "3"), "Sections ready: 1 / 3")
        XCTAssertTrue(english.localizedString(forKey: "NSMicrophoneUsageDescription", value: nil, table: "InfoPlist").contains("Record"))
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
