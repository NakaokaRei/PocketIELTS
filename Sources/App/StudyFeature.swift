import ComposableArchitecture
import Foundation

@Reducer
struct StudyFeature {
    @ObservableState
    struct State: Equatable {
        var settings = SettingsFeature.State()
        var section = 1
        var session: ReadingSet?
        var answers: [Int: String] = [:]
        var reviewed = false
        var loading = false
        var error: String?
        var explanation: String?
        var asking = false
        var messages: [TutorMessage] = []
        @Shared(.appStorage("vocabularyDetails")) var vocabularyData = Data()
        @Shared(.appStorage("studyResults")) var resultData = Data()
        @Shared(.appStorage("savedPapers")) var paperData = Data()
        var vocabulary: [SavedExpression] {
            let details = (try? JSONDecoder().decode([SavedExpression].self, from: vocabularyData)) ?? []
            return details + entries.filter { word in !details.contains { $0.expression == word } }
                .map(SavedExpression.legacy)
        }
        var records: [StudyResult] { (try? JSONDecoder().decode([StudyResult].self, from: resultData)) ?? [] }
        var papers: [ExamUnit] { (try? JSONDecoder().decode([ExamUnit].self, from: paperData)) ?? [] }
        @Shared(.appStorage("savedExpressions")) var words: Data = Data()
        @Shared(.appStorage("readingHistory")) var history: Data = Data()
        var entries: [String] { (try? JSONDecoder().decode([String].self, from: words)) ?? [] }
        var results: [String] { (try? JSONDecoder().decode([String].self, from: history)) ?? [] }
    }

    enum Action {
        case settings(SettingsFeature.Action)
        case start(Int), loaded(ReadingSet), failed(String), finish
        case answer(Int, String), review, save(String)
        case saveExpression(SavedExpression), savePaper(ExamUnit), record(StudyResult)
        case updateMeaning(UUID, String)
        case updateAssessment(UUID, PracticeAssessment)
        case ask(String, String), explained(String), askFailed(String), closeQuestion
    }

    @Dependency(StudyClient.self) var client
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now
    private enum Request { case generation, tutor }

    var body: some ReducerOf<Self> {
        Scope(state: \.settings, action: \.settings) { SettingsFeature() }
        Reduce { state, action in
            switch action {
            case .settings: break
            case let .start(section):
                state.section = section
                state.loading = true
                state.error = nil
                return .run { send in
                    let result = try await client.generate(section)
                    try Task.checkCancellation()
                    await send(.loaded(result))
                } catch: { error, send in
                    if !Task.isCancelled { await send(.failed(error.localizedDescription)) }
                }.cancellable(id: Request.generation, cancelInFlight: true)
            case let .loaded(set):
                state.session = set
                state.loading = false
                state.answers = [:]
                state.reviewed = false
            case let .failed(message):
                state.loading = false
                state.error = message
            case .finish:
                state.messages = []
                state.session = nil
                state.answers = [:]
                state.reviewed = false
                state.loading = false
                state.asking = false
                state.explanation = nil
                state.error = nil
                return .merge(.cancel(id: Request.generation), .cancel(id: Request.tutor))
            case let .answer(index, value):
                if !state.reviewed { state.answers[index] = value }
            case .review:
                guard let set = state.session, !state.reviewed else { return .none }
                state.reviewed = true
                let correct = set.questions.enumerated().filter { $0.element.accepts(state.answers[$0.offset] ?? "") }.count
                let result = "Section \(state.section) · \(set.title) · \(correct)/\(set.questions.count)"
                let data = try? StudyPersistence.encode([result] + state.results)
                if let data { state.$history.withLock { $0 = data } }
                let record = StudyResult(id: uuid(), date: now, skill: "Reading", title: set.title, correct: correct, total: set.questions.count)
                if let data = try? StudyPersistence.encode([record] + state.records) { state.$resultData.withLock { $0 = data } }
            case let .saveExpression(entry):
                var entries = state.vocabulary
                if let index = entries.firstIndex(where: { $0.expression == entry.expression && $0.source == entry.source }) {
                    entries[index].sourceText = entry.sourceText
                    entries[index].paper = entry.paper ?? entries[index].paper
                    entries[index].sourceID = entry.sourceID
                    entries[index].selectionLocation = entry.selectionLocation
                    entries[index].selectionLength = entry.selectionLength
                    if !entry.meaning.isEmpty { entries[index].meaning = entry.meaning }
                } else { entries.insert(entry, at: 0) }
                if let data = try? StudyPersistence.encode(entries) { state.$vocabularyData.withLock { $0 = data } }
            case let .updateMeaning(id, meaning):
                var entries = state.vocabulary
                for i in entries.indices where entries[i].id == id { entries[i].meaning = meaning }
                if let data = try? StudyPersistence.encode(entries) { state.$vocabularyData.withLock { $0 = data } }
            case let .savePaper(paper):
                guard !state.papers.contains(where: { $0.id == paper.id }) else { return .none }
                if let data = try? StudyPersistence.encode([paper] + state.papers) { state.$paperData.withLock { $0 = data } }
            case let .updateAssessment(id, assessment):
                var records = state.records
                guard let index = records.firstIndex(where: { $0.id == id }) else { return .none }
                records[index].assessment = assessment
                if let data = try? StudyPersistence.encode(records) { state.$resultData.withLock { $0 = data } }
            case let .record(result):
                guard !state.records.contains(where: { $0.id == result.id }) else { return .none }
                if let data = try? StudyPersistence.encode([result] + state.records) { state.$resultData.withLock { $0 = data } }
            case let .save(expression):
                guard !state.entries.contains(expression) else { return .none }
                let data = try? StudyPersistence.encode([expression] + state.entries)
                if let data { state.$words.withLock { $0 = data } }
            case let .ask(context, question):
                guard !state.asking else { return .none }
                let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !question.isEmpty else { return .none }
                let conversation = state.messages.map { ($0.isUser ? "学習者: " : "チューター: ") + $0.text }.joined(separator: "\n")
                state.messages.append(TutorMessage(isUser: true, text: question))
                state.asking = true
                state.explanation = nil
                return .run { send in
                    let answer = try await client.explain(context + "\nこれまでの会話:\n" + conversation, question)
                    try Task.checkCancellation()
                    await send(.explained(answer))
                } catch: { error, send in
                    if !Task.isCancelled { await send(.askFailed(error.localizedDescription)) }
                }.cancellable(id: Request.tutor, cancelInFlight: true)
            case let .explained(reply):
                state.messages.append(TutorMessage(isUser: false, text: reply))
                state.asking = false
                state.explanation = reply
            case let .askFailed(reply):
                state.asking = false
                state.explanation = reply
            case .closeQuestion:
                state.messages = []
                state.asking = false
                state.explanation = nil
                return .cancel(id: Request.tutor)
            }
            return .none
        }
    }
}
