import Foundation

// Suggests character virtues (e.g. "Self-Discipline", "Patience") a task or
// project exercises, based on its title/description. Mirrors
// AISchedulerService's plumbing (same OpenAI key lookup, same raw
// chat/completions call).
struct VirtueSuggestionService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init() {
        self.apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
    }

    /// Returns `count` new virtue names, distinct from `existing` (case-insensitive).
    /// `itemLabel` is "Task" or "Project" (just used to phrase the prompt).
    /// `context` is free text about the item (description/info/tags) — whatever's
    /// available to ground the suggestion; pass "" if there's none.
    func suggestVirtues(itemTitle: String, itemLabel: String = "Task", context: String, existing: [String], count: Int = 4) async throws -> [String] {
        let systemPrompt = """
        Virtues work like muscles: each \(itemLabel.lowercased()) a person does exercises specific ones, the way a specific exercise works a specific physical muscle. Your job is to identify which virtues THIS SPECIFIC \(itemLabel.lowercased()) exercises — not a generic productivity checklist slapped on everything.

        Think concretely before answering: what would someone need to summon, resist, or draw on to actually do this \(itemLabel.lowercased()) well? Which virtue's absence would make them fail, quit early, or do it half-heartedly? Ground every suggestion in something the title/description actually implies — don't guess generically.

        Examples of grounding by domain (use these as a pattern, not a fixed list):
        - Physical training / exercise → Discipline, Perseverance, Physical Courage, Endurance
        - A hard conversation / confrontation → Honesty, Courage, Diplomacy, Directness
        - Deep, focused solo work → Focus, Patience, Diligence, Concentration
        - Helping or serving someone else → Compassion, Generosity, Selflessness, Empathy
        - Resisting a bad habit or urge → Temperance, Self-Control, Restraint
        - Creative or exploratory work → Curiosity, Originality, Openness, Courage
        - Financial discipline (saving, budgeting) → Prudence, Frugality, Foresight
        - Routine/habitual tasks (waking early, chores) → Discipline, Consistency, Order
        - Learning something new / studying → Curiosity, Humility, Diligence, Patience
        - Cleaning up a mess you didn't make / owning a mistake → Responsibility, Humility, Accountability

        Pick virtues SPECIFIC to what this \(itemLabel.lowercased()) actually demands. Do not default to "Self-Discipline" or "Perseverance" unless the \(itemLabel.lowercased()) genuinely calls for them more than any other virtue — vary your vocabulary based on the \(itemLabel.lowercased())'s actual domain and action, not a one-size-fits-all list.

        Respond with ONLY a JSON array of exactly \(count) short virtue names, each 1–3 words, Title Case (e.g. ["Focus", "Empathy"]). No explanation, no markdown, no code fences — just the JSON array.

        Never repeat any of these already-assigned virtues: \(existing.isEmpty ? "(none)" : existing.joined(separator: ", ")).
        """

        let contextLine = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let userMessage = contextLine.isEmpty
            ? "\(itemLabel): \(itemTitle)"
            : "\(itemLabel): \(itemTitle)\n\(contextLine)"

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 200,
            "temperature": 0.3
        ]

        guard let url = URL(string: baseURL) else { throw VirtueError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "VirtueSuggestion", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }

        struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        struct Response: Decodable { let choices: [Choice] }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw VirtueError.noResponse
        }

        let parsed = Self.parseVirtues(from: content)
        guard !parsed.isEmpty else { throw VirtueError.badFormat(content) }

        // De-dupe against what's already assigned (case-insensitive), then cap to `count`.
        let existingLower = Set(existing.map { $0.lowercased() })
        var seen = existingLower
        var result: [String] = []
        for v in parsed {
            let key = v.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(v)
            if result.count == count { break }
        }
        return result
    }

    // Tolerates a JSON array, a fenced ```json array, or a plain newline/comma-
    // separated list with stray bullets/numbering — GPT doesn't always follow
    // the "JSON only" instruction exactly.
    private static func parseVirtues(from raw: String) -> [String] {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let data = cleaned.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }

        // Fallback: split on newlines/commas, strip common list markers.
        let separators = CharacterSet(charactersIn: ",\n")
        return cleaned.components(separatedBy: separators)
            .map { line -> String in
                var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                s = s.trimmingCharacters(in: CharacterSet(charactersIn: "[]\"'"))
                if let dashRange = s.range(of: #"^[-•\d.\)]+\s*"#, options: .regularExpression) {
                    s.removeSubrange(dashRange)
                }
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    enum VirtueError: LocalizedError {
        case invalidURL, noResponse, badFormat(String)
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API URL."
            case .noResponse: return "No response from AI."
            case .badFormat(let s): return "Unexpected AI output:\n\(s.prefix(200))"
            }
        }
    }
}
