import Foundation

struct GeneratedQuote {
    let text: String
    let chapterNumber: Int?
    let chapterName: String?
}

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

    func generateQuotes(bookTitle: String, author: String, existingQuotes: [String], count: Int = 25) async throws -> [GeneratedQuote] {
        let existingList = existingQuotes.isEmpty
            ? "None"
            : existingQuotes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let systemPrompt = """
        You are a literary quote expert. Generate exactly \(count) meaningful, inspiring quotes from the book "\(bookTitle)" by \(author).

        Rules:
        - Return ONLY a valid JSON array of objects, nothing else — no explanation, no preamble
        - Each object must have exactly these keys: "text", "chapterNumber", "chapterName"
        - "text": the quote (1–3 sentences, do NOT include attribution)
        - "chapterNumber": the integer chapter number where this quote appears (e.g. 3)
        - "chapterName": the name of that chapter as a string (e.g. "The Road Ahead")
        - Quotes should be insightful, authentic to the book's themes and style
        - Do NOT repeat any of the existing quotes listed below
        - Spread quotes across different chapters

        Existing quotes to avoid repeating:
        \(existingList)

        Return format (JSON array of objects only):
        [{"text": "...", "chapterNumber": 1, "chapterName": "..."}, ...]
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Generate \(count) quotes for \"\(bookTitle)\" by \(author)."]
        ]

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 3000,
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

    private func parseQuotesArray(from text: String, existingQuotes: [String]) throws -> [GeneratedQuote] {
        guard let startIdx = text.firstIndex(of: "["),
              let endIdx = text.lastIndex(of: "]") else {
            throw OpenAIError.invalidResponse
        }

        let jsonString = String(text[startIdx...endIdx])
        guard let data = jsonString.data(using: .utf8) else {
            throw OpenAIError.invalidResponse
        }

        let raw = try JSONDecoder().decode([[String: JSONValue]].self, from: data)
        let normalised = existingQuotes.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }

        return raw.compactMap { obj -> GeneratedQuote? in
            guard case .string(let quoteText) = obj["text"] else { return nil }
            let trimmed = quoteText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !normalised.contains(trimmed.lowercased()) else { return nil }

            var chapterNum: Int?
            if case .int(let n) = obj["chapterNumber"] { chapterNum = n }
            else if case .double(let d) = obj["chapterNumber"] { chapterNum = Int(d) }

            var chapterTitle: String?
            if case .string(let s) = obj["chapterName"], !s.isEmpty { chapterTitle = s }

            return GeneratedQuote(text: trimmed, chapterNumber: chapterNum, chapterName: chapterTitle)
        }
    }
}

// Minimal JSON value type for flexible decoding
enum JSONValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Int.self)    { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode(Bool.self)   { self = .bool(v); return }
        self = .null
    }
}
