import Foundation

enum DurationInput {
    // Parses "4h", "40m", "1h 30m", "2.5h" into total minutes.
    static func minutes(from input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        var total = 0.0
        var matched = false

        if let hours = firstMatch(pattern: #"(\d+\.?\d*)\s*h"#, in: trimmed) {
            total += hours * 60
            matched = true
        }
        if let mins = firstMatch(pattern: #"(\d+\.?\d*)\s*m"#, in: trimmed) {
            total += mins
            matched = true
        }
        if !matched, let bare = Double(trimmed) {
            // Bare number with no unit is treated as minutes (e.g. "10" = 10m)
            total = bare
            matched = true
        }

        guard matched, total > 0 else { return nil }
        return total
    }

    static func string(from minutes: Double) -> String {
        let totalMinutes = Int(minutes.rounded())
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }

    private static func firstMatch(pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[valueRange])
    }
}
