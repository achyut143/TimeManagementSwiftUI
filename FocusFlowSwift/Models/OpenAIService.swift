import Foundation



class OpenAIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    init() {
        // Load API key from Config.xcconfig or use empty string as fallback
        if let path = Bundle.main.path(forResource: "Config", ofType: "xcconfig"),
           let contents = try? String(contentsOfFile: path),
           let keyLine = contents.components(separatedBy: .newlines).first(where: { $0.contains("OPENAI_API_KEY") }) {
            let key = keyLine.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) ?? ""
            self.apiKey = key
        } else {
            self.apiKey = ""
        }
    }

    
    
    func generateTasks(from prompt: String) async throws -> [TaskData] {
        let systemPrompt = """
        Extract task information from the user's input and return ONLY a JSON array of task objects. For multiple tasks, create separate objects:
        [
            {
                "title": "task title",
                "description": "comma separated tags",
                "startTime": "h:mm a format",
                "endTime": "h:mm a format", 
                "weight": 1,
                "date": "today or specific date if mentioned",
                "priority": "P3"
            }
        ]
        Use AM/PM format for times. If date is not specified, use today. Always set weight to 1 unless explicitly specified otherwise. If start time is not mentioned, use 12:00 AM as start time and 12:20 AM as end time. If only start time is mentioned, create a 30 minute task ending 30 minutes after start time. Current time is \(Date().formatted(date: .omitted, time: .shortened)). Current year is \(Calendar.current.component(.year, from: Date())). If no year is mentioned, use current year.
        """
        
        let messages = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": prompt]
        ]
        
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": messages,
            "max_tokens": 150,
            "temperature": 0.3
        ]
        
        guard let url = URL(string: baseURL) else {
            throw OpenAIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Debug: Print the raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("OpenAI Response: \(responseString)")
        }
        
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = response.choices.first?.message.content else {
            throw OpenAIError.noResponse
        }
        
        return try parseTasksData(from: content)
    }
    
    private func parseTasksData(from jsonString: String) throws -> [TaskData] {
        guard let data = jsonString.data(using: .utf8) else {
            throw OpenAIError.invalidResponse
        }
        return try JSONDecoder().decode([TaskData].self, from: data)
    }
    
    func generateWhyStatement(for taskTitle: String, description: String = "", persistentNotes: String? = nil, notes: String? = nil) async throws -> String {
        // Extract tags from notes
        let tags = extractTags(from: notes)
        
        // Extract content between START and END/=Completed tags, excluding completed items
        var contextInfo = ""
        
        if let persistentNotes = persistentNotes {
            // Extract active content (between START and END or =Completed)
            if let startRange = persistentNotes.range(of: "START", options: .caseInsensitive) {
                // Find the end marker - either =Completed or END
                var endMarkerRange: Range<String.Index>?
                
                // Check for =Completed first
                if let completedRange = persistentNotes.range(of: "=Completed", options: .caseInsensitive, range: startRange.upperBound..<persistentNotes.endIndex) {
                    endMarkerRange = completedRange
                } else if let endRange = persistentNotes.range(of: "END", options: .caseInsensitive, range: startRange.upperBound..<persistentNotes.endIndex) {
                    endMarkerRange = endRange
                }
                
                if let endMarker = endMarkerRange, startRange.upperBound < endMarker.lowerBound {
                    let extractedContent = String(persistentNotes[startRange.upperBound..<endMarker.lowerBound])
                    contextInfo = extractedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                // If no START tag, use all persistent notes but exclude completed section
                if let completedRange = persistentNotes.range(of: "=Completed", options: .caseInsensitive) {
                    contextInfo = String(persistentNotes[..<completedRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    contextInfo = persistentNotes
                }
            }
        }
        
        // Customize system prompt based on tags
        var systemPrompt = getCustomSystemPrompt(for: tags, defaultPrompt: """
You are a motivational coach who helps people understand their deeper purpose and build an unshakeable mindset. Generate a compelling motivational block for the given task with FOUR parts:

1. An identity statement (who they ARE, not just what they're doing)
2. A resilience reminder (not every day goes your way — but that's the point)
3. A selfish reason (personal benefit)
4. A selfless reason (benefit to others)

Format:
"I am [identity statement] — someone who [character trait tied to the task].
Not every day will go my way. But every day I show up is a vote for who I'm becoming. I train not to guarantee the outcome — I train to deserve it.

---
I do this for me: [selfish reason].
I do this for others: [selfless reason]."

Guidelines:
- The identity statement should feel like a label they *own*, not a goal they're chasing
- The resilience line should separate effort (controllable) from outcome (uncontrollable) — Stoic style
- The selfish + selfless reasons should feel like a natural emotional landing after the mindset block
- Be specific to the task, emotionally resonant, and avoid generic clichés
- Use any provided context (persistent notes, current notes, description) to make it personal

Examples:
- "I am an athlete — someone who shows up even when motivation is absent.
  Not every session will feel great. But every rep is evidence that I don't quit when it gets hard.

  ---
  I do this for me: to build a body and mind I'm proud of.
  I do this for others: so the people watching me learn that showing up is always enough."

- "I am a builder — someone who turns frustration into curiosity and problems into solutions.
  Not every bug will be solved today. But every hour I spend is compounding into mastery I can't yet see.

  ---
  I do this for me: to unlock creative freedom and a career built on my own terms.
  I do this for others: to create tools that make someone's day a little easier and more joyful."

- "I am someone who chooses stillness — even when the world is loud and my mind is louder.
  Not every session will feel peaceful. But sitting down anyway is the practice — and the practice is the point.

  ---
  I do this for me: to find clarity and calm in the chaos of daily life.
  I do this for others: to show up more present and patient for the people who need me most."
""")
        
        var userPrompt = "Task: \(taskTitle)"
        
        if !description.isEmpty {
            userPrompt += "\nDescription: \(description)"
        }
        
        if !contextInfo.isEmpty {
            userPrompt += "\nGuidelines/Context: \(contextInfo)"
        }
        
        if let notes = notes, !notes.isEmpty {
            userPrompt += "\nCurrent Notes: \(notes)"
        }
        
        userPrompt += "\n\nGenerate a personalized why statement for this task:"
        
        let messages = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
        
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": messages,
            "max_tokens": 100,
            "temperature": 0.8
        ]
        
        guard let url = URL(string: baseURL) else {
            throw OpenAIError.invalidURL
        }
        
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
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func generateTaskSuggestions(taskTitle: String, persistentNotes: String?, currentNotes: String?, dayOfWeek: String, date: Date) async throws -> String {
        // Extract content between START and END tags, excluding completed items
        var contextInfo = ""
        var completedInfo = ""
        
        if let persistentNotes = persistentNotes {
            // First, extract completed items (between =Completed and End)
            if let completedRange = persistentNotes.range(of: "=Completed", options: .caseInsensitive),
               let endRange = persistentNotes.range(of: "End", options: .caseInsensitive, range: completedRange.upperBound..<persistentNotes.endIndex),
               completedRange.upperBound < endRange.lowerBound {
                let extractedCompleted = String(persistentNotes[completedRange.upperBound..<endRange.lowerBound])
                completedInfo = extractedCompleted.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Then extract active content (between START and END or =Completed)
            if let startRange = persistentNotes.range(of: "START", options: .caseInsensitive) {
                // Find the end marker - either =Completed or END
                var endMarkerRange: Range<String.Index>?
                
                // Check for =Completed first
                if let completedRange = persistentNotes.range(of: "=Completed", options: .caseInsensitive, range: startRange.upperBound..<persistentNotes.endIndex) {
                    endMarkerRange = completedRange
                } else if let endRange = persistentNotes.range(of: "END", options: .caseInsensitive, range: startRange.upperBound..<persistentNotes.endIndex) {
                    endMarkerRange = endRange
                }
                
                if let endMarker = endMarkerRange, startRange.upperBound < endMarker.lowerBound {
                    let extractedContent = String(persistentNotes[startRange.upperBound..<endMarker.lowerBound])
                    contextInfo = extractedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                // If no START tag, use all persistent notes but exclude completed section
                if let completedRange = persistentNotes.range(of: "=Completed", options: .caseInsensitive) {
                    contextInfo = String(persistentNotes[..<completedRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    contextInfo = persistentNotes
                }
            }
        }
        
        let systemPrompt = """
        You are an expert task planning assistant who provides DEEP, SPECIFIC, and ACTIONABLE recommendations. Your suggestions should go beyond surface-level advice.
        
        CRITICAL REQUIREMENTS:
        1. For learning tasks: Provide specific concepts, technologies, frameworks, algorithms, or theories to study
        2. For technical topics: Include actual technology names, tools, libraries, and specific techniques
        3. For workouts: Include specific exercises with sets, reps, and form cues
        4. For projects: Break down into concrete sub-tasks with specific deliverables
        5. Always include WHY each item matters and HOW it connects to the bigger picture
        6. IGNORE any completed items - focus ONLY on active/pending tasks
        
        FORMAT YOUR RESPONSE AS:
        - Numbered action items with specific details
        - Include concrete examples, not generic advice
        - Add resource suggestions (specific articles, docs, or tools)
        - Provide time estimates for each item
        - Connect items to show progression
        
        EXAMPLES OF GOOD VS BAD:
        ❌ BAD: "Research AI trends"
        ✅ GOOD: "Study Transformer architecture (30 min) - Read 'Attention Is All You Need' paper, understand self-attention mechanism and how it powers GPT models"
        
        ❌ BAD: "Learn about databases"
        ✅ GOOD: "Master database indexing (45 min) - Study B-tree vs Hash indexes, practice creating composite indexes in PostgreSQL, understand query optimization with EXPLAIN ANALYZE"
        
        ❌ BAD: "Do chest exercises"
        ✅ GOOD: "Barbell Bench Press: 4 sets x 8 reps (focus on scapular retraction, controlled eccentric phase, explosive concentric)"
        
        Be SPECIFIC. Be TECHNICAL. Be ACTIONABLE. Go DEEP.
        """
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        let formattedDate = dateFormatter.string(from: date)
        
        var userPrompt = """
        Task: \(taskTitle)
        Day: \(dayOfWeek)
        Date: \(formattedDate)
        """
        
        if !contextInfo.isEmpty {
            userPrompt += "\n\nActive Tasks/Guidelines:\n\(contextInfo)"
        }
        
        if !completedInfo.isEmpty {
            userPrompt += "\n\nCompleted Items (DO NOT suggest these):\n\(completedInfo)"
        }
        
        if let currentNotes = currentNotes, !currentNotes.isEmpty {
            userPrompt += "\n\nCurrent Notes:\n\(currentNotes)"
        }
        
        userPrompt += "\n\nGenerate specific suggestions for what to do for this task today. Focus ONLY on active/pending items, NOT completed ones:"
        
        let messages = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
        
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": messages,
            "max_tokens": 500,
            "temperature": 0.7
        ]
        
        guard let url = URL(string: baseURL) else {
            throw OpenAIError.invalidURL
        }
        
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
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Tag Detection and Custom Prompts
    
    /// Extracts tags from notes text (words in quotes or hashtags)
    private func extractTags(from text: String?) -> [String] {
        guard let text = text else { return [] }
        
        var tags: [String] = []
        
        // Extract quoted words: "motivate", "end", etc.
        let quotePattern = "\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: quotePattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    tags.append(String(text[range]).lowercased())
                }
            }
        }
        
        // Extract hashtags: #motivate, #end, etc.
        let hashtagPattern = "#(\\w+)"
        if let regex = try? NSRegularExpression(pattern: hashtagPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    tags.append(String(text[range]).lowercased())
                }
            }
        }
        
        return tags
    }
    
    /// Returns a custom system prompt based on detected tags
    private func getCustomSystemPrompt(for tags: [String], defaultPrompt: String) -> String {
        // Check for specific tags and return custom prompts
        if tags.contains("motivate") {
            return """
You are an INTENSE motivational coach who delivers POWERFUL, DIRECT, and UNCOMPROMISING motivation. Your job is to IGNITE ACTION and DESTROY EXCUSES.

Generate a HARD-HITTING motivational message with THREE parts:

1. A BRUTAL TRUTH (call out the reality they're avoiding)
2. An IDENTITY SHIFT (who they need to become RIGHT NOW)
3. A CHALLENGE (what they must do TODAY to prove themselves)

Format:
"[BRUTAL TRUTH about their current state or what they're avoiding]

You're not [weak identity]. You're [strong identity] — someone who [powerful action/trait].

TODAY'S CHALLENGE: [Specific, measurable action they must take]"

Guidelines:
- Be DIRECT and INTENSE, but not cruel
- Use CAPS for emphasis on key words
- Make it PERSONAL and SPECIFIC to their task
- Focus on ACTION, not feelings
- Challenge them to PROVE themselves TODAY
- No fluff, no generic advice — PURE FIRE

Examples:
- "You know what you need to do. You've known for weeks. The only thing stopping you is the story you keep telling yourself about 'not being ready.'

You're not someone who waits for permission. You're a BUILDER — someone who ships before they're ready and learns by DOING.

TODAY'S CHALLENGE: Write 100 lines of code. Not perfect code. Not production-ready code. Just 100 lines that EXIST."

- "Every day you skip this, you're voting for the person you DON'T want to be. That's not motivation — that's MATH.

You're not someone who 'tries their best.' You're an ATHLETE — someone who shows up when it SUCKS because that's when it COUNTS.

TODAY'S CHALLENGE: 30 minutes. No phone. No excuses. MOVE."

Be FIERCE. Be DIRECT. Make them MOVE.
"""
        }
        
        if tags.contains("end") {
            return """
You are a reflective coach who helps people process their day with HONESTY and GROWTH. Generate a powerful end-of-day reflection with THREE parts:

1. ACKNOWLEDGMENT (what they actually did today — no judgment)
2. LESSON (what they learned about themselves)
3. TOMORROW'S EDGE (one small way to be 1% better)

Format:
"Today you [specific actions taken].

Here's what that tells you: [insight about their character, patterns, or growth].

Tomorrow's edge: [One specific, actionable improvement]."

Guidelines:
- Be HONEST but COMPASSIONATE
- Focus on LEARNING, not judging
- Celebrate EFFORT, not just results
- Make tomorrow's edge SMALL and SPECIFIC
- Connect today's actions to their bigger journey
- No toxic positivity — real growth requires real honesty

Examples:
- "Today you showed up for 20 minutes when you planned for 60.

Here's what that tells you: You're still learning to calibrate ambition with reality. That's not failure — that's data. 20 minutes is infinitely more than 0.

Tomorrow's edge: Start with 25 minutes. Build the habit of exceeding your target, not falling short."

- "Today you skipped the workout but crushed your work tasks.

Here's what that tells you: You prioritize what feels urgent over what's important. Your body is a long-term investment that never feels urgent until it's too late.

Tomorrow's edge: Put the workout FIRST. Before email. Before Slack. Before anything that can wait."

Be HONEST. Be KIND. Help them GROW.
"""
        }
        
        // Add more tag-specific prompts here as needed
        
        // Return default prompt if no special tags found
        return defaultPrompt
    }
}

struct TaskData: Codable {
    let title: String
    let description: String
    let startTime: String
    let endTime: String
    let weight: Double
    let date: String
    let priority: String
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