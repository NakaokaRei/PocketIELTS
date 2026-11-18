import Foundation

struct ReadingSet: Codable, Equatable, Sendable {
    var title: String
    var passages: [String]
    var questions: [Question]

    struct Question: Codable, Equatable, Sendable {
        var instruction: String
        var prompt: String
        var answers: [String]
        var explanation: String
        func accepts(_ input: String) -> Bool {
            func normal(_ value: String) -> String {
                value.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            return answers.contains { normal($0) == normal(input) }
        }
    }
}

struct SavedExpression: Codable, Equatable, Identifiable {
    var id = UUID()
    var expression: String
    var source: String
    var sourceText: String
    var meaning = ""
    var paper: ExamUnit?
}

struct StudyResult: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var skill: String
    var title: String
    var correct: Int
    var total: Int
    var isMock = false
}

struct TutorMessage: Equatable, Identifiable {
    var id = UUID()
    var isUser: Bool
    var text: String
}

/// Stable bytes avoid unnecessary Shared state updates when a saved value is unchanged.
enum StudyPersistence {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
