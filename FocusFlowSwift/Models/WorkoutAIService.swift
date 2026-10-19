import Foundation

/// Turns a pasted workout description into a Tabata or rep workout draft.
/// Same OpenAI plumbing as VirtueSuggestionService / AISchedulerService.
struct WorkoutAIService {
    enum Result {
        case tabata(TabataDraft)
        case reps(name: String, sets: [RepSet], restSeconds: Int)

        var kind: WorkoutKind {
            if case .tabata = self { return .tabata }
            return .reps
        }

        var name: String {
            switch self {
            case .tabata(let d): return d.name
            case .reps(let name, _, _): return name
            }
        }

        var summary: String {
            switch self {
            case .tabata(let d): return d.summary
            case .reps(_, let sets, _):
                let exercises = sets.reduce(0) { $0 + $1.exercises.count }
                return "\(sets.count) set\(sets.count == 1 ? "" : "s") · \(exercises) exercise\(exercises == 1 ? "" : "s")"
            }
        }
    }

    enum WorkoutAIError: LocalizedError {
        case missingKey, noResponse, badFormat, tooLong

        var errorDescription: String? {
            switch self {
            case .missingKey: return "No OpenAI API key is set up in the app."
            case .noResponse: return "The AI didn't send anything back. Try again."
            case .badFormat: return "Couldn't read a workout from that description. Try adding more detail."
            case .tooLong: return "That description is too long to read at once. Put a blank line between workouts, or paste fewer at a time."
            }
        }
    }

    /// Copied from the Create with AI screen and given to another AI chat
    /// (ChatGPT, Claude…) so it writes workouts in a format this app reads well.
    static let formatInstructions = """
    Write my workouts in the format below so I can paste them into my workout app. Follow it exactly.

    GENERAL
    - One workout per paragraph. Put a blank line between workouts, and no blank lines inside a workout.
    - Start each workout with its name on the first line, ending with a full stop.
    - Plain text only: no tables, no markdown, no bullet points, no emojis.
    - Keep each reply under about 15 workouts; split bigger programs into batches I can paste one at a time.

    TABATA (timed intervals)
    First line: name, then prepare time, work time, rest time, number of rounds, and rest between rounds.
    Second line: the exercises in order, separated by commas. Each exercise is one cycle.
    Example:
    Insanity warm up 1: 10s prepare, 40s work, no rest, 3 rounds, 30s rest between rounds.
    Jog, jumping jacks, heismans, 1-2-3, butt kicks, high knees, mummy kicks.

    ONE TABATA WITH SEVERAL PARTS (e.g. a warm up followed by circuits, run as one workout)
    First line: the workout name followed by "(one Tabata, N parts)".
    Then, for each part, a line starting with "Part <name>:" and its timing, followed by a line with its exercises.
    Keep all parts in one paragraph (no blank lines between parts).
    Example:
    Insanity Max 30 Cardio Challenge (one Tabata, 3 parts).
    Part Warm up: 10s prepare, 30s work, no rest, 2 rounds.
    Chest open jack, jack uppercut, 1-2-3 knee, cross jack, high knee jab.
    Part Circuit 1: 30s prepare, 30s work, no rest, 3 rounds.
    Squat kick, pike-up spider, 10 and 2.
    Part Circuit 2: 30s prepare, 30s work, no rest, 3 rounds.
    Medicine ball twist, plank jack plus in and out, 4 jab plus 4 high knee.

    REP WORKOUT (weight training)
    First line: the name, optionally followed by the rest between sets.
    Then one line per set: "Set N: exercise R reps W kg, exercise R reps W kg."
    - If a set is repeated with the same reps, write "Set N × 3:".
    - If the reps change from round to round (15, 12, 8), write each round as its own set.
    - Leave out the weight if it isn't known.
    - Timed exercises: "plank 30 seconds".
    - Extra details go in brackets after the exercise: "(each side)", "(slow tempo)", "(force set)".
    Example:
    Upper body A, 90s rest between sets.
    Set 1 × 3: bench press 10 reps 40 kg, bent-over row 10 reps 30 kg.
    Set 2: shoulder press 12 reps 15 kg, bicep curl 12 reps 10 kg (slow on the way down).
    Set 3: shoulder press 8 reps 17.5 kg.

    Now write these workouts:
    """

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    /// Uses the app's OpenAI key unless one is passed (for testing).
    init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
    }

    /// Builds every workout described in the text, in order.
    /// Long text is split into pieces of one or two workouts, read four at a
    /// time; a piece that fails is retried. `skippedParts` counts pieces that
    /// still couldn't be read, and `firstError` says why.
    /// `onProgress(done, total)` is called on the main thread.
    /// `weightUnit` is "kg" or "lb"; weights are returned in that unit.
    func createWorkouts(from description: String, weightUnit: String,
                        onProgress: @escaping @MainActor (Int, Int) -> Void = { _, _ in })
        async throws -> (workouts: [Result], parts: Int, skippedParts: Int, firstError: String?) {
        guard !apiKey.isEmpty else { throw WorkoutAIError.missingKey }
        let pieces = Self.pieces(of: description)
        let maxParallel = 4

        var outcomes = [(results: [Result], error: Error?)](repeating: ([], nil), count: pieces.count)
        var done = 0
        await onProgress(0, pieces.count)
        await withTaskGroup(of: (Int, [Result], Error?).self) { group in
            var next = 0
            func addNext() {
                guard next < pieces.count else { return }
                let i = next
                next += 1
                group.addTask {
                    do { return (i, try await self.requestWithRetry(pieces[i], weightUnit: weightUnit), nil) }
                    catch { return (i, [], error) }
                }
            }
            for _ in 0..<min(maxParallel, pieces.count) { addNext() }
            for await (i, results, error) in group {
                outcomes[i] = (results, error)
                done += 1
                await onProgress(done, pieces.count)
                addNext()
            }
        }

        let workouts = outcomes.flatMap(\.results)
        let failures = outcomes.compactMap(\.error)
        if workouts.isEmpty {
            throw failures.first ?? WorkoutAIError.badFormat
        }
        return (workouts, pieces.count, failures.count, failures.first?.localizedDescription)
    }

    /// Up to 3 tries per piece, waiting a little longer each time.
    private func requestWithRetry(_ piece: String, weightUnit: String) async throws -> [Result] {
        var lastError: Error = WorkoutAIError.noResponse
        for attempt in 0..<3 {
            do {
                return try await request(piece, weightUnit: weightUnit)
            } catch WorkoutAIError.missingKey {
                throw WorkoutAIError.missingKey
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await _Concurrency.Task.sleep(nanoseconds: UInt64(2 + attempt * 3) * 1_000_000_000)
                }
            }
        }
        throw lastError
    }

    /// Splits text into pieces of about `maxChars`, so each AI answer stays
    /// short and complete. Prefers blank lines; a long block with no blank
    /// lines is split before workout-title lines (lines not starting with
    /// "Set"). Short text stays in one piece.
    static func pieces(of text: String, maxChars: Int = 1500) -> [String] {
        // Every kind of line break becomes "\n" (notes apps, PDFs and chat
        // apps don't all use the same one).
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for separator in ["\r", "\u{2028}", "\u{2029}", "\u{0085}", "\u{000B}", "\u{000C}"] {
            normalized = normalized.replacingOccurrences(of: separator, with: "\n")
        }
        normalized = reflow(normalized)
        let paragraphs = normalized
            .components(separatedBy: "\n")
            .split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            .flatMap { lines in splitLongBlock(Array(lines), maxChars: maxChars) }

        var pieces: [String] = []
        var current = ""
        for paragraph in paragraphs {
            if !current.isEmpty && current.count + paragraph.count > maxChars {
                pieces.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n\n") + paragraph
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pieces.append(current) }
        return pieces
    }

    /// Restores structure when line breaks were lost in copying (e.g. the
    /// whole program arrives as one line): puts each "Set N" on its own line
    /// and a blank line before each workout title (the sentence before "Set 1").
    static func reflow(_ text: String) -> String {
        // "… 15 reps. Set 2: …" → "… 15 reps.\nSet 2: …"
        guard let setStart = try? NSRegularExpression(pattern: #"[ \t]+(?=set\s*\d+\s*(?:[×x]\s*\d+\s*)?:)"#,
                                                      options: .caseInsensitive) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let withSetLines = setStart.stringByReplacingMatches(in: text, range: range, withTemplate: "\n")

        func startsWithSet(_ line: String, number: String? = nil) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard t.hasPrefix("set") else { return false }
            guard let number else { return true }
            let rest = t.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return rest.hasPrefix(number) && !(rest.dropFirst(number.count).first?.isNumber ?? false)
        }

        var lines = withSetLines.components(separatedBy: "\n")
        var i = 0
        while i < lines.count - 1 {
            // A "Set" line followed by "Set 1" ends with the next workout's title.
            if startsWithSet(lines[i]), startsWithSet(lines[i + 1], number: "1") {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                let body = line.hasSuffix(".") ? String(line.dropLast()) : line
                if let cut = body.range(of: ". ", options: .backwards) ?? body.range(of: ") ", options: .backwards) {
                    let head = String(line[..<cut.upperBound]).trimmingCharacters(in: .whitespaces)
                    let title = String(line[cut.upperBound...]).trimmingCharacters(in: .whitespaces)
                    lines.replaceSubrange(i...i, with: [head, "", title])
                    i += 3
                    continue
                }
            } else if !startsWithSet(lines[i]), startsWithSet(lines[i + 1], number: "1"),
                      i > 0, !lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                // A title on its own line right after another workout: separate it.
                lines.insert("", at: i)
                i += 2
                continue
            }
            i += 1
        }
        return lines.joined(separator: "\n")
    }

    /// Breaks a block with no blank lines into workout-sized chunks.
    private static func splitLongBlock(_ lines: [String], maxChars: Int) -> [String] {
        let block = lines.joined(separator: "\n")
        guard block.count > maxChars else { return [block] }
        func isSetLine(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces).lowercased()
            return t.hasPrefix("set ") || t.first?.isNumber == true
        }
        var chunks: [String] = []
        var current: [String] = []
        for line in lines {
            // Start a new chunk at a workout title once the current one has content.
            if !current.isEmpty && !isSetLine(line) && current.contains(where: isSetLine) {
                chunks.append(current.joined(separator: "\n"))
                current = []
            }
            current.append(line)
        }
        if !current.isEmpty { chunks.append(current.joined(separator: "\n")) }
        return chunks
    }

    /// One AI call for one piece of text. Returns [] if the piece has no workout.
    private func request(_ description: String, weightUnit: String) async throws -> [Result] {

        let systemPrompt = """
        You turn a person's workout description into structured workouts for a fitness app.
        The text may describe one workout or several; return every workout it describes, in order. Treat each separately named or separately described workout as its own item; do not merge them.
        For each, decide whether it is a "tabata" (timed intervals that repeat in rounds) or "reps" (weight training: sets of exercises with rep counts, no timer).

        Respond with ONLY a JSON object in exactly this shape:
        { "workouts": [ WORKOUT, WORKOUT, ... ] }

        where each WORKOUT is:
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
          (or, for one Tabata made of several timed parts:)
          "tabata": {
            "parts": [
              { "name": "Warm up", "prepare_seconds": 10, "work_seconds": 30, "rest_seconds": 0, "cycles": 5, "rounds": 2, "rest_between_rounds_seconds": 0, "cycle_names": ["..."] },
              { "name": "Circuit 1", "prepare_seconds": 30, "work_seconds": 30, "rest_seconds": 0, "cycles": 3, "rounds": 3, "rest_between_rounds_seconds": 0, "cycle_names": ["..."] }
            ]
          },
          "reps": {
            "rest_between_sets_seconds": 0,
            "sets": [
              { "repeats": 3, "exercises": [ { "name": "Bench press", "reps": 10, "weight": 40, "note": "" } ] }
            ]
          }
        }

        Rules:
        - In each workout, fill only the section that matches "kind".
        - All times are whole seconds. "0:40" means 40 seconds; "1:30" means 90 seconds.
        - If the text contradicts itself about a time (e.g. "0:30 sec (40 seconds)"), use the number written in words or in brackets.
        - Tabata: "cycles" is the number of work intervals in one round, one per exercise; list one name per cycle in order. If no exercises are named, use an empty list. "rounds" is how many times the full set of cycles repeats (also called tabatas or sets). Use defaults when not given: prepare 10, work 20, rest 10, rounds 1, rest between rounds 0.
        - Multi-part Tabata: ONLY when the text explicitly says timed sections belong to one workout (it says "one Tabata" or "N parts", or lists "Part …:" lines under one title), return ONE tabata workout with "parts", one per section, in order, each with its own "name", timing and cycle names. Separately titled Tabatas are separate workouts, even if their titles share words (e.g. "X warm up" and "X circuit 1" are two workouts); never merge them yourself.
        - Tabata cycle names: copy each exercise exactly as written, including details in brackets, e.g. "Squat kick (right, then left, then alternating)".
        - Reps: group exercises into sets as described; "repeats" is how many times a set is done (e.g. "3 sets of" or "× 3"). "reps" is a whole number (use the first number of a range, e.g. 8-12 → 8). "weight" is a number in \(weightUnit); convert from the other unit if needed. Put tempo, cues or rep ranges in "note".
        - Timed exercises (e.g. "plank 30 seconds"): set "reps" to the number of seconds and "note" to "30 seconds".
        - Extra details such as "each side", "(force set)" or "slow tempo" go in "note".
        - Keep the output compact: leave out "weight" and "note" when not given, and leave out the section that doesn't match "kind".
        - Never skip or summarize: include every workout and every set in the text, even if there are many.
        - Ignore text that is not a workout (titles, separators, instructions). If there is no workout at all, return { "workouts": [] }.
        - If no name is given, make a short descriptive one.
        - No explanation, no markdown, no code fences.
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": description]
            ],
            "max_tokens": 8000,
            "temperature": 0.1,
            "response_format": ["type": "json_object"]
        ]

        guard let url = URL(string: baseURL) else { throw WorkoutAIError.noResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "WorkoutAI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }

        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
            let finish_reason: String?
        }
        struct Response: Decodable { let choices: [Choice] }
        guard let choice = try JSONDecoder().decode(Response.self, from: data).choices.first else {
            throw WorkoutAIError.noResponse
        }
        // A cut-off answer is incomplete JSON; say so instead of "can't read".
        if choice.finish_reason == "length" { throw WorkoutAIError.tooLong }
        guard let content = choice.message.content else { throw WorkoutAIError.noResponse }
        return try Self.parse(content)
    }

    // MARK: Parsing

    private struct Envelope: Decodable {
        var workouts: [Lenient<Payload>]?
    }

    /// Decodes an item, or nil if that one item is malformed, so one bad
    /// workout doesn't throw away the rest.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// A number that may arrive as 15, 15.0 or "15".
    private struct Num: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { value = d }
            else if let s = try? c.decode(String.self) {
                let digits = s.replacingOccurrences(of: ",", with: ".")
                    .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
                    .first { !$0.isEmpty }
                value = digits.flatMap(Double.init)
            } else { value = nil }
        }
        var int: Int? { value.map { Int($0.rounded()) } }
    }

    private struct Payload: Decodable {
        struct Tabata: Decodable {
            /// Several timed sections of ONE workout; each is like a Tabata itself.
            var parts: [Lenient<Tabata>]?
            var name: String?
            var prepare_seconds: Num?
            var work_seconds: Num?
            var rest_seconds: Num?
            var cycles: Num?
            var rounds: Num?
            var rest_between_rounds_seconds: Num?
            var cycle_names: [String]?
        }
        struct Exercise: Decodable {
            var name: String?
            var reps: Num?
            var weight: Num?
            var note: String?
        }
        struct Set: Decodable {
            var repeats: Num?
            var exercises: [Exercise]?
        }
        struct Reps: Decodable {
            var rest_between_sets_seconds: Num?
            var sets: [Set]?
        }
        var kind: String?
        var name: String?
        var tabata: Tabata?
        var reps: Reps?
    }

    static func parse(_ raw: String) throws -> [Result] {
        // Strip code fences in case the model adds them anyway.
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        guard let data = text.data(using: .utf8) else { throw WorkoutAIError.badFormat }
        var payloads: [Payload?] = []
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data), let list = envelope.workouts {
            payloads = list.map(\.value)
        } else if let single = try? JSONDecoder().decode(Payload.self, from: data), single.kind != nil {
            payloads = [single]
        } else {
            throw WorkoutAIError.badFormat
        }
        // No workouts in this text (e.g. only a title): nothing to add.
        if payloads.isEmpty { return [] }
        // Skip any item that can't be read; fail only if none can.
        let results = payloads.compactMap { $0.flatMap { try? build($0) } }
        guard !results.isEmpty else { throw WorkoutAIError.badFormat }
        return results
    }

    private static func build(_ p: Payload) throws -> Result {
        let name = (p.name ?? "").trimmingCharacters(in: .whitespaces)

        if p.kind == "reps", let reps = p.reps {
            let sets: [RepSet] = (reps.sets ?? []).compactMap { set in
                let exercises = (set.exercises ?? []).compactMap { e -> RepExercise? in
                    let n = (e.name ?? "").trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return nil }
                    return RepExercise(name: n, reps: max(0, e.reps?.int ?? 10),
                                       weight: (e.weight?.value ?? 0) > 0 ? e.weight?.value : nil, note: e.note ?? "")
                }
                return exercises.isEmpty ? nil : RepSet(repeats: min(20, max(1, set.repeats?.int ?? 1)), exercises: exercises)
            }
            guard !sets.isEmpty else { throw WorkoutAIError.badFormat }
            return .reps(name: name, sets: sets, restSeconds: clampSeconds(reps.rest_between_sets_seconds?.int ?? 0))
        }

        guard let t = p.tabata else { throw WorkoutAIError.badFormat }
        let sections = (t.parts ?? []).compactMap(\.value)
        let parts = sections.isEmpty ? [part(from: t)] : sections.map(part(from:))
        return .tabata(TabataDraft(name: name, parts: parts))
    }

    private static func part(from t: Payload.Tabata) -> TabataPart {
        let names = (t.cycle_names ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
        let cycles = min(50, max(1, t.cycles?.int ?? max(names.count, 1)))
        var part = TabataPart()
        part.name = (t.name ?? "").trimmingCharacters(in: .whitespaces)
        part.prepareSeconds = clampSeconds(t.prepare_seconds?.int ?? 10)
        part.workSeconds = max(5, clampSeconds(t.work_seconds?.int ?? 20))
        part.restSeconds = clampSeconds(t.rest_seconds?.int ?? 10)
        part.cycles = cycles
        part.rounds = min(20, max(1, t.rounds?.int ?? 1))
        part.restBetweenRoundsSeconds = clampSeconds(t.rest_between_rounds_seconds?.int ?? 0)
        part.cycleNames = (0..<cycles).map { $0 < names.count ? names[$0] : "" }
        part.cycleImageIDs = Array(repeating: "", count: cycles)
        return part
    }

    private static func clampSeconds(_ s: Int) -> Int { min(3600, max(0, s)) }
}
