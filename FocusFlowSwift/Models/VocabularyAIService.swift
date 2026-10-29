import Foundation

/// Asks OpenAI for new vocabulary words. Same plumbing as WorkoutAIService.
struct VocabularyAIService {
    /// A word as the AI returns it, before it is saved.
    struct Draft: Decodable {
        var word: String
        var part_of_speech: String?
        var pronunciation: String?
        var syllables: String?
        var definition: String
        var sentences: [String]?
        var synonyms: [String]?
        var antonyms: [String]?
        var collocations: [String]?
        var memory_tip: String?
    }

    enum VocabAIError: LocalizedError {
        case missingKey, noResponse, badFormat

        var errorDescription: String? {
            switch self {
            case .missingKey: return "No OpenAI API key is set up in the app."
            case .noResponse: return "The AI didn't send anything back. Try again."
            case .badFormat: return "Couldn't read the words the AI sent. Try again."
            }
        }
    }

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
    }

    /// Returns `count` new words. `avoid` lists words already saved so they
    /// aren't repeated.
    func generateWords(level: VocabLevel, focus: VocabFocus, tone: VocabTone,
                       topic: String, count: Int = 5, avoid: [String]) async throws -> [Draft] {
        guard !apiKey.isEmpty else { throw VocabAIError.missingKey }

        let topicLine = topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "- Theme: the words and sentences should relate to \"\(topic)\".\n"
        let toneLine: String
        switch tone {
        case .mixed: toneLine = "Mix formal and casual example sentences."
        case .formal: toneLine = "Write the example sentences in a formal, professional style."
        case .casual: toneLine = "Write the example sentences the way people speak casually."
        }
        // Keep the prompt short: the most recent words matter most.
        let avoidList = avoid.suffix(300).joined(separator: ", ")

        let systemPrompt = """
        You are an English vocabulary coach helping an adult learner speak and write more clearly and confidently.
        Pick \(count) English words for CEFR level \(level.rawValue) (\(level.title)): \(level.promptHint).
        Focus: \(focus.rawValue) — \(focus.promptHint).
        \(topicLine)- Choose high-value words the learner will actually use, not obscure ones. Vary the parts of speech.
        - Never use any word from this list: [\(avoidList)]
        - Give 3 example sentences per word showing different natural uses. Each sentence must contain the exact word (or a form of it). \(toneLine)
        - The definition is one short, plain sentence a learner at this level understands. Don't use the word itself in it.
        - "pronunciation" is a simple sound-it-out guide with the stressed syllable in capitals, e.g. "uh-BIK-wih-tus".
        - "syllables" splits the written word with middle dots, e.g. "u·biq·ui·tous".
        - Give 2–3 synonyms and 0–2 antonyms (empty list if none fit). Each must be a single word or short phrase that is NOT the word itself.
        - Give 2–3 common collocations (words it's often used with), e.g. "make a decision".
        - "memory_tip" is one short trick to remember the meaning or spelling.

        Respond with ONLY a JSON object in exactly this shape, no markdown:
        { "words": [ { "word": "", "part_of_speech": "", "pronunciation": "", "syllables": "", "definition": "", "sentences": ["", "", ""], "synonyms": [""], "antonyms": [], "collocations": [""], "memory_tip": "" } ] }
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Give me \(count) new words."]
            ],
            "max_tokens": 3000,
            "temperature": 0.9,
            "response_format": ["type": "json_object"]
        ]

        guard let url = URL(string: baseURL) else { throw VocabAIError.noResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "VocabularyAI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }

        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        struct Response: Decodable { let choices: [Choice] }
        guard let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content else {
            throw VocabAIError.noResponse
        }
        return try Self.parse(content, avoid: avoid)
    }

    static func parse(_ raw: String, avoid: [String]) throws -> [Draft] {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        struct Envelope: Decodable { var words: [Draft] }
        guard let data = cleaned.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw VocabAIError.badFormat
        }
        // Drop blanks and anything already saved, in case the AI ignored the list.
        let known = Set(avoid.map { $0.lowercased() })
        var seen = Set<String>()
        let words = envelope.words.filter { draft in
            let key = draft.word.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, !draft.definition.isEmpty, !known.contains(key), !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        guard !words.isEmpty else { throw VocabAIError.badFormat }
        return words
    }
}
