import Foundation
import SwiftData

/// How to do one exercise, written by AI once and then kept, so the same
/// exercise never needs a second AI call. Shared by every workout that uses it.
@Model
final class ExerciseGuide {
    /// Program + normalised name (see ExerciseGuideStore.storageKey), unique per exercise per program.
    var key: String = ""
    var name: String = ""
    /// The program it was explained for (e.g. "Insanity"); "" = general.
    var program: String = ""
    /// The AI wasn't sure which move the name means.
    var unsure: Bool = false
    var summary: String = ""
    var steps: [String] = []
    var tips: [String] = []
    var mistakes: [String] = []
    var muscles: [String] = []
    var easier: String = ""
    var harder: String = ""
    var safety: String = ""
    var createdAt: Date = Date()

    init(key: String, name: String, program: String) {
        self.key = key
        self.name = name
        self.program = program
        self.createdAt = Date()
    }

    /// Plain text for reading aloud.
    var spokenText: String {
        var parts = ["\(name). \(summary)"]
        if !steps.isEmpty {
            parts.append("How to do it. " + steps.enumerated().map { "Step \($0.offset + 1). \($0.element)" }.joined(separator: " "))
        }
        if !tips.isEmpty { parts.append("Tips. " + tips.joined(separator: " ")) }
        return parts.joined(separator: " ")
    }
}

extension TabataWorkout {
    /// Each exercise once, in order.
    var exerciseNames: [String] {
        let d = draft
        let names = d.parts.flatMap { part in (0..<part.cycles).map { part.exerciseName(cycle: $0) } }
        return ExerciseGuideStore.unique(names)
    }
}

extension RepWorkout {
    /// Each exercise once, in order.
    var exerciseNames: [String] {
        ExerciseGuideStore.unique(sets.flatMap(\.exercises).map(\.name))
    }
}

/// What the AI is told about where an exercise comes from, so it explains
/// the program's own version of a move (Insanity's "Heismans", not a guess).
struct ExerciseGuideContext: Equatable {
    /// Top-level folder, treated as the program (e.g. "Insanity"); "" if none.
    var program = ""
    var folderPath = ""
    var workoutName = ""
    var kind: WorkoutKind = .tabata
    var tags: [String] = []
    /// Every exercise in the workout, in order.
    var exercises: [String] = []

    static func make(workoutName: String, kind: WorkoutKind, folderID: UUID?, tags: [String],
                     exercises: [String], folders: [WorkoutFolder]) -> ExerciseGuideContext {
        let chain = WorkoutFolderTree.chain(from: folderID, in: folders)
        return ExerciseGuideContext(
            program: chain.last?.name ?? "",
            folderPath: chain.reversed().map(\.name).joined(separator: " › "),
            workoutName: workoutName,
            kind: kind,
            tags: WorkoutTags.clean(tags + chain.flatMap(\.tags)),
            exercises: exercises)
    }

    static func make(_ w: TabataWorkout, folders: [WorkoutFolder]) -> ExerciseGuideContext {
        make(workoutName: w.name, kind: .tabata, folderID: w.folderID, tags: w.tags, exercises: w.exerciseNames, folders: folders)
    }

    static func make(_ w: RepWorkout, folders: [WorkoutFolder]) -> ExerciseGuideContext {
        make(workoutName: w.name, kind: .reps, folderID: w.folderID, tags: w.tags, exercises: w.exerciseNames, folders: folders)
    }

    /// Same, reading folders from the database (for run screens).
    @MainActor
    static func load(workoutID: UUID, kind: WorkoutKind, context: ModelContext) -> ExerciseGuideContext? {
        let folders = (try? context.fetch(FetchDescriptor<WorkoutFolder>())) ?? []
        switch kind {
        case .tabata:
            let found = try? context.fetch(FetchDescriptor<TabataWorkout>(predicate: #Predicate { $0.id == workoutID }))
            return found?.first.map { make($0, folders: folders) }
        case .reps:
            let found = try? context.fetch(FetchDescriptor<RepWorkout>(predicate: #Predicate { $0.id == workoutID }))
            return found?.first.map { make($0, folders: folders) }
        }
    }

    var promptText: String {
        var lines: [String] = []
        if !program.isEmpty { lines.append("Program: \(program)") }
        if !folderPath.isEmpty && folderPath != program { lines.append("Folder: \(folderPath)") }
        lines.append("Workout: \(workoutName) (\(kind == .tabata ? "timed intervals / Tabata" : "sets and reps"))")
        if !tags.isEmpty { lines.append("Tags: \(tags.joined(separator: ", "))") }
        if !exercises.isEmpty { lines.append("All exercises in this workout, in order: \(exercises.joined(separator: "; "))") }
        return lines.joined(separator: "\n")
    }
}

enum ExerciseGuideStore {
    /// "Squat kick (right, then left)" and "squat  kick" share one guide.
    static func key(_ name: String) -> String {
        let noBrackets = name.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        return noBrackets.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,-"))
    }

    /// Placeholder names like "Work" have nothing to explain.
    static func isGuidable(_ name: String) -> Bool {
        let k = key(name)
        return !k.isEmpty && !["work", "rest", "prepare", "exercise"].contains(k)
    }

    /// Guidable names, first occurrence of each exercise kept.
    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { isGuidable($0) && seen.insert(key($0)).inserted }
    }

    /// Guides are kept per program: Insanity's "1-2-3" isn't a general one.
    static func storageKey(_ name: String, program: String) -> String {
        let p = key(program)
        return p.isEmpty ? key(name) : "\(p)|\(key(name))"
    }

    static func find(_ name: String, program: String, in guides: [ExerciseGuide]) -> ExerciseGuide? {
        let k = storageKey(name, program: program)
        return guides.first { $0.key == k }
    }

    static func missing(_ names: [String], program: String, in guides: [ExerciseGuide]) -> [String] {
        let have = Set(guides.map(\.key))
        return unique(names).filter { !have.contains(storageKey($0, program: program)) }
    }

    /// Fetches guides only for exercises that don't have one yet, a few per
    /// AI call, saving each batch as it arrives. `onProgress(done, total)`.
    @MainActor
    static func fetchMissing(_ names: [String], guideContext: ExerciseGuideContext, context: ModelContext,
                             onProgress: (Int, Int) -> Void = { _, _ in }) async throws {
        let existing = (try? context.fetch(FetchDescriptor<ExerciseGuide>())) ?? []
        let todo = missing(names, program: guideContext.program, in: existing)
        guard !todo.isEmpty else { return }
        var done = 0
        onProgress(0, todo.count)
        for start in stride(from: 0, to: todo.count, by: 6) {
            let batch = Array(todo[start..<min(start + 6, todo.count)])
            let drafts = try await ExerciseGuideAIService().guides(for: batch, guideContext: guideContext)
            for (name, draft) in zip(batch, drafts) {
                save(draft, name: name, program: guideContext.program, context: context)
            }
            try? context.save()
            done += batch.count
            onProgress(done, todo.count)
        }
    }

    /// Replaces one guide with a fresh AI version (only when asked).
    @MainActor
    static func regenerate(_ name: String, guideContext: ExerciseGuideContext, context: ModelContext) async throws {
        guard let draft = try await ExerciseGuideAIService().guides(for: [name], guideContext: guideContext).first else { return }
        let k = storageKey(name, program: guideContext.program)
        let old = (try? context.fetch(FetchDescriptor<ExerciseGuide>(predicate: #Predicate { $0.key == k }))) ?? []
        old.forEach(context.delete)
        save(draft, name: name, program: guideContext.program, context: context)
        try? context.save()
    }

    @MainActor
    private static func save(_ d: ExerciseGuideAIService.Draft, name: String, program: String, context: ModelContext) {
        let k = storageKey(name, program: program)
        // Another screen may have saved it meanwhile; keep one per exercise.
        if let found = try? context.fetch(FetchDescriptor<ExerciseGuide>(predicate: #Predicate { $0.key == k })), !found.isEmpty {
            return
        }
        let g = ExerciseGuide(key: k, name: name.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces), program: program)
        g.unsure = d.unsure ?? false
        g.summary = d.summary ?? ""
        g.steps = d.steps ?? []
        g.tips = d.tips ?? []
        g.mistakes = d.mistakes ?? []
        g.muscles = d.muscles ?? []
        g.easier = d.easier ?? ""
        g.harder = d.harder ?? ""
        g.safety = d.safety ?? ""
        context.insert(g)
    }
}

/// Asks OpenAI how to do exercises. Same plumbing as WorkoutAIService.
struct ExerciseGuideAIService {
    struct Draft: Decodable {
        var name: String?
        var summary: String?
        var steps: [String]?
        var tips: [String]?
        var mistakes: [String]?
        var muscles: [String]?
        var easier: String?
        var harder: String?
        var safety: String?
        var unsure: Bool?
    }

    enum GuideError: LocalizedError {
        case missingKey, badResponse
        var errorDescription: String? {
            switch self {
            case .missingKey: return "No OpenAI API key is set up in the app."
            case .badResponse: return "Couldn't read the AI's answer. Try again."
            }
        }
    }

    private let apiKey: String

    init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
    }

    /// One guide per name, in the same order.
    func guides(for names: [String], guideContext: ExerciseGuideContext) async throws -> [Draft] {
        guard !apiKey.isEmpty else { throw GuideError.missingKey }
        let list = names.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let systemPrompt = """
        You are a certified fitness coach who knows the popular home workout programs (Insanity, Insanity Max:30, \
        P90X, T25, 21 Day Fix, Les Mills and similar) move by move.
        Explain exercises to someone doing them at home, accurately.

        Where these exercises come from:
        \(guideContext.promptText)

        Rules for accuracy:
        - Use the program, folder and workout names to work out which program the moves come from.
        - When the program is a known one, explain the move exactly as THAT program teaches and names it \
        (its own version, pace and arm/leg pattern), not a generic exercise with a similar name.
        - Use the other exercises in the workout as clues (e.g. a list of Insanity moves means these are Insanity moves).
        - Text in brackets is extra detail about how the move is done in this workout (e.g. "each side"); include it.
        - Never invent a move. If you are not sure which move a name means, set "unsure": true, explain the most \
        likely move, and say in "summary" what the person should check against the program.

        For each exercise give:
        - "summary": one or two plain sentences on what the move is (say which program's version it is when known).
        - "steps": 3 to 6 short, clear steps to do it, from the starting position.
        - "tips": 2 or 3 form tips.
        - "mistakes": 2 or 3 common mistakes to avoid.
        - "muscles": main muscles worked, short names.
        - "easier": one easier variation. "harder": one harder variation.
        - "safety": one short safety note, or "" if none is needed.
        - "unsure": true or false.
        Keep the language simple. Respond with ONLY a JSON object:
        { "exercises": [ { "name": "", "summary": "", "steps": [], "tips": [], "mistakes": [], "muscles": [], "easier": "", "harder": "", "safety": "", "unsure": false } ] }
        with exactly one entry per exercise, in the same order.
        """
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": list]
            ],
            "max_tokens": 4000,
            "temperature": 0.2,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let text = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "ExerciseGuideAI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"])
        }

        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        struct Response: Decodable { let choices: [Choice] }
        struct Envelope: Decodable { let exercises: [Draft] }

        guard let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content,
              let json = content.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: json),
              envelope.exercises.count == names.count else {
            throw GuideError.badResponse
        }
        return envelope.exercises
    }
}

/// How many of a workout's (or folder's) exercises already have a saved guide.
struct GuideCoverage: Equatable {
    var saved = 0
    var total = 0

    var isComplete: Bool { total > 0 && saved == total }
    var isEmpty: Bool { saved == 0 }

    static func + (a: GuideCoverage, b: GuideCoverage) -> GuideCoverage {
        GuideCoverage(saved: a.saved + b.saved, total: a.total + b.total)
    }

    static func of(_ item: WorkoutItem, folders: [WorkoutFolder], guides: [ExerciseGuide]) -> GuideCoverage {
        let names = item.exerciseNames
        let program = WorkoutFolderTree.chain(from: item.folderID, in: folders).last?.name ?? ""
        let missing = ExerciseGuideStore.missing(names, program: program, in: guides).count
        return GuideCoverage(saved: names.count - missing, total: names.count)
    }

    /// Every workout in the folder and its subfolders.
    static func of(_ folder: WorkoutFolder, items: [WorkoutItem], folders: [WorkoutFolder], guides: [ExerciseGuide]) -> GuideCoverage {
        let ids = WorkoutFolderTree.descendants(of: folder.id, in: folders).union([folder.id])
        return items.filter { $0.folderID.map(ids.contains) ?? false }
            .reduce(GuideCoverage()) { $0 + of($1, folders: folders, guides: guides) }
    }
}
