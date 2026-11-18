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
        @Shared(.appStorage("savedExpressions")) var words: Data = Data()
        @Shared(.appStorage("readingHistory")) var history: Data = Data()
        var entries: [String] { (try? JSONDecoder().decode([String].self, from: words)) ?? [] }
        var results: [String] { (try? JSONDecoder().decode([String].self, from: history)) ?? [] }
    }

    enum Action {
        case settings(SettingsFeature.Action)
        case start(Int), loaded(ReadingSet), failed(String), finish
        case answer(Int, String), review, save(String)
        case ask(String, String), explained(String), askFailed(String), closeQuestion
    }

    @Dependency(StudyClient.self) var client
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
                let data = try? JSONEncoder().encode([result] + state.results)
                if let data { state.$history.withLock { $0 = data } }
            case let .save(expression):
                guard !state.entries.contains(expression) else { return .none }
                let data = try? JSONEncoder().encode([expression] + state.entries)
                if let data { state.$words.withLock { $0 = data } }
            case let .ask(context, question):
                state.asking = true
                state.explanation = nil
                return .run { send in
                    let answer = try await client.explain(context, question)
                    try Task.checkCancellation()
                    await send(.explained(answer))
                } catch: { error, send in
                    if !Task.isCancelled { await send(.askFailed(error.localizedDescription)) }
                }.cancellable(id: Request.tutor, cancelInFlight: true)
            case let .explained(reply), let .askFailed(reply):
                state.asking = false
                state.explanation = reply
            case .closeQuestion:
                state.asking = false
                state.explanation = nil
                return .cancel(id: Request.tutor)
            }
            return .none
        }
    }
}
