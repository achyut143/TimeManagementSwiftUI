import Foundation

/// Turns a pasted workout description into a Tabata or rep workout draft.
/// Same OpenAI plumbing as VirtueSuggestionService / AISchedulerService.
struct WorkoutAIService {
    enum Result {
        case tabata(TabataDraft)
        case reps(name: String, sets: [RepSet], restSeconds: Int)
    }

    enum WorkoutAIError: LocalizedError {
        case missingKey, noResponse, badFormat

        var errorDescription: String? {
            switch self {
            case .missingKey: return "No OpenAI API key is set up in the app."
            case .noResponse: return "The AI didn't send anything back. Try again."
            case .badFormat: return "Couldn't read a workout from that description. Try adding more detail."
            }
        }
    }

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init() {
        self.apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
    }

    /// `weightUnit` is "kg" or "lb"; weights are returned in that unit.
    func createWorkout(from description: String, weightUnit: String) async throws -> Result {
        guard !apiKey.isEmpty else { throw WorkoutAIError.missingKey }

        let systemPrompt = """
        You turn a person's workout description into a structured workout for a fitness app.
        Decide whether it is a "tabata" (timed intervals that repeat in rounds) or "reps" (weight training: sets of exercises with rep counts, no timer).

        Respond with ONLY a JSON object in exactly this shape:
        {
          "kind": "tabata" or "reps",
          "name": "short workout name",
          "tabata": {
            "prepare_seconds": 10,
            "work_seconds": 40,
            "rest_seconds": 0,
            "cycles": 7,
            "rounds": 3,
            "rest_between_rounds_seconds": 30,
            "cycle_names": ["Jog", "Jumping jacks"]
          },
          "reps": {
            "rest_between_sets_seconds": 0,
            "sets": [
              { "repeats": 3, "exercises": [ { "name": "Bench press", "reps": 10, "weight": 40, "note": "" } ] }
            ]
          }
        }

        Rules:
        - Fill only the section that matches "kind"; set the other to null.
        - All times are whole seconds. "0:40" means 40 seconds; "1:30" means 90 seconds.
        - If the text contradicts itself about a time (e.g. "0:30 sec (40 seconds)"), use the number written in words or in brackets.
        - Tabata: "cycles" is the number of work intervals in one round, one per exercise; list one name per cycle in order. If no exercises are named, use an empty list. "rounds" is how many times the full set of cycles repeats (also called tabatas or sets). Use defaults when not given: prepare 10, work 20, rest 10, rounds 1, rest between rounds 0.
        - Reps: group exercises into sets as described; "repeats" is how many times a set is done (e.g. "3 sets of" or "× 3"). "reps" is a whole number (use the first number of a range, e.g. 8-12 → 8). "weight" is a number in \(weightUnit), or null when not given; convert from the other unit if needed. Put tempo, cues or rep ranges in "note".
        - If no name is given, make a short descriptive one.
        - No explanation, no markdown, no code fences.
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": description]
            ],
            "max_tokens": 2000,
            "temperature": 0.1,
            "response_format": ["type": "json_object"]
        ]

        guard let url = URL(string: baseURL) else { throw WorkoutAIError.noResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "WorkoutAI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }

        struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        struct Response: Decodable { let choices: [Choice] }
        guard let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content else {
            throw WorkoutAIError.noResponse
        }
        return try Self.parse(content)
    }

    // MARK: Parsing

    private struct Payload: Decodable {
        struct Tabata: Decodable {
            var prepare_seconds: Int?
            var work_seconds: Int?
            var rest_seconds: Int?
            var cycles: Int?
            var rounds: Int?
            var rest_between_rounds_seconds: Int?
            var cycle_names: [String]?
        }
        struct Exercise: Decodable {
            var name: String?
            var reps: Int?
            var weight: Double?
            var note: String?
        }
        struct Set: Decodable {
            var repeats: Int?
            var exercises: [Exercise]?
        }
        struct Reps: Decodable {
            var rest_between_sets_seconds: Int?
            var sets: [Set]?
        }
        var kind: String?
        var name: String?
        var tabata: Tabata?
        var reps: Reps?
    }

    static func parse(_ raw: String) throws -> Result {
        // Strip code fences in case the model adds them anyway.
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        guard let data = text.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw WorkoutAIError.badFormat
        }
        let name = (p.name ?? "").trimmingCharacters(in: .whitespaces)

        if p.kind == "reps", let reps = p.reps {
            let sets: [RepSet] = (reps.sets ?? []).compactMap { set in
                let exercises = (set.exercises ?? []).compactMap { e -> RepExercise? in
                    let n = (e.name ?? "").trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return nil }
                    return RepExercise(name: n, reps: max(0, e.reps ?? 10),
                                       weight: (e.weight ?? 0) > 0 ? e.weight : nil, note: e.note ?? "")
                }
                return exercises.isEmpty ? nil : RepSet(repeats: min(20, max(1, set.repeats ?? 1)), exercises: exercises)
            }
            guard !sets.isEmpty else { throw WorkoutAIError.badFormat }
            return .reps(name: name, sets: sets, restSeconds: clampSeconds(reps.rest_between_sets_seconds ?? 0))
        }

        guard let t = p.tabata else { throw WorkoutAIError.badFormat }
        let names = (t.cycle_names ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
        let cycles = min(50, max(1, t.cycles ?? max(names.count, 1)))
        var draft = TabataDraft()
        draft.name = name
        draft.prepareSeconds = clampSeconds(t.prepare_seconds ?? 10)
        draft.workSeconds = max(5, clampSeconds(t.work_seconds ?? 20))
        draft.restSeconds = clampSeconds(t.rest_seconds ?? 10)
        draft.cycles = cycles
        draft.rounds = min(20, max(1, t.rounds ?? 1))
        draft.restBetweenRoundsSeconds = clampSeconds(t.rest_between_rounds_seconds ?? 0)
        draft.cycleNames = (0..<cycles).map { $0 < names.count ? names[$0] : "" }
        draft.cycleImageIDs = Array(repeating: "", count: cycles)
        return .tabata(draft)
    }

    private static func clampSeconds(_ s: Int) -> Int { min(3600, max(0, s)) }
}
