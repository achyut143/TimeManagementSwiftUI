import Foundation

struct QuickTaskParser {
    struct ParsedTask {
        let title: String
        let startTime: String
        let endTime: String
        let weight: Double
        let repeatDays: Int?
        let isUntimed: Bool
        
        var isValid: Bool {
            !title.isEmpty
        }
    }
    
    /// Parses quick task input format:
    /// - Timed: "15:30 - 16:30 - shovel snow - 2 - r2"
    /// - Untimed: "shovel snow - 2 - r2"
    /// - Weight defaults to 1.0 if not specified
    /// - Repeat is optional (r2 means repeat every 2 days)
    static func parse(_ input: String) -> ParsedTask? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let parts = trimmed.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Check if first part contains time (HH:MM format)
        let timePattern = #"^\d{1,2}:\d{2}$"#
        let hasStartTime = parts.first?.range(of: timePattern, options: .regularExpression) != nil
        
        if hasStartTime && parts.count >= 2 {
            // Timed task format: "15:30 - 16:30 - title - weight - rN"
            let startTime = parts[0]
            let endTime = parts[1]
            let title = parts.count > 2 ? parts[2] : ""
            let weight = parts.count > 3 ? parseWeight(parts[3]) : 1.0
            let repeatDays = parts.count > 4 ? parseRepeat(parts[4]) : nil
            
            return ParsedTask(
                title: title,
                startTime: startTime,
                endTime: endTime,
                weight: weight,
                repeatDays: repeatDays,
                isUntimed: false
            )
        } else {
            // Untimed task format: "title - weight - rN"
            let title = parts[0]
            let weight = parts.count > 1 ? parseWeight(parts[1]) : 1.0
            let repeatDays = parts.count > 2 ? parseRepeat(parts[2]) : nil
            
            return ParsedTask(
                title: title,
                startTime: "",
                endTime: "",
                weight: weight,
                repeatDays: repeatDays,
                isUntimed: true
            )
        }
    }
    
    private static func parseWeight(_ input: String) -> Double {
        // Try to parse as number, default to 1.0 if it fails or if it's a repeat pattern
        if input.lowercased().hasPrefix("r") {
            return 1.0
        }
        return Double(input) ?? 1.0
    }
    
    private static func parseRepeat(_ input: String) -> Int? {
        // Parse "r2" or "R2" format
        let lowercased = input.lowercased()
        if lowercased.hasPrefix("r"), let number = Int(lowercased.dropFirst()) {
            return number
        }
        return nil
    }
    
    /// Returns example formats for user guidance
    static var exampleFormats: [String] {
        [
            "15:30 - 16:30 - shovel snow",
            "15:30 - 16:30 - shovel snow - 2",
            "15:30 - 16:30 - shovel snow - 2 - r2",
            "shovel snow",
            "shovel snow - 2",
            "shovel snow - 2 - r2"
        ]
    }
    
    static var helpText: String {
        """
        Quick Task Format:
        • Timed: 15:30 - 16:30 - task name - weight - r2
        • Untimed: task name - weight - r2
        • Weight defaults to 1 (optional)
        • r2 = repeat every 2 days (optional)
        """
    }
}
