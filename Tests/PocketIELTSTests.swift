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

    func testSettingsTrimsKeyAndReportsRemoval() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0[CredentialClient.self] = CredentialClient(
                isConfigured: { false },
                save: { XCTAssertEqual($0, "sample") },
                remove: {}
            )
        }
        await store.send(.opened)
        await store.send(.save("  "))
        await store.send(.save(" sample\n")) {
            $0.configured = true
            $0.didSave = true
        }
        await store.send(.remove) {
            $0.configured = false
            $0.didSave = false
        }
    }

    func testFailedReplacementDoesNotReportSuccess() async {
        var state = SettingsFeature.State()
        state.configured = true
        state.didSave = true
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0[CredentialClient.self].save = { _ in throw StudyError.message("Save failed") }
        }
        await store.send(.save("replacement")) {
            $0.didSave = false
            $0.error = "Save failed"
        }
    }

    func testReadingSessionLoadsGradesOnceAndFinishes() async {
        let question = ReadingSet.Question(instruction: "Write one word.", prompt: "When?",
                                           answers: ["Monday"], explanation: "Opening day")
        let paper = ReadingSet(title: "Opening hours", passages: ["We open on Monday."], questions: [question])
        let store = TestStore(initialState: StudyFeature.State()) {
            StudyFeature()
        } withDependencies: {
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
        let history = try! JSONEncoder().encode(["Section 2 · Opening hours · 1/1"])
        await store.send(.review) {
            $0.reviewed = true
            $0.$history.withLock { $0 = history }
        }
        await store.send(.review)
        await store.send(.answer(0, "Tuesday"))
        await store.send(.finish) {
            $0.reviewed = false
            $0.session = nil
            $0.answers = [:]
        }
    }
}
