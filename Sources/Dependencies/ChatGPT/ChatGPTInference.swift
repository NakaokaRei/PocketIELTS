import Foundation

enum ChatGPTInference {
    struct ModelCatalog: Decodable {
        struct Model: Decodable { var slug: String; var visibility: String }
        var models: [Model]
    }
    struct Event: Decodable {
        var type: String
        var delta: String?
    }

    static func generate(token: String, instructions: String, input: String) async throws -> String {
        var modelsRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        modelsRequest.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: modelsRequest)
        try check(response)
        let catalog = try JSONDecoder().decode(ModelCatalog.self, from: data)
        guard let model = catalog.models.first(where: { $0.visibility == "list" }) else {
            throw StudyError.message("このChatGPTアカウントで利用できるモデルがありません。")
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model.slug, "instructions": instructions, "input": [["role":"user", "content":input]],
            "stream":true, "store":false
        ])
        let (stream, status) = try await URLSession.shared.bytes(for: request)
        try check(status)
        var text = ""
        for try await line in stream.lines where line.hasPrefix("data:") {
            try Task.checkCancellation()
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            let event = try JSONDecoder().decode(Event.self, from: Data(payload.utf8))
            switch event.type {
            case "response.output_text.delta": text += event.delta ?? ""
            case "response.completed" where !text.isEmpty: return text
            case "response.failed", "error": throw StudyError.message("応答を生成できませんでした。ChatGPTの利用枠と接続状態を確認してください。")
            case "response.incomplete": throw StudyError.message("応答が途中で終了しました。")
            default: continue
            }
        }
        throw StudyError.message("完全な応答を受信できませんでした。")
    }
    private static func check(_ response: URLResponse) throws {
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return
        case 401, 403: throw StudyError.message("設定でChatGPTに再接続してください。")
        case 429: throw StudyError.message("ChatGPTの利用上限に達しました。")
        default: throw StudyError.message("ChatGPTに接続できませんでした。")
        }
    }
}
