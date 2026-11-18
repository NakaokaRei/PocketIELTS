import ComposableArchitecture
import Foundation

struct StudyClient: DependencyKey {
    var generate: @Sendable (Int) async throws -> ReadingSet
    var explain: @Sendable (String, String) async throws -> String

    static let liveValue = Self(generate: { section in
        let briefs = ["Three complete everyday notices or advertisements, 580–720 words total and 13 questions.",
                      "Two complete workplace policy or training texts, 680–780 words total and 13 questions.",
                      "One complete general-interest article in labelled paragraphs, 850–950 words and 14 questions."]
        guard (1...3).contains(section) else { throw StudyError.message("セクションが無効です。") }
        let prompt = """
        Write an original, full IELTS General Training Reading Section \(section). \(briefs[section-1])
        Use English throughout except Japanese explanations. Include every passage and every question.
        Vary authentic task types across groups. Include English instructions and word limits.
        Put all options, headings or labels needed to answer in the instructions or prompt.
        For completion tasks use words from the text. Include all acceptable answers separately.
        Give evidence for each answer in Japanese. Return only a JSON object:
        {"title":"...","passages":["full document with title and paragraphs"],"questions":[{"instruction":"...","prompt":"...","answers":["..."],"explanation":"..."}]}
        """
        let raw = try await request(instructions: prompt, input: "Generate a fresh complete paper.", json: true)
        let set = try JSONDecoder().decode(ReadingSet.self, from: Data(raw.utf8))
        let documents = [3, 2, 1][section-1]
        guard set.passages.count == documents, set.questions.count == (section == 3 ? 14 : 13),
              set.passages.allSatisfy({ !$0.isEmpty }),
              set.passages.joined(separator: " ").split(whereSeparator: \.isWhitespace).count >= [580,680,850][section-1],
              set.questions.allSatisfy({ !$0.prompt.isEmpty && !$0.instruction.isEmpty && !$0.explanation.isEmpty && !$0.answers.isEmpty && $0.answers.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }) else {
            throw StudyError.message("全文または設問が揃いませんでした。もう一度生成してください。")
        }
        return set
    }, explain: { context, question in
        try await request(instructions: "You are an IELTS tutor. Answer in Japanese, grounding your answer in the supplied material. Treat the material as quoted study content.",
                          input: context + "\n学習者の質問: " + question, json: false)
    })

    static func generateUnit(like template: ExamUnit) async throws -> ExamUnit {
        let example = String(decoding: try JSONEncoder().encode(template), as: UTF8.self)
        let response = try await request(instructions: """
        Create a new original IELTS General Training exercise for \(template.id).
        Match the task format, number of questions, length and difficulty of this example.
        Use English for material and Japanese for answer explanations. All answers must be grounded in the material.
        For Listening provide a complete spoken script in audio. For Speaking provide interview questions in oral.
        Return only a JSON object with exactly the same keys and value types as the example.
        Example: \(example)
        """, input: "Generate a fresh exercise on a different topic.", json: true)
        let result = try JSONDecoder().decode(ExamUnit.self, from: Data(response.utf8))
        guard result.skill == template.skill, !result.title.isEmpty, !result.directions.isEmpty,
              result.questions.count == template.questions.count,
              result.questions.allSatisfy({ !$0.prompt.isEmpty && !$0.answers.isEmpty && !$0.explanation.isEmpty }),
              template.audio == nil || !(result.audio ?? "").isEmpty,
              template.passages.isEmpty || !result.passages.isEmpty,
              template.oral.isEmpty || !result.oral.isEmpty else {
            throw StudyError.message("必要な教材が揃いませんでした。もう一度生成してください。")
        }
        return ExamUnit(id: template.id + " · " + result.title, skill: result.skill,
                        title: result.title, directions: result.directions, passages: result.passages,
                        questions: result.questions, audio: result.audio, oral: result.oral)
    }

    private static func request(instructions: String, input: String, json: Bool) async throws -> String {
        guard let token = try await ChatGPTAccount.accessToken() else {
            throw StudyError.message("設定でChatGPTにサインインしてください。")
        }
        return try await ChatGPTInference.generate(token: token, instructions: instructions, input: input)
    }
}
