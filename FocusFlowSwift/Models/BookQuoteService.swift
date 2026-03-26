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
        self.apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
    }

    func generateQuotes(bookTitle: String, author: String, existingQuotes: [String], count: Int = 25) async throws -> [GeneratedQuote] {
        let existingList = existingQuotes.isEmpty
            ? "None"
            : existingQuotes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let systemPrompt = """
        You are a book insights expert. For the book "\(bookTitle)" by \(author), generate exactly \(count) key ideas and insights paraphrased in the author's voice and style. These should faithfully represent the book's actual arguments, lessons, and themes — not invented content.

        Rules:
        - Return ONLY a valid JSON array of objects, nothing else — no explanation, no preamble, no markdown fences
        - Each object must have exactly these keys: "text", "chapterNumber", "chapterName"
        - "text": a single concise sentence (max 20 words) capturing one key idea from the book (do NOT include attribution)
        - "chapterNumber": the real chapter number from the book (e.g. 3)
        - "chapterName": the real name of that chapter from the book (e.g. "The Road Ahead")
        - IMPORTANT — chapter grouping: use the book's actual chapter structure. Multiple quotes from the same chapter MUST share the exact same chapterNumber and chapterName. Every chapter must contain at least 5 quotes — if a chapter would have fewer than 5, merge it with the nearest thematically related chapter. The total number of distinct chapters across all \(count) quotes should reflect the book's real structure (typically 5–12 chapters), not one chapter per quote.
        - Do NOT repeat any of the existing entries listed below

        Existing entries to avoid repeating:
        \(existingList)

        Return format (JSON array only, no other text):
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

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("❌ BookQuoteService HTTP \(httpResponse.statusCode): \(body)")
            throw NSError(domain: "BookQuoteService", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"])
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        guard let content = decoded.choices.first?.message.content else {
            throw OpenAIError.noResponse
        }

        return try parseQuotesArray(from: content, existingQuotes: existingQuotes)
    }

    func extractQuotes(from text: String, bookTitle: String, author: String, existingQuotes: [String]) async throws -> [GeneratedQuote] {
        let existingList = existingQuotes.isEmpty
            ? "None"
            : existingQuotes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let systemPrompt = """
        You are a quote extraction expert. The user has pasted raw text containing quotes or insights from the book "\(bookTitle)" by \(author). Extract each individual quote or insight as a separate entry.

        Rules:
        - Return ONLY a valid JSON array of objects, nothing else — no explanation, no preamble, no markdown fences
        - Each object must have exactly these keys: "text", "chapterNumber", "chapterName"
        - "text": one clean, concise quote or insight (max 20 words, do NOT include attribution or chapter labels)
        - "chapterNumber": integer chapter number from the book (e.g. 1, 2, 3) — use your knowledge of the book's actual chapter structure
        - "chapterName": the real name of that chapter from the book
        - IMPORTANT — chapter grouping: aim for 3–8 broad chapters total across all extracted quotes. Multiple quotes that share the same theme or belong to the same section of the book MUST share the same chapterNumber and chapterName. Do NOT give each quote its own unique chapter. Group liberally.
        - Every chapter must contain at least 5 quotes — if a chapter would have fewer than 5, merge it with the nearest thematically related chapter instead of creating a new one.
        - If the pasted text has an explicit chapter marker (e.g. "Ch.3" or "Chapter 3: ..."), use that. Otherwise, use your knowledge of the book to assign the most fitting existing chapter.
        - Only create a new chapter when quotes are clearly from a distinctly different part of the book
        - Remove duplicates and skip any entries that match the existing quotes below
        - If the pasted text contains attribution markers like "—", "-", or "Ch." treat them as metadata, not part of the quote text

        Existing quotes to skip:
        \(existingList)

        Return format (JSON array only):
        [{"text": "...", "chapterNumber": 1, "chapterName": "..."}, ...]
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Extract all quotes from this text:\n\n\(text)"]
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

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "BookQuoteService", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"])
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        guard let content = decoded.choices.first?.message.content else {
            throw OpenAIError.noResponse
        }

        return try parseQuotesArray(from: content, existingQuotes: existingQuotes)
    }

    // MARK: - Chapter Segregation

    struct ChapterAssignment {
        let quoteId: UUID
        let chapterNumber: Int
        let chapterName: String
    }

    func segregateIntoChapters(
        bookTitle: String,
        author: String,
        quotes: [(id: UUID, text: String, existingChapterNumber: Int?, existingChapterName: String?)]
    ) async throws -> [ChapterAssignment] {
        let quoteList = quotes.enumerated().map { i, q -> String in
            var entry = "\(i + 1). \(q.text)"
            if let cn = q.existingChapterNumber {
                let nameTag = q.existingChapterName.map { " - \($0)" } ?? ""
                entry += " [Already assigned: Ch.\(cn)\(nameTag)]"
            }
            return entry
        }.joined(separator: "\n")

        let knownChapters: [String] = {
            var seen = Set<Int>()
            return quotes.compactMap { q -> String? in
                guard let cn = q.existingChapterNumber, seen.insert(cn).inserted else { return nil }
                let namePart = q.existingChapterName.map { " - \($0)" } ?? ""
                return "Ch.\(cn)\(namePart)"
            }.sorted()
        }()
        let chaptersInfo = knownChapters.isEmpty ? "None detected yet" : knownChapters.joined(separator: "\n")

        let systemPrompt = """
        You are a book organization expert for "\(bookTitle)" by \(author).

        Your task: assign every quote to the correct chapter using your knowledge of the book.

        Rules:
        - Return ONLY a valid JSON array of objects — no explanation, no markdown fences
        - Each object must have exactly these keys: "index" (integer, 1-based), "chapterNumber" (integer), "chapterName" (string)
        - CRITICAL: each chapterNumber must map to exactly one chapterName throughout the entire response. Never use the same chapterNumber with two different names, and never use the same chapterName with two different numbers. Pick one canonical number for each chapter and use it consistently for every quote in that chapter.
        - Every chapter must contain at least 5 quotes — if a chapter would have fewer than 5, merge it with the nearest thematically related chapter instead of creating a standalone small chapter.
        - For quotes marked [Already assigned], keep the same chapter unless the match is clearly wrong
        - For unassigned quotes, use the book's actual chapter structure to determine the best chapter
        - Match to an existing known chapter (listed below) when the content fits — reuse its exact chapterNumber and chapterName as listed
        - chapterName must be the real name of that chapter from the book (e.g. "The Road Ahead"), not just "Chapter N"
        - Every quote must be assigned — no nulls

        Known chapters already in this book (reuse these exact number+name pairs):
        \(chaptersInfo)

        Return format (JSON array only, no other text):
        [{"index": 1, "chapterNumber": 2, "chapterName": "The Road Ahead"}, ...]
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Assign chapters to all these quotes from \"\(bookTitle)\":\n\n\(quoteList)"]
        ]

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 4000,
            "temperature": 0.0
        ]

        guard let url = URL(string: baseURL) else { throw OpenAIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("❌ segregateIntoChapters HTTP \(httpResponse.statusCode): \(body)")
            throw NSError(domain: "BookQuoteService", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"])
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw OpenAIError.noResponse
        }

        return try parseChapterAssignments(from: content, quotes: quotes)
    }

    private func parseChapterAssignments(
        from text: String,
        quotes: [(id: UUID, text: String, existingChapterNumber: Int?, existingChapterName: String?)]
    ) throws -> [ChapterAssignment] {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let fence = cleaned.range(of: "```") {
                cleaned = String(cleaned[..<fence.lowerBound])
            }
        }

        print("📖 segregateIntoChapters response:\n\(cleaned.prefix(500))")

        guard let startIdx = cleaned.firstIndex(of: "["),
              let endIdx = cleaned.lastIndex(of: "]") else {
            throw OpenAIError.invalidResponse
        }

        let jsonString = String(cleaned[startIdx...endIdx])
        guard let data = jsonString.data(using: .utf8) else { throw OpenAIError.invalidResponse }

        let raw = try JSONDecoder().decode([[String: JSONValue]].self, from: data)

        return raw.compactMap { obj -> ChapterAssignment? in
            var index: Int
            if case .int(let i) = obj["index"] { index = i }
            else if case .double(let d) = obj["index"] { index = Int(d) }
            else { return nil }

            let quoteIndex = index - 1
            guard quoteIndex >= 0 && quoteIndex < quotes.count else { return nil }

            var chapterNum: Int
            if case .int(let n) = obj["chapterNumber"] { chapterNum = n }
            else if case .double(let d) = obj["chapterNumber"] { chapterNum = Int(d) }
            else { return nil }

            let chapterTitle: String
            if case .string(let s) = obj["chapterName"], !s.isEmpty { chapterTitle = s }
            else { chapterTitle = "Chapter \(chapterNum)" }

            return ChapterAssignment(quoteId: quotes[quoteIndex].id, chapterNumber: chapterNum, chapterName: chapterTitle)
        }
    }

    // MARK: - Quote Parsing

    private func parseQuotesArray(from text: String, existingQuotes: [String]) throws -> [GeneratedQuote] {
        // Strip markdown code fences if present (gpt-4o often wraps JSON in ```json ... ```)
        var cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .components(separatedBy: "\n")
                .dropFirst()          // remove opening ```json line
                .joined(separator: "\n")
            if let fence = cleaned.range(of: "```") {
                cleaned = String(cleaned[..<fence.lowerBound])
            }
        }

        print("📖 BookQuoteService response content:\n\(cleaned.prefix(500))")

        guard let startIdx = cleaned.firstIndex(of: "["),
              let endIdx = cleaned.lastIndex(of: "]") else {
            print("❌ No JSON array found in response")
            throw OpenAIError.invalidResponse
        }

        let jsonString = String(cleaned[startIdx...endIdx])
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

struct OpenAIResponse: Codable {
    let choices: [Choice]
    struct Choice: Codable {
        let message: Message
        struct Message: Codable {
            let content: String
        }
    }
}

enum OpenAIError: Error {
    case invalidURL
    case noResponse
    case invalidResponse
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
