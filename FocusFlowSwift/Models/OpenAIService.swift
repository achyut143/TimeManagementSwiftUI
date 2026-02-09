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
        
        let systemPrompt = """
        You are a motivational coach who helps people understand their deeper purpose. Generate a compelling "why statement" for the given task that has TWO parts:
        1. A selfish reason (personal benefit)
        2. A selfless reason (benefit to others)
        
        Format: "[Selfish reason]. [Selfless reason]."
        
        Keep it to 2 lines maximum. Be creative, inspiring, and specific to the task. Make it personal and emotionally resonant.
        Use any provided context (persistent notes, current notes, description) to make the why statement more specific and meaningful.
        
        Examples:
        - "I'm working out to build strength and confidence in my body. So I can inspire others to prioritize their health and show them what's possible."
        - "I'm learning to code to unlock creative freedom and career opportunities. So I can build tools that make people's lives easier and more joyful."
        - "I'm meditating to find inner peace and clarity in my daily life. So I can be more present and compassionate with the people I love."
        """
        
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