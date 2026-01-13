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
    ///   - completions: Array of (Date, Bool) tuples representing daily completions (only days with actual tasks)
    ///   - totalDays: Total days in the period (default 30) - used for backward compatibility
    ///   - repeatInterval: How often the habit should repeat (in days, default 1 for daily)
    /// - Returns: DisciplineMuscleScore with all metrics
    static func calculateScore(completions: [(Date, Bool)], totalDays: Int = 30, repeatInterval: Int = 1) -> DisciplineMuscleScore {
        let sortedCompletions = completions.sorted { $0.0 < $1.0 }
        
        // Use actual task occurrences instead of theoretical expected occurrences
        // The completions array already contains only days where tasks were scheduled
        let actualOccurrences = sortedCompletions.count
        let expectedOccurrences = max(1, actualOccurrences) // Use actual occurrences as expected
        
        // 1. Base Metrics - count actual completions
        let completedDays = sortedCompletions.filter { $0.1 }.count
        
        // 2. Streak Calculations (using actual task occurrences)
        let streaks = calculateStreaks(from: sortedCompletions)
        let streakBonus = actualOccurrences > 0 ? Double(streaks.longest) / Double(actualOccurrences) : 0
        
        // 3. Decay Penalty Calculation (using actual task occurrences)
        let decayPenalty = calculateDecayPenalty(from: sortedCompletions)
        
        // 4. Final Discipline Muscle Score (DMS)
        let adjustedCompletedDays = max(0, Double(completedDays) - decayPenalty)
        let baseScore = actualOccurrences > 0 ? adjustedCompletedDays / Double(actualOccurrences) : 0
        let disciplineScore = min(1.0, baseScore + streakBonus)
        
        // 5. Determine Discipline Level
        let disciplineLevel = DisciplineLevel.from(score: disciplineScore)
        
        return DisciplineMuscleScore(
            completedDays: completedDays,
            totalDays: actualOccurrences,
            longestStreak: streaks.longest,
            currentStreak: streaks.current,
            decayPenalty: decayPenalty,
            streakBonus: streakBonus,
            disciplineScore: disciplineScore,
            disciplineLevel: disciplineLevel
        )
    }
    
    /// Calculate current and longest streaks from completion data (using actual task occurrences)
    private static func calculateStreaks(from completions: [(Date, Bool)]) -> (current: Int, longest: Int) {
        guard !completions.isEmpty else { return (0, 0) }
        
        let sortedCompletions = completions.sorted { $0.0 < $1.0 }
        
        var longestStreak = 0
        var currentStreakInData = 0
        
        // Calculate longest streak based on actual task occurrences
        for (_, isCompleted) in sortedCompletions {
            if isCompleted {
                currentStreakInData += 1
                longestStreak = max(longestStreak, currentStreakInData)
            } else {
                currentStreakInData = 0
            }
        }
        
        // Calculate current streak from the end
        var currentStreak = 0
        for (_, isCompleted) in sortedCompletions.reversed() {
            if isCompleted {
                currentStreak += 1
            } else {
                break
            }
        }
        
        return (currentStreak, longestStreak)
    }
    
    /// Calculate decay penalty based on consecutive missed actual task occurrences
    /// Rules:
    /// - 1 missed occurrence → no penalty
    /// - 2 missed occurrences in a row → -0.5 rep
    /// - 3+ missed occurrences in a row → -0.5 + (extra × 1.0) rep
    private static func calculateDecayPenalty(from completions: [(Date, Bool)]) -> Double {
        guard !completions.isEmpty else { return 0 }
        
        let sortedCompletions = completions.sorted { $0.0 < $1.0 }
        var penalty: Double = 0
        var consecutiveMisses = 0
        
        // Process each actual task occurrence
        for (_, isCompleted) in sortedCompletions {
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