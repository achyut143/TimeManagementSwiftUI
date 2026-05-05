import Foundation

struct AISchedulerService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init() {
        self.apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
    }

    struct TaskInput {
        let title: String
        let estimatedMinutes: Int
        let priority: String   // "P1","P2","P3" or "⭐" for five
        let isTimed: Bool
    }

    /// Calls GPT-4o to generate an optimised daily schedule.
    /// Returns the raw START…END block string ready to splice into notes.
    func generateSchedule(
        tasks: [TaskInput],
        currentTime: Date,
        selectedDate: Date,
        startNumber: Int
    ) async throws -> String {

        guard !tasks.isEmpty else { throw SchedulerError.noTasks }

        let cal  = Calendar.current
        let hour = cal.component(.hour,   from: currentTime)
        let min  = cal.component(.minute, from: currentTime)
        let h12  = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        let currentTimeStr = String(format: "%d:%02d %@", h12, min, ampm)

        let weekday = cal.weekdaySymbols[cal.component(.weekday, from: selectedDate) - 1]
        let dateStr: String = {
            let f = DateFormatter(); f.dateStyle = .medium
            return f.string(from: selectedDate)
        }()

        let taskLines = tasks.map { t -> String in
            let timeNote = t.estimatedMinutes > 0 ? "~\(t.estimatedMinutes) min" : "unknown duration"
            let star = t.priority == "⭐" ? " [STARRED]" : ""
            return "- \(t.title) (\(timeNote), \(t.priority)\(star))"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are an expert productivity scheduler. Your job is to produce a precise daily schedule for the user.

        TODAY'S CONTEXT
        - Day: \(weekday), \(dateStr)
        - Current time (schedule starts here): \(currentTimeStr)
        - Hard sleep cutoff: 11:00 PM — no tasks may be scheduled after this time
        - Task numbering starts at: \(startNumber)

        SCHEDULING RULES
        1. SPLITTING: Any task estimated >40 minutes MUST be split into parts named "Title (1/N)", "Title (2/N)" etc, each ≤40 min.
        2. MINIMUM HABIT: Never schedule a task for less than 15 minutes. If truly no time remains, drop it instead — never truncate below 15 min.
        3. BREAKS: Insert a 5-minute "Break" between every 2 consecutive work tasks. Insert a 10-minute "Walk / stretch" once in the afternoon.
        4. FUN ACTIVITIES: Add 1–2 enjoyable activities appropriate for the day and time:
           - Morning: "Morning coffee ☕" or "Light reading 📖"
           - Afternoon (weekday): "Short walk 🚶" or "Music break 🎵"
           - Evening: "Wind-down 🌙", "Journal ✍️"
           - Weekend: "Free time 🎉", "Creative time 🎨", "Outdoor break 🌿"
        5. PRIORITY ORDER when time runs short: ⭐ starred first, then P1 → P2 → P3. Drop lowest priority tasks first. Never mention dropped tasks in the output.
        6. SHRINKING: Before dropping a task entirely, try shrinking it to exactly 15 minutes (the habit minimum).
        7. NO OVERLAP: Each block must start exactly where the previous one ends. No gaps, no overlap.
        8. FORMAT: Output ONLY the schedule block — nothing else, no explanation, no markdown. The very first line must be START and the very last line must be END.

        OUTPUT FORMAT (strictly follow this, no deviation):
        START
        N) H:MM AM - H:MM AM - Task name
        N+1) H:MM AM - H:MM AM - Break
        ...
        END

        Time format: 1-or-2 digit hour, 2-digit minute, space, AM or PM. Example: 2:30 PM - 3:10 PM
        """

        let userMessage = """
        Schedule these tasks starting from \(currentTimeStr) today (\(weekday)):

        \(taskLines)

        Generate the full schedule now.
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user",   "content": userMessage]
        ]

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 2000,
            "temperature": 0.3
        ]

        guard let url = URL(string: baseURL) else { throw SchedulerError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "AIScheduler", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }

        struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        struct Response: Decodable { let choices: [Choice] }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw SchedulerError.noResponse
        }

        // Validate that output contains START…END
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.contains("START") && cleaned.contains("END") else {
            throw SchedulerError.badFormat(cleaned)
        }

        // Extract just the START…END block in case the model prefixed text
        let lines = cleaned.components(separatedBy: .newlines)
        var inside = false
        var result: [String] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" { inside = true; result.append("START"); continue }
            if t == "END"   { result.append("END"); break }
            if inside { result.append(line) }
        }
        guard result.first == "START", result.last == "END" else {
            throw SchedulerError.badFormat(cleaned)
        }
        return result.joined(separator: "\n")
    }

    enum SchedulerError: LocalizedError {
        case noTasks, invalidURL, noResponse, badFormat(String)
        var errorDescription: String? {
            switch self {
            case .noTasks:        return "No tasks to schedule."
            case .invalidURL:     return "Invalid API URL."
            case .noResponse:     return "No response from AI."
            case .badFormat(let s): return "Unexpected AI output:\n\(s.prefix(200))"
            }
        }
    }

    // MARK: - Helpers

    /// Derives an estimated duration in minutes from a Task.
    static func estimatedMinutes(startTime: String, endTime: String,
                                  timeSpent: Double?, elapsedTime: Double?) -> Int {
        // 1. timeSpent (actual logged minutes)
        if let ts = timeSpent, ts > 0 { return Int(ts) }
        // 2. elapsedTime (allocated minutes for untimed tasks)
        if let et = elapsedTime, et > 0 { return Int(et) }
        // 3. Derive from start/end time strings
        if !startTime.isEmpty && !endTime.isEmpty {
            let s = parseMinutes(startTime)
            let e = parseMinutes(endTime)
            if let s, let e, e > s { return e - s }
        }
        // 4. Default
        return 30
    }

    private static func parseMinutes(_ s: String) -> Int? {
        let clean = s.trimmingCharacters(in: .whitespaces)
        let isPM = clean.lowercased().contains("pm")
        let isAM = clean.lowercased().contains("am")
        let timeOnly = clean.replacingOccurrences(of: #"\s*[AaPp][Mm]"#, with: "", options: .regularExpression)
        let parts = timeOnly.components(separatedBy: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        var h = parts[0], m = parts[1]
        if isPM && h != 12 { h += 12 }
        if isAM && h == 12 { h = 0 }
        return h * 60 + m
    }
}
