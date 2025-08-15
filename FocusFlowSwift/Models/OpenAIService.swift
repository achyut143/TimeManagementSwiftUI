import Foundation

class OpenAIService {
    private let apiKey = "" // Replace with your actual API key
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
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