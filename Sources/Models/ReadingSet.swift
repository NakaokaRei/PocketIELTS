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
