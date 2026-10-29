import Foundation

/// Estimates calories for food descriptions. Same OpenAI plumbing as the
/// other AI services.
struct FoodAIService {
    enum FoodAIError: LocalizedError {
        case missingKey, noResponse

        var errorDescription: String? {
            switch self {
            case .missingKey: return "No OpenAI API key is set up in the app."
            case .noResponse: return "Couldn't get a calorie estimate. Try again."
            }
        }
    }

    private let apiKey: String

    init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
    }

    /// One estimate per food, in the same order.
    func estimateCalories(_ foods: [String]) async throws -> [Double] {
        guard !apiKey.isEmpty else { throw FoodAIError.missingKey }
        guard !foods.isEmpty else { return [] }

        let list = foods.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let systemPrompt = """
        You estimate calories for foods and drinks people describe.
        Assume normal home or restaurant portions when no amount is given.
        Respond with ONLY a JSON object: { "calories": [number, number, ...] } with one whole number per item, in the same order.
        """
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": list]
            ],
            "max_tokens": 400,
            "temperature": 0.1,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let text = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "FoodAI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"])
        }

        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        struct Response: Decodable { let choices: [Choice] }
        struct Result: Decodable { let calories: [Double] }

        guard let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content,
              let json = content.data(using: .utf8),
              let result = try? JSONDecoder().decode(Result.self, from: json),
              result.calories.count == foods.count else {
            throw FoodAIError.noResponse
        }
        return result.calories.map { $0.rounded() }
    }
}
