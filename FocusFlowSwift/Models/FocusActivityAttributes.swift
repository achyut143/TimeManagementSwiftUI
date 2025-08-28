import ActivityKit
import Foundation

struct FocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic properties that change during the activity
        var currentInterval: Int
        var totalIntervals: Int?
        var intervalName: String
        var nextAlertTime: Date
        var isInCycleMode: Bool
        var currentCycleName: String?
        var cycleProgress: String? // e.g., "2/4"
        var timeRemaining: TimeInterval
        var isPaused: Bool
        
        // Force update mechanism - changes with each update to ensure Dynamic Island refreshes
        var updateTimestamp: TimeInterval
        var updateCounter: Int
    }
    
    // Static properties that don't change during the activity
    var intervalDuration: Int // in minutes
    var startTime: Date
    var sessionId: String
}