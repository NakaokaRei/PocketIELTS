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

    private static func request(instructions: String, input: String, json: Bool) async throws -> String {
        guard let key = try KeyStore.read() else { throw StudyError.message("設定でAPIキーを入力してください。") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["model":"gpt-4.1-mini", "instructions":instructions, "input":input,
                                   "store":false, "max_output_tokens":json ? 10000 : 1500]
        if json { body["text"] = ["format":["type":"json_object"]] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: throw StudyError.message("APIキーまたはモデルの利用権限を設定で確認してください。")
        case 429: throw StudyError.message("APIの利用上限に達しました。利用枠を確認してから再試行してください。")
        default: throw StudyError.message("OpenAIへのリクエストに失敗しました。時間をおいて再試行してください。")
        }
        struct Reply: Decodable {
            struct Item: Decodable {
                struct Content: Decodable { var type: String; var text: String? }
                var content: [Content]?
            }
            var status: String
            var output: [Item]
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        let result = reply.output.flatMap { $0.content ?? [] }.filter { $0.type == "output_text" }.compactMap(\.text).joined()
        guard reply.status == "completed", !result.isEmpty else { throw StudyError.message("応答が途中で終了しました。もう一度お試しください。") }
        return result
    }
}
