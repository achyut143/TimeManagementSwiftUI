import Foundation

class BookQuoteService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init() {
        if let path = Bundle.main.path(forResource: "Config", ofType: "xcconfig"),
           let contents = try? String(contentsOfFile: path),
           let keyLine = contents.components(separatedBy: .newlines).first(where: { $0.contains("OPENAI_API_KEY") }) {
            let key = keyLine.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) ?? ""
            self.apiKey = key
        } else {
            self.apiKey = ""
        }
    }

    func generateQuotes(bookTitle: String, author: String, existingQuotes: [String], count: Int = 25) async throws -> [String] {
        let existingList = existingQuotes.isEmpty
            ? "None"
            : existingQuotes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let systemPrompt = """
        You are a literary quote expert. Generate exactly \(count) meaningful, inspiring quotes that capture the themes, wisdom, and spirit of the book "\(bookTitle)" by \(author).

        Rules:
        - Return ONLY a valid JSON array of strings, nothing else — no explanation, no preamble
        - Each quote should be insightful, thought-provoking, or inspiring
        - Quotes should feel authentic to the book's themes and style
        - Do NOT repeat any of the existing quotes listed below
        - Do NOT include attribution text (like "— Author") inside the quote strings
        - Each quote should be 1–3 sentences maximum

        Existing quotes to avoid repeating:
        \(existingList)

        Return format (JSON array only):
        ["quote 1", "quote 2", "quote 3", ...]
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Generate \(count) quotes for \"\(bookTitle)\" by \(author)."]
        ]

        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": messages,
            "max_tokens": 2000,
            "temperature": 0.0
        ]

        guard let url = URL(string: baseURL) else { throw OpenAIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        guard let content = response.choices.first?.message.content else {
            throw OpenAIError.noResponse
        }

        return try parseQuotesArray(from: content, existingQuotes: existingQuotes)
    }

    private func parseQuotesArray(from text: String, existingQuotes: [String]) throws -> [String] {
        guard let startIdx = text.firstIndex(of: "["),
              let endIdx = text.lastIndex(of: "]") else {
            throw OpenAIError.invalidResponse
        }

        let jsonString = String(text[startIdx...endIdx])
        guard let data = jsonString.data(using: .utf8) else {
            throw OpenAIError.invalidResponse
        }

        let allQuotes = try JSONDecoder().decode([String].self, from: data)
        let normalised = existingQuotes.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }

        return allQuotes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !normalised.contains($0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
