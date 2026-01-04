import Foundation

// MARK: - Discipline Muscle System
struct DisciplineMuscleScore {
    let completedDays: Int
    let totalDays: Int
    let longestStreak: Int
    let currentStreak: Int
    let decayPenalty: Double
    let streakBonus: Double
    let disciplineScore: Double
    let disciplineLevel: DisciplineLevel
    
    var baseScore: Double {
        guard totalDays > 0 else { return 0 }
        return Double(completedDays) / Double(totalDays)
    }
}

enum DisciplineLevel: String, CaseIterable {
    case strong = "Strong Discipline"
    case growing = "Growing Discipline"
    case inconsistent = "Inconsistent but Improving"
    case weak = "Weak Consistency"
    case undertrained = "Discipline Undertrained"
    
    var color: (primary: String, background: String) {
        switch self {
        case .strong:
            return ("#22C55E", "#DCFCE7") // Green
        case .growing:
            return ("#3B82F6", "#DBEAFE") // Blue
        case .inconsistent:
            return ("#F59E0B", "#FEF3C7") // Amber
        case .weak:
            return ("#EF4444", "#FEE2E2") // Red
        case .undertrained:
            return ("#6B7280", "#F3F4F6") // Gray
        }
    }
    
    var range: ClosedRange<Double> {
        switch self {
        case .strong: return 0.90...1.0
        case .growing: return 0.75...0.89
        case .inconsistent: return 0.60...0.74
        case .weak: return 0.40...0.59
        case .undertrained: return 0.0...0.39
        }
    }
    
    var scoreRangeText: String {
        switch self {
        case .strong: return "0.90 – 1.0"
        case .growing: return "0.75 – 0.89"
        case .inconsistent: return "0.60 – 0.74"
        case .weak: return "0.40 – 0.59"
        case .undertrained: return "< 0.40"
        }
    }
    
    static func from(score: Double) -> DisciplineLevel {
        for level in DisciplineLevel.allCases {
            if level.range.contains(score) {
                return level
            }
        }
        return .undertrained
    }
}

class DisciplineMuscleCalculator {
    
    /// Calculate discipline muscle score for a habit over a specified period, accounting for repeat frequency
    /// - Parameters:
    ///   - completions: Array of (Date, Bool) tuples representing daily completions
    ///   - totalDays: Total days in the period (default 30)
    ///   - repeatInterval: How often the habit should repeat (in days, default 1 for daily)
    /// - Returns: DisciplineMuscleScore with all metrics
    static func calculateScore(completions: [(Date, Bool)], totalDays: Int = 30, repeatInterval: Int = 1) -> DisciplineMuscleScore {
        let sortedCompletions = completions.sorted { $0.0 < $1.0 }
        
        // Calculate expected occurrences based on repeat interval
        let expectedOccurrences = max(1, totalDays / repeatInterval)
        
        // 1. Base Metrics - count actual completions
        let completedDays = sortedCompletions.filter { $0.1 }.count
        
        // 2. Streak Calculations (adjusted for repeat interval)
        let streaks = calculateStreaks(from: sortedCompletions, repeatInterval: repeatInterval)
        let streakBonus = Double(streaks.longest) / Double(expectedOccurrences)
        
        // 3. Decay Penalty Calculation (adjusted for repeat interval)
        let decayPenalty = calculateDecayPenalty(from: sortedCompletions, repeatInterval: repeatInterval)
        
        // 4. Final Discipline Muscle Score (DMS)
        let adjustedCompletedDays = max(0, Double(completedDays) - decayPenalty)
        let baseScore = adjustedCompletedDays / Double(expectedOccurrences)
        let disciplineScore = min(1.0, baseScore + streakBonus)
        
        // 5. Determine Discipline Level
        let disciplineLevel = DisciplineLevel.from(score: disciplineScore)
        
        return DisciplineMuscleScore(
            completedDays: completedDays,
            totalDays: expectedOccurrences,
            longestStreak: streaks.longest,
            currentStreak: streaks.current,
            decayPenalty: decayPenalty,
            streakBonus: streakBonus,
            disciplineScore: disciplineScore,
            disciplineLevel: disciplineLevel
        )
    }
    
    /// Calculate current and longest streaks from completion data, accounting for repeat interval
    private static func calculateStreaks(from completions: [(Date, Bool)], repeatInterval: Int) -> (current: Int, longest: Int) {
        guard !completions.isEmpty else { return (0, 0) }
        
        let sortedCompletions = completions.sorted { $0.0 < $1.0 }
        
        var longestStreak = 0
        var currentStreakInData = 0
        
        // For non-daily habits, we need to group by expected occurrence dates
        let expectedDates = generateExpectedDates(from: sortedCompletions, repeatInterval: repeatInterval)
        
        // Calculate longest streak based on expected occurrences
        for expectedDate in expectedDates {
            let isCompleted = sortedCompletions.contains { completion in
                let daysDiff = Calendar.current.dateComponents([.day], from: expectedDate, to: completion.0).day ?? 0
                return abs(daysDiff) <= (repeatInterval / 2) && completion.1 // Allow some flexibility
            }
            
            if isCompleted {
                currentStreakInData += 1
                longestStreak = max(longestStreak, currentStreakInData)
            } else {
                currentStreakInData = 0
            }
        }
        
        // Calculate current streak from the end
        var currentStreak = 0
        for expectedDate in expectedDates.reversed() {
            let isCompleted = sortedCompletions.contains { completion in
                let daysDiff = Calendar.current.dateComponents([.day], from: expectedDate, to: completion.0).day ?? 0
                return abs(daysDiff) <= (repeatInterval / 2) && completion.1
            }
            
            if isCompleted {
                currentStreak += 1
            } else {
                break
            }
        }
        
        return (currentStreak, longestStreak)
    }
    
    /// Generate expected occurrence dates based on repeat interval
    private static func generateExpectedDates(from completions: [(Date, Bool)], repeatInterval: Int) -> [Date] {
        guard let firstDate = completions.first?.0 else { return [] }
        guard let lastDate = completions.last?.0 else { return [] }
        
        var expectedDates: [Date] = []
        var currentDate = firstDate
        
        while currentDate <= lastDate {
            expectedDates.append(currentDate)
            currentDate = Calendar.current.date(byAdding: .day, value: repeatInterval, to: currentDate) ?? currentDate
        }
        
        return expectedDates
    }
    
    /// Calculate decay penalty based on consecutive missed expected occurrences
    /// Rules (adjusted for repeat interval):
    /// - 1 missed occurrence → no penalty
    /// - 2 missed occurrences in a row → -0.5 rep
    /// - 3+ missed occurrences in a row → -1 rep per extra occurrence
    private static func calculateDecayPenalty(from completions: [(Date, Bool)], repeatInterval: Int) -> Double {
        guard !completions.isEmpty else { return 0 }
        
        let expectedDates = generateExpectedDates(from: completions, repeatInterval: repeatInterval)
        var penalty: Double = 0
        var consecutiveMisses = 0
        
        for expectedDate in expectedDates {
            let isCompleted = completions.contains { completion in
                let daysDiff = Calendar.current.dateComponents([.day], from: expectedDate, to: completion.0).day ?? 0
                return abs(daysDiff) <= (repeatInterval / 2) && completion.1
            }
            
            if !isCompleted {
                consecutiveMisses += 1
            } else {
                // Apply penalty for the consecutive miss streak that just ended
                if consecutiveMisses >= 2 {
                    if consecutiveMisses == 2 {
                        penalty += 0.5
                    } else {
                        penalty += 0.5 + Double(consecutiveMisses - 2)
                    }
                }
                consecutiveMisses = 0
            }
        }
        
        // Handle case where data ends with consecutive misses
        if consecutiveMisses >= 2 {
            if consecutiveMisses == 2 {
                penalty += 0.5
            } else {
                penalty += 0.5 + Double(consecutiveMisses - 2)
            }
        }
        
        return penalty
    }
    
    /// Calculate overall discipline level from multiple habits
    static func calculateOverallDiscipline(scores: [DisciplineMuscleScore]) -> (score: Double, level: DisciplineLevel) {
        guard !scores.isEmpty else { return (0, .undertrained) }
        
        let averageScore = scores.map { $0.disciplineScore }.reduce(0, +) / Double(scores.count)
        let level = DisciplineLevel.from(score: averageScore)
        
        return (averageScore, level)
    }
}