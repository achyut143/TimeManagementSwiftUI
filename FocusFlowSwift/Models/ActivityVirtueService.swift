import Foundation

// Generates (and regenerates) a VirtueActivity's description: exactly 2
// virtues from the fixed personal virtue list below, each with a short note
// on how the activity exercises it, plus one selfless "why" reason. Uses the
// user's own prompt verbatim as the substantive instructions — the only
// addition is a JSON-output directive at the end, needed to parse the reply
// into structured fields instead of free-form prose.
struct ActivityVirtueService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    // The fixed personal virtue list the prompt draws from.
    static let virtueList: [String] = [
        "Self control", "Temperance", "Non attachment (engaged freedom)", "Concentration & focus",
        "Steadiness", "Commitment", "Austerity", "Happiness and enjoyment", "Wisdom & planning",
        "Curiosity", "Persistence", "Punctuality", "Humility", "Modesty", "Compassion", "Generosity",
        "Courage", "Explorer", "Accept people as they are", "Avoid fault finding", "Non harming",
        "Service", "Cleanliness", "Physical energy", "Learner", "Prioritization", "Excellence"
    ]

    init() {
        self.apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
    }

    struct GeneratedDescription {
        let properName: String
        let virtues: [VirtueExplanation]
        let why: String
    }

    func generateDescription(activityName: String) async throws -> GeneratedDescription {
        let systemPrompt = """
        I will give you an activity. Identify exactly 2 virtues from my virtue list that this activity genuinely exercises.

        For each virtue:

        Virtue: Name it.
        How it is exercised: Briefly explain how doing the activity trains that virtue.
        Then give me:

        Why should I do it? — Give me one short, powerful, selfless reason connected to a higher purpose. Do NOT focus on personal benefits such as money, fitness, status, confidence, or achievement.

        The reason could involve:

        Being a source of strength or inspiration for others
        Serving my family, team, community, or users
        Making other people's lives better
        Setting an example through my actions
        Using my abilities responsibly
        Contributing something meaningful beyond myself
        Be creative, thoughtful, and specific to the activity. Avoid generic motivational statements.

        Keep the response concise.

        My virtues:
        \(Self.virtueList.joined(separator: ", ")), etc.

        Before the above, also clean up the activity name I give you: fix typos, capitalization, and phrasing so it reads as a proper, concise activity title (e.g. "cold showers" → "Cold Showers", "read book" → "Reading"). Keep it recognizably the same activity — don't change what it means, just how it's written.

        Respond ONLY with valid JSON in exactly this shape, no markdown, no code fences, no extra text:
        {"activityName": "cleaned-up activity name", "virtues": [{"name": "virtue name", "howExercised": "one brief sentence"}, {"name": "virtue name", "howExercised": "one brief sentence"}], "why": "one short, powerful, selfless sentence or two"}
        """

        let userMessage = "Activity: \(activityName)"

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 400,
            "temperature": 0.6
        ]

        guard let url = URL(string: baseURL) else { throw ServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "ActivityVirtueService", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }

        struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        struct Response: Decodable { let choices: [Choice] }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw ServiceError.noResponse
        }

        guard let parsed = Self.parse(content) else {
            throw ServiceError.badFormat(content)
        }
        return parsed
    }

    // Tolerates a bare JSON object or one wrapped in ```json fences.
    private static func parse(_ raw: String) -> GeneratedDescription? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        struct RawVirtue: Decodable { let name: String; let howExercised: String }
        struct RawResponse: Decodable { let activityName: String?; let virtues: [RawVirtue]; let why: String }

        guard let data = cleaned.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RawResponse.self, from: data),
              !decoded.virtues.isEmpty else {
            return nil
        }

        let virtues = decoded.virtues.map { VirtueExplanation(virtueName: $0.name, howExercised: $0.howExercised) }
        let cleanedName = decoded.activityName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GeneratedDescription(properName: cleanedName, virtues: virtues, why: decoded.why)
    }

    enum ServiceError: LocalizedError {
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
