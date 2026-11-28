import Foundation
import CryptoKit

struct ReadingSet: Codable, Equatable, Sendable {
    var title: String
    var passages: [String]
    var questions: [Question]
    var visuals: [QuestionVisual]? = nil

    mutating func shuffleParagraphMatchingQuestions() {
        var start = questions.startIndex
        while start < questions.endIndex {
            let instruction = questions[start].instruction
            let group = questions[start...].prefix { $0.instruction == instruction }
            let end = group.endIndex
            defer { start = end }
            guard group.count > 1, instruction.localizedCaseInsensitiveContains("which paragraph"),
                  group.allSatisfy({ $0.answers.count == 1 && $0.answers[0].wholeMatch(of: #/[A-Z]/#) != nil }) else { continue }

            var shuffled = group.shuffled()
            let letters = shuffled.map { $0.answers[0] }
            // A random permutation can still give away the answers in passage order.
            if letters == letters.sorted(), letters.first != letters.last {
                shuffled.swapAt(0, shuffled.count - 1)
            }
            questions.replaceSubrange(start..<end, with: shuffled)
        }
    }

    struct Question: Codable, Equatable, Sendable {
        var instruction: String
        var prompt: String
        var answers: [String]
        var explanation: String
        var evidenceQuote: String? = nil
        var choices: [String] {
            let value = instruction.uppercased()
            if value.contains("TRUE"), value.contains("FALSE"), value.contains("NOT GIVEN") { return ["TRUE", "FALSE", "NOT GIVEN"] }
            if value.contains("YES"), value.contains("NO"), value.contains("NOT GIVEN") { return ["YES", "NO", "NOT GIVEN"] }
            let options = StudyQuestionLayout(instruction).options + StudyQuestionLayout(prompt).options
            if !options.isEmpty { return Array(NSOrderedSet(array: options.map(\.label))) as? [String] ?? [] }
            if value.contains("CORRECT LETTER, A, B OR C") { return ["A", "B", "C"] }
            if let range = value.firstMatch(of: #/\bI\s*[-–—]\s*([IVX]+)\b/#),
               let last = StudyQuestionLayout.roman.firstIndex(of: range.1.lowercased()) {
                return Array(StudyQuestionLayout.roman[...last])
            }
            return []
        }
        func displayPrompt(number: Int, localNumber: Int) -> String {
            var result = StudyQuestionLayout(prompt).body
            for _ in 0..<2 {
                guard let range = result.range(of: #"^\s*(?:Question\s+)?(\d+)[.):]\s+"#, options: .regularExpression),
                      let value = result[range].split(whereSeparator: { !$0.isNumber }).first,
                      [number, localNumber].contains(Int(value) ?? -1) else { break }
                result.removeSubrange(range)
            }
            return result
        }
        func choiceText(_ label: String) -> String {
            let options = StudyQuestionLayout(prompt).options + StudyQuestionLayout(instruction).options
            return options.first { $0.label == label }.map { label + ". " + $0.text } ?? label
        }
        func accepts(_ input: String) -> Bool {
            func normal(_ value: String) -> String {
                let text = value.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if let time = text.wholeMatch(of: #/(0?[1-9]|1[0-2])[:.]([0-5][0-9]) ?([ap])\.?m\.?/#) {
                    return "\(time.1.drop(while: { $0 == "0" })):\(time.2) \(time.3)m"
                }
                return text
            }
            let response = normal(input)
            return answers.contains { normal($0) == response }
        }
    }
}

struct SavedExpression: Codable, Equatable, Identifiable {
    var id = UUID()
    var expression: String
    var source: String
    var sourceText: String
    var meaning = ""
    var meaningLanguage: String? = nil
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
    var markedExpressions: [SelectableStudyText.Entry]?
    var questionAnswers: [String]?

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
    var criterionMean: Double? {
        let scores = criteria.compactMap(\.band)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
    var estimatedBand: Double? { criterionMean.map { ($0 * 2).rounded() / 2 } }
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
            guard let score = result.assessment?.criterionMean else { return nil }
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
        switch band { case 8.5...: return "C2"; case 7...: return "C1"; case 5.5...: return "B2"; case 4...: return "B1"; default: return String(localized: "B1未満") }
    }
    static func label(_ band: Double?) -> String { band.map { String(format: "%.1f", $0) } ?? String(localized: "判定中") }
}

/// Recognizes a complete, sequential option list, preserving punctuation inside each option.
/// Plain prose is left unchanged when it does not contain at least A/B or i/ii.
struct StudyQuestionLayout {
    struct Option { let label, text: String }
    let body: String
    let options: [Option]
    var formatted: String {
        ([body] + options.map { $0.label + ". " + $0.text }).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    static let roman = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii", "xiii", "xiv", "xv"]
    init(_ text: String) {
        let pattern = #"(?m)(?:^|\n|[ \t]{2,}|(?<=[;.!?])[ \t]+)([A-H]|[ivx]{1,5})([.)])?[ \t]+"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        let labels = matches.map { source.substring(with: $0.range(at: 1)) }
        let punctuationCount = matches.filter { $0.range(at: 2).location != NSNotFound }.count
        let consistentMarkers = punctuationCount == 0 || punctuationCount == matches.count
        let separatedBareMarkers = punctuationCount > 0 || matches.dropFirst().allSatisfy { match in
            let prefix = source.substring(with: NSRange(location: match.range.location,
                length: match.range(at: 1).location - match.range.location))
            return prefix.contains("\n") || prefix.count >= 2
        }
        let alphabet = ["A", "B", "C", "D", "E", "F", "G", "H"]
        guard labels.count >= 2, consistentMarkers, separatedBareMarkers,
              labels == Array(alphabet.prefix(labels.count)) || labels == Array(Self.roman.prefix(labels.count)) else {
            body = text; options = []; return
        }
        body = source.substring(to: matches[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        options = matches.enumerated().map { index, match in
            let start = NSMaxRange(match.range)
            let end = index + 1 < matches.count ? matches[index + 1].range.location : source.length
            return Option(label: labels[index], text: source.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";"))))
        }
    }
}
