import XCTest
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

}
