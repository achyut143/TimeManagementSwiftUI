import Foundation

// Classifies new activities (the WHAT) against the user's existing WHY
// groups, or generates brand-new WHY + HOWs when none of them genuinely
// fit. Embeds the substantive framework from the user's own
// "Start With Why" / "Find Your Why" prompt (startWithaWhy-multiActivity-prompt.md)
// as the system prompt's substance, with a classification frame and a
// JSON-output directive added around it so the reply can be parsed into
// structured fields.
struct WhyHowWhatService {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"

    init() {
        self.apiKey = Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String ?? ""
    }

    // One existing WHY group, summarized just enough to let the model judge
    // fit — its own id (so a match can be reported back unambiguously), the
    // why statement itself, its current hows, and the activity names already
    // grouped under it (context: "does this new one belong with these?").
    struct ExistingWhy {
        let id: UUID
        let whyStatement: String
        let hows: [VirtueExplanation]
        let activityNames: [String]
    }

    struct Classification {
        // nil = none of the existing WHYs fit; a brand-new one was generated.
        let matchedWhyID: UUID?
        // The why statement to use going forward — unchanged from the
        // matched group's existing one in the common case, the model's
        // (minimally) broadened version if it needed to say so, or a fresh
        // one when matchedWhyID is nil.
        let whyStatement: String
        // The full HOW set for this why after folding in the new activity/
        // activities — replaces the matched group's stored hows outright (it
        // already includes anything worth keeping from before, plus
        // whatever's new).
        let hows: [VirtueExplanation]
        // Cleaned-up activity name(s) (the WHAT) that belong under this why.
        // Usually one, but classifyMultiple can cluster several new
        // activities under the same why in one Classification.
        let whats: [String]
    }

    // MARK: - Single activity, AI decides fit (used by "Re-classify with AI"
    // on an existing activity, and by Add Activity's "Auto" mode for a
    // single name).

    func classify(newActivityName: String, existingWhys: [ExistingWhy]) async throws -> Classification {
        let userMessage = Self.buildSingleUserMessage(newActivityName: newActivityName, existingWhys: existingWhys)
        let content = try await send(system: Self.classifySystemPrompt, user: userMessage)
        guard let parsed = Self.parseSingle(content, existingWhys: existingWhys) else {
            throw ServiceError.badFormat(content)
        }
        return parsed
    }

    // MARK: - Multiple new activities, AI decides fit AND groups them

    // Used by Add Activity's "Auto" mode when more than one activity name is
    // typed at once (or even just one — it degrades gracefully to a single
    // group). Each input activity ends up in exactly one returned
    // Classification: matched to an existing why, or clustered together with
    // other new activities from this same batch under a brand-new why.
    func classifyMultiple(newActivityNames: [String], existingWhys: [ExistingWhy]) async throws -> [Classification] {
        let names = newActivityNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return [] }
        let userMessage = Self.buildMultiUserMessage(newActivityNames: names, existingWhys: existingWhys)
        let content = try await send(system: Self.classifyMultipleSystemPrompt, user: userMessage)
        let parsed = Self.parseMultiple(content, existingWhys: existingWhys)
        guard !parsed.isEmpty else { throw ServiceError.badFormat(content) }
        return parsed
    }

    // MARK: - User-forced grouping ("add this to THIS why" or "make these
    // their own new why") — the grouping decision is already made; the AI's
    // only job is to write/update the why + hows so they genuinely cover
    // every activity that will now be under it (forcedWhy's existing
    // activities, if any, plus the new ones), and clean up the new names.

    func assignToWhy(activityNames: [String], forcedWhy: ExistingWhy?) async throws -> Classification {
        let names = activityNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { throw ServiceError.badFormat("(no activity names)") }
        let userMessage = Self.buildForcedUserMessage(newActivityNames: names, forcedWhy: forcedWhy)
        let content = try await send(system: Self.forcedSystemPrompt, user: userMessage)
        guard let parsed = Self.parseForced(content, forcedWhy: forcedWhy) else {
            throw ServiceError.badFormat(content)
        }
        return parsed
    }

    // MARK: - Regenerate just the WHY (keeping the same activities/Hows as context)

    func regenerateWhy(currentWhy: String, hows: [VirtueExplanation], activityNames: [String]) async throws -> String {
        let userMessage = Self.buildRegenerateWhyMessage(currentWhy: currentWhy, hows: hows, activityNames: activityNames)
        let content = try await send(system: Self.regenerateWhySystemPrompt, user: userMessage)
        guard let why = Self.parseWhyOnly(content) else {
            throw ServiceError.badFormat(content)
        }
        return why
    }

    // MARK: - Regenerate just ONE HOW (keeping the Why/activities/other Hows as context)

    func regenerateHow(why: String, otherHows: [VirtueExplanation], activityNames: [String], currentHow: VirtueExplanation?) async throws -> VirtueExplanation {
        let userMessage = Self.buildRegenerateHowMessage(why: why, otherHows: otherHows, activityNames: activityNames, currentHow: currentHow)
        let content = try await send(system: Self.regenerateHowSystemPrompt, user: userMessage)
        guard let how = Self.parseHowOnly(content) else {
            throw ServiceError.badFormat(content)
        }
        return how
    }

    // MARK: - Networking

    // Claude Opus 5 via the Messages API. Note: this model doesn't accept
    // `temperature`/`top_p`/`top_k` (400 if sent) — sampling controls were
    // removed for it — so the request is just model + system + one user
    // turn. Thinking is on by default for this model, so the response's
    // `content` array can contain `thinking` blocks alongside the final
    // `text` block; only the text blocks are the actual answer.
    private func send(system: String, user: String) async throws -> String {
        let requestBody: [String: Any] = [
            "model": "claude-opus-5",
            "max_tokens": 4096,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]

        guard let url = URL(string: baseURL) else { throw ServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "WhyHowWhatService", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }

        struct ContentBlock: Decodable { let type: String; let text: String? }
        struct Response: Decodable { let content: [ContentBlock] }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let content = decoded.content
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined()
        guard !content.isEmpty else {
            throw ServiceError.noResponse
        }
        return content
    }

    // MARK: - Shared framework text, reused verbatim across all prompts
    // below. This is startWithaWhy-multiActivity-prompt.md's own Definitions
    // + Critical Rules + Quality Check sections, essentially word-for-word —
    // no added rules beyond what's in that file. (A tightened version with
    // several extra anti-vagueness/anti-fabrication rules was tried and then
    // reverted at the user's request; it's saved in
    // startWithaWhy-tightened-prompt-backup.md in case it's wanted again.)

    private static let framework = """
    Definitions

    WHAT = Activity
    The actual thing the person is doing.

    HOW = Values in Action
    The behaviors, virtues, principles, strengths, and ways of operating that
    someone consistently demonstrates when they are at their best.

    Important: HOWs are not abstract values. A HOW should describe what the value
    looks like in action. For example:

    Integrity -> Tell the truth even when it is uncomfortable
    Curiosity -> Ask questions to deeply understand
    Kindness -> Treat people with respect and empathy
    Growth -> Continuously improve and learn

    WHY = Purpose
    The deeper belief, cause, contribution, impact, or meaning behind the
    activity. A WHY should remain true even if the activity changes.

    Example (single activity)
    Activity: Running
    WHAT: Running
    HOW: Maintain discipline; Push personal limits; Build healthy habits
    WHY: To continuously improve myself so that I can become the best version
    of myself.

    Critical Rules

    1. Never return the activity itself as the WHY.

       Activity: Exercise
       WHY: "To exercise" — incorrect, this is still a WHAT
       WHY: "To stay fit" — incorrect, this is still an outcome
       WHY: "To continuously grow and challenge myself" — correct
       WHY: "To build resilience and confidence" — correct
       WHY: "To maintain the energy needed to serve others" — correct

    2. Use the "Could this still exist?" test.

       Ask: "Could this purpose still be fulfilled if the activity disappeared?"
       If YES -> it may be a valid WHY.
       If NO -> it is probably still a WHAT or HOW.

       Example: Could the person still live "To continuously learn and grow"
       without reading books? YES. Therefore: Reading books = WHAT; Learning and
       growth = WHY.

    3. Use the 5 Whys technique. Continue asking "Why is that important?"
       until you reach a purpose that is independent of the activity.

       Example:
       I exercise. Why? -> To stay healthy. Why? -> To have energy. Why? -> To
       perform at my best. Why? -> To contribute meaningfully to others. Why? ->
       Because helping others gives my life meaning.
       Final WHY: To contribute positively to the lives of others so that
       people can thrive.

    4. When grouping, only merge activities under one shared WHY if that WHY
       would pass the same tests above for every activity in the group — not
       just a vague surface similarity. Two activities that both "make me feel
       good" are not automatically the same WHY; the deeper purpose has to
       genuinely be the same one.

    Quality Check
    Before presenting the final answer, verify for every activity and every group:
    - Activity = WHAT
    - Behaviors/virtues in action = HOW
    - Purpose/contribution/meaning = WHY
    - WHY remains true even if the activity changes
    - HOWs are actionable
    - WHY is deeper than the activity itself
    - Grouped activities genuinely share the same underlying WHY, not just a
      surface-level resemblance
    - Explanations use simple, non-technical language
    """

    // MARK: - Prompt: single activity, auto

    private static let classifySystemPrompt = """
    You are an expert purpose coach trained in Simon Sinek's "Start With Why" and "Find Your Why" frameworks.

    \(framework)

    Task
    I will give you ONE new activity, and a list of my EXISTING WHY groups (each with an id, its current WHY statement, its current HOWs, and the activities already grouped under it).

    Decide:
    - Does the new activity genuinely belong under one of the EXISTING WHYs — would the "could this still exist" test hold for that same shared purpose across this activity too, not just a surface-level resemblance to the other activities already there?
    - If YES: use that WHY's id as matchedWhyId. Keep its whyStatement unchanged unless it is genuinely necessary to broaden it slightly so it accurately covers the new activity too — prefer leaving it exactly as-is when possible. If the existing whyStatement is not already in the "To ... so that ..." form, rephrase it into that form without changing its meaning. Return the full HOW list for that WHY after folding in this activity: keep any existing HOWs that still apply, and add any new HOW(s) genuinely needed to describe how this new activity also exercises the same purpose. Do not add a HOW that's already covered by an existing one, and do not remove a HOW that still applies to the group's other activities.
    - If NO existing WHY genuinely fits: set matchedWhyId to null, and generate a brand-new WHY (following the rules above, in the "To ... so that ..." form) plus 2 to 5 HOWs specific to this new activity.

    Also clean up the activity name: fix typos, capitalization, and phrasing into a concise, proper activity title (e.g. "cold showers" -> "Cold Showers"), without changing what it means.

    Respond ONLY with valid JSON, no markdown, no code fences, no extra text, in exactly this shape:
    {"matchedWhyId": "<one of the existing why ids I gave you, or JSON null if none fit>", "whyStatement": "To <do/be/give something> so that <the deeper impact> — existing (reformatted into this shape if needed), lightly broadened, or brand new", "hows": [{"virtueName": "value name", "howExercised": "what it looks like in action"}], "what": "cleaned-up activity name"}
    """

    private static func buildSingleUserMessage(newActivityName: String, existingWhys: [ExistingWhy]) -> String {
        var lines: [String] = ["New activity: \(newActivityName)", ""]
        lines.append(contentsOf: existingWhysLines(existingWhys))
        return lines.joined(separator: "\n")
    }

    private static func parseSingle(_ raw: String, existingWhys: [ExistingWhy]) -> Classification? {
        guard let data = cleanedJSONData(from: raw) else { return nil }

        struct RawHow: Decodable { let virtueName: String; let howExercised: String }
        struct RawResponse: Decodable {
            let matchedWhyId: String?
            let whyStatement: String
            let hows: [RawHow]
            let what: String
        }

        guard let decoded = try? JSONDecoder().decode(RawResponse.self, from: data) else { return nil }

        let matchedID = validatedMatch(decoded.matchedWhyId, in: existingWhys)
        let hows = VirtueExplanation.merged(decoded.hows.map { VirtueExplanation(virtueName: $0.virtueName, howExercised: $0.howExercised) })
        let what = decoded.what.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !what.isEmpty else { return nil }

        return Classification(matchedWhyID: matchedID, whyStatement: decoded.whyStatement, hows: hows, whats: [what])
    }

    // MARK: - Prompt: multiple new activities, auto (AI both classifies AND groups)

    private static let classifyMultipleSystemPrompt = """
    You are an expert purpose coach trained in Simon Sinek's "Start With Why" and "Find Your Why" frameworks.

    \(framework)

    Task
    I will give you SEVERAL new activities at once, and a list of my EXISTING WHY groups (each with an id, its current WHY statement, its current HOWs, and the activities already grouped under it).

    For each new activity, decide whether it genuinely belongs under one of the EXISTING WHYs (same "could this still exist" test as above), or whether it doesn't fit any of them.

    Then group the new activities into output groups:
    - New activities that genuinely belong under the SAME existing WHY all go into one output group referencing that WHY's id as matchedWhyId, with the HOW list for that WHY updated to also cover all of them (keep existing HOWs that still apply, add any new ones genuinely needed, don't duplicate, don't remove HOWs that still apply to that WHY's other activities).
    - New activities that don't fit any existing WHY, but genuinely share the SAME underlying purpose with each other (not just a surface resemblance — the same purpose would have to pass the "could this still exist" test across all of them), go into one output group with matchedWhyId null and a brand-new WHY + HOWs covering all of them together.
    - A new activity that doesn't fit any existing WHY and doesn't genuinely share a purpose with any other new activity in this batch gets its own output group, matchedWhyId null, with its own brand-new WHY + HOWs.

    Every new activity I give you must appear in exactly one output group's "whats" list — never drop one, never duplicate one across groups. Only merge activities into the same group when the shared WHY would genuinely pass the "could this still exist" test for every one of them, not because they superficially resemble each other.

    Also clean up each activity's name: fix typos, capitalization, and phrasing into a concise, proper activity title, without changing what it means.

    Respond ONLY with valid JSON, no markdown, no code fences, no extra text, in exactly this shape:
    {"groups": [{"matchedWhyId": "<an existing why id, or JSON null for a new why>", "whyStatement": "To <do/be/give something> so that <the deeper impact>", "hows": [{"virtueName": "value name", "howExercised": "what it looks like in action"}], "whats": ["cleaned activity name", "..."]}]}
    """

    private static func buildMultiUserMessage(newActivityNames: [String], existingWhys: [ExistingWhy]) -> String {
        var lines: [String] = ["New activities:"]
        lines.append(contentsOf: newActivityNames.map { "- \($0)" })
        lines.append("")
        lines.append(contentsOf: existingWhysLines(existingWhys))
        return lines.joined(separator: "\n")
    }

    private static func parseMultiple(_ raw: String, existingWhys: [ExistingWhy]) -> [Classification] {
        guard let data = cleanedJSONData(from: raw) else { return [] }

        struct RawHow: Decodable { let virtueName: String; let howExercised: String }
        struct RawGroup: Decodable {
            let matchedWhyId: String?
            let whyStatement: String
            let hows: [RawHow]
            let whats: [String]
        }
        struct RawResponse: Decodable { let groups: [RawGroup] }

        guard let decoded = try? JSONDecoder().decode(RawResponse.self, from: data) else { return [] }

        return decoded.groups.compactMap { group in
            let whats = group.whats.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !whats.isEmpty else { return nil }
            let matchedID = validatedMatch(group.matchedWhyId, in: existingWhys)
            let hows = VirtueExplanation.merged(group.hows.map { VirtueExplanation(virtueName: $0.virtueName, howExercised: $0.howExercised) })
            return Classification(matchedWhyID: matchedID, whyStatement: group.whyStatement, hows: hows, whats: whats)
        }
    }

    // MARK: - Prompt: user-forced grouping

    private static let forcedSystemPrompt = """
    You are an expert purpose coach trained in Simon Sinek's "Start With Why" and "Find Your Why" frameworks.

    \(framework)

    Task
    I have already decided that one or more NEW activities belong together under a single WHY — either an EXISTING one (given below, along with the activities already under it), or a brand-new one if none is given. You are NOT deciding whether they belong together — that's already decided. Your job is only to:

    1. Write or update the WHY statement so it genuinely and accurately covers every activity that will now be under it (the existing ones listed, if any, plus the new ones) — in the "To ... so that ..." form. If an existing WHY is given, keep it unchanged unless it's genuinely necessary to broaden it so it truly covers the new activities too; prefer minimal changes.
    2. Produce the full HOW list covering all of those activities together: keep any existing HOWs that still apply, add any new ones genuinely needed for the new activities, don't duplicate, don't remove ones that still apply.
    3. Clean up each new activity's name: fix typos, capitalization, and phrasing into a concise, proper activity title, without changing what it means.

    Respond ONLY with valid JSON, no markdown, no code fences, no extra text, in exactly this shape:
    {"whyStatement": "To <do/be/give something> so that <the deeper impact>", "hows": [{"virtueName": "value name", "howExercised": "what it looks like in action"}], "whats": ["cleaned new activity name", "..."]}
    """

    private static func buildForcedUserMessage(newActivityNames: [String], forcedWhy: ExistingWhy?) -> String {
        var lines: [String] = ["New activities to add:"]
        lines.append(contentsOf: newActivityNames.map { "- \($0)" })
        lines.append("")
        if let forcedWhy {
            lines.append("Existing WHY these must be added to:")
            lines.append("Why: \(forcedWhy.whyStatement)")
            if !forcedWhy.hows.isEmpty {
                let howsList = forcedWhy.hows.map { "\($0.virtueName): \($0.howExercised)" }.joined(separator: "; ")
                lines.append("Hows: \(howsList)")
            }
            if !forcedWhy.activityNames.isEmpty {
                lines.append("Activities already here: \(forcedWhy.activityNames.joined(separator: ", "))")
            }
        } else {
            lines.append("No existing WHY given — these activities form a brand-new WHY together.")
        }
        return lines.joined(separator: "\n")
    }

    private static func parseForced(_ raw: String, forcedWhy: ExistingWhy?) -> Classification? {
        guard let data = cleanedJSONData(from: raw) else { return nil }

        struct RawHow: Decodable { let virtueName: String; let howExercised: String }
        struct RawResponse: Decodable {
            let whyStatement: String
            let hows: [RawHow]
            let whats: [String]
        }

        guard let decoded = try? JSONDecoder().decode(RawResponse.self, from: data) else { return nil }

        let whats = decoded.whats.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !whats.isEmpty else { return nil }
        let hows = VirtueExplanation.merged(decoded.hows.map { VirtueExplanation(virtueName: $0.virtueName, howExercised: $0.howExercised) })

        return Classification(matchedWhyID: forcedWhy?.id, whyStatement: decoded.whyStatement, hows: hows, whats: whats)
    }

    // MARK: - Prompt: regenerate just the WHY

    private static let regenerateWhySystemPrompt = """
    You are an expert purpose coach trained in Simon Sinek's "Start With Why" and "Find Your Why" frameworks.

    \(framework)

    Task
    I will give you a WHY that already covers one or more activities, along with its current HOWs and the activities themselves. Write a fresh WHY statement that still genuinely covers all of these activities (it must pass the "could this still exist" test across every one of them). Give a genuinely different angle or phrasing from the current one — a fresh take, not a trivial reword — while staying true to what actually connects these activities. Still follow the "To ... so that ..." form and all the critical rules above.

    Respond ONLY with valid JSON, no markdown, no code fences, no extra text, in exactly this shape:
    {"whyStatement": "To <do/be/give something> so that <the deeper impact>"}
    """

    private static func buildRegenerateWhyMessage(currentWhy: String, hows: [VirtueExplanation], activityNames: [String]) -> String {
        var lines = ["Current Why: \(currentWhy)"]
        if !hows.isEmpty {
            lines.append("Current Hows: " + hows.map { "\($0.virtueName): \($0.howExercised)" }.joined(separator: "; "))
        }
        if !activityNames.isEmpty {
            lines.append("Activities under this Why: " + activityNames.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    private static func parseWhyOnly(_ raw: String) -> String? {
        guard let data = cleanedJSONData(from: raw) else { return nil }
        struct RawResponse: Decodable { let whyStatement: String }
        guard let decoded = try? JSONDecoder().decode(RawResponse.self, from: data) else { return nil }
        let why = decoded.whyStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        return why.isEmpty ? nil : why
    }

    // MARK: - Prompt: regenerate just ONE HOW

    private static let regenerateHowSystemPrompt = """
    You are an expert purpose coach trained in Simon Sinek's "Start With Why" and "Find Your Why" frameworks.

    \(framework)

    Task
    I will give you a WHY, the activities grouped under it, and the OTHER Hows already listed for it (so you don't duplicate any of them). Generate ONE new HOW — a value name plus what it looks like in action — that genuinely and specifically fits this Why and at least one of these activities. It must be concrete and actionable, not generic filler that could apply to almost anything, and it must not restate a value or angle already covered by the other Hows listed.

    Respond ONLY with valid JSON, no markdown, no code fences, no extra text, in exactly this shape:
    {"virtueName": "value name", "howExercised": "what it looks like in action"}
    """

    private static func buildRegenerateHowMessage(why: String, otherHows: [VirtueExplanation], activityNames: [String], currentHow: VirtueExplanation?) -> String {
        var lines = ["Why: \(why)"]
        if !activityNames.isEmpty {
            lines.append("Activities under this Why: " + activityNames.joined(separator: ", "))
        }
        if !otherHows.isEmpty {
            lines.append("Other Hows already listed (do not duplicate): " + otherHows.map { "\($0.virtueName): \($0.howExercised)" }.joined(separator: "; "))
        }
        if let currentHow, !currentHow.virtueName.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("The How being replaced (feel free to keep its value name if it's still a good fit, or pick a different one): \(currentHow.virtueName): \(currentHow.howExercised)")
        }
        return lines.joined(separator: "\n")
    }

    private static func parseHowOnly(_ raw: String) -> VirtueExplanation? {
        guard let data = cleanedJSONData(from: raw) else { return nil }
        struct RawResponse: Decodable { let virtueName: String; let howExercised: String }
        guard let decoded = try? JSONDecoder().decode(RawResponse.self, from: data) else { return nil }
        let name = decoded.virtueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return VirtueExplanation(virtueName: name, howExercised: decoded.howExercised)
    }

    // MARK: - Shared parsing/formatting helpers

    private static func existingWhysLines(_ existingWhys: [ExistingWhy]) -> [String] {
        guard !existingWhys.isEmpty else { return ["Existing WHY groups: (none yet)"] }
        var lines = ["Existing WHY groups:"]
        for why in existingWhys {
            lines.append("- id: \(why.id.uuidString)")
            lines.append("  Why: \(why.whyStatement)")
            if !why.hows.isEmpty {
                let howsList = why.hows.map { "\($0.virtueName): \($0.howExercised)" }.joined(separator: "; ")
                lines.append("  Hows: \(howsList)")
            }
            if !why.activityNames.isEmpty {
                lines.append("  Activities already here: \(why.activityNames.joined(separator: ", "))")
            }
        }
        return lines
    }

    // Only trust a matchedWhyId that actually names one of the groups we
    // offered — anything else (a hallucinated id, or a match against a
    // group that no longer exists) falls back to "no match", which is the
    // safe outcome (a new group gets created rather than silently attaching
    // to the wrong one, or to nothing).
    private static func validatedMatch(_ rawID: String?, in existingWhys: [ExistingWhy]) -> UUID? {
        rawID.flatMap { UUID(uuidString: $0) }
            .flatMap { id in existingWhys.contains { $0.id == id } ? id : nil }
    }

    // Tolerates a bare JSON object/array or one wrapped in ```json fences.
    private static func cleanedJSONData(from raw: String) -> Data? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.data(using: .utf8)
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
