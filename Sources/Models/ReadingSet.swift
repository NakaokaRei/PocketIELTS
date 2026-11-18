import Foundation
import CryptoKit

struct ReadingSet: Codable, Equatable, Sendable {
    var title: String
    var passages: [String]
    var questions: [Question]

    struct Question: Codable, Equatable, Sendable {
        var instruction: String
        var prompt: String
        var answers: [String]
        var explanation: String
        var choices: [String] {
            let value = instruction.uppercased()
            if value.contains("TRUE"), value.contains("FALSE"), value.contains("NOT GIVEN") { return ["TRUE", "FALSE", "NOT GIVEN"] }
            if value.contains("YES"), value.contains("NO"), value.contains("NOT GIVEN") { return ["YES", "NO", "NOT GIVEN"] }
            if value.contains("CORRECT LETTER, A, B OR C") { return ["A", "B", "C"] }
            if value.contains("I–VI") || value.contains("I-VI") { return ["i", "ii", "iii", "iv", "v", "vi"] }
            return []
        }
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
    var sourceID: String?
    var selectionLocation: Int?
    var selectionLength: Int?
    var contextExcerpt: String {
        StudyTextSelection.excerpt(sourceText, range: selectionLocation.flatMap { location in
            selectionLength.map { NSRange(location: location, length: $0) }
        }, expression: expression)
    }
    static func legacy(_ word: String) -> Self {
        let bytes = Array(SHA256.hash(data: Data(word.utf8)).prefix(16))
        let id = UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        return Self(id: id, expression: word, source: "Reading", sourceText: "")
    }
}

struct StudyResult: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var skill: String
    var title: String
    var correct: Int
    var total: Int
    var isMock = false
    var response: String?
    var assessment: PracticeAssessment?
    var recordingFile: String?
    var paper: ExamUnit?
    var attemptID: UUID?

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

/// UTF-16 offsets match UITextView selection, including emoji and non-Latin text.
enum StudyTextSelection {
    static func excerpt(_ text: String, range: NSRange?, expression: String) -> String {
        let selected = range ?? (text as NSString).range(of: expression)
        guard selected.location != NSNotFound, Range(selected, in: text) != nil else { return text }
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, sentenceRange, _, _ in
            if NSIntersectionRange(NSRange(sentenceRange, in: text), selected).length > 0, let sentence {
                sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return sentences.isEmpty ? text : sentences.joined(separator: " ")
    }
}

struct PracticeAssessment: Codable, Equatable, Sendable {
    struct Criterion: Codable, Equatable, Sendable {
        var name: String
        var band: Double?
        var feedback: String
    }
    var criteria: [Criterion]
    var summary: String
    var improvedResponse: String
    var estimatedBand: Double? {
        let scores = criteria.compactMap(\.band)
        guard !scores.isEmpty else { return nil }
        return (scores.reduce(0, +) / Double(scores.count) * 2).rounded() / 2
    }
    var isPartial: Bool { criteria.contains { $0.band == nil } }
}

/// Practice estimates; the full official test uses equated forms and examiner judgement.
/// Anchors: https://ielts.org/take-a-test/your-results/ielts-scoring-in-detail
/// CEFR: https://ielts.org/news-and-insights/finding-the-right-english-proficiency-test-for-you
enum StudyBand {
    static func objective(skill: String, correct: Int, total: Int) -> Double? {
        guard total >= 10, correct >= 0, correct <= total, ["Reading", "Listening"].contains(skill) else { return nil }
        let raw = Double(correct) / Double(total) * 40
        let anchors: [(Double, Double)] = skill == "Reading"
            ? [(0,0),(15,4),(23,5),(30,6),(35,7),(38,8),(40,9)]
            : [(0,0),(16,5),(23,6),(30,7),(35,8),(40,9)]
        for i in 1..<anchors.count where raw <= anchors[i].0 {
            let low = anchors[i-1], high = anchors[i]
            let value = low.1 + (raw-low.0)/(high.0-low.0)*(high.1-low.1)
            return (value * 2).rounded() / 2
        }
        return 9
    }
    static func skill(_ skill: String, records: [StudyResult]) -> Double? {
        let recent = Array(records.filter { $0.skill == skill }.prefix(12))
        if skill == "Reading" || skill == "Listening" {
            return objective(skill: skill, correct: recent.reduce(0) { $0 + $1.correct }, total: recent.reduce(0) { $0 + $1.total })
        }
        let assessed = recent.compactMap { result -> (Double, Double)? in
            guard let score = result.assessment?.estimatedBand else { return nil }
            return (score, skill == "Writing" && result.paper?.id.contains("Task 2") == true ? 2 : 1)
        }
        guard !assessed.isEmpty else { return nil }
        return (assessed.reduce(0) { $0 + $1.0 * $1.1 } / assessed.reduce(0) { $0 + $1.1 } * 2).rounded() / 2
    }
    static func overall(_ records: [StudyResult]) -> Double? {
        let bands = ["Reading","Listening","Writing","Speaking"].compactMap { skill($0, records: records) }
        guard bands.count == 4 else { return nil }
        return (bands.reduce(0,+) / 4 * 2).rounded() / 2
    }
    static func cefr(_ band: Double?) -> String {
        guard let band else { return "—" }
        switch band { case 8.5...: return "C2"; case 7...: return "C1"; case 5.5...: return "B2"; case 4...: return "B1"; default: return "B1未満" }
    }
    static func label(_ band: Double?) -> String { band.map { String(format: "%.1f", $0) } ?? "判定中" }
}
