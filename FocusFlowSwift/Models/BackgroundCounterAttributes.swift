import ActivityKit
import Foundation

struct BackgroundCounterAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentSessionTime: TimeInterval
        var totalBackgroundTime: TimeInterval
        var isCountingInBackground: Bool
        var backgroundStartTime: Date?
        
        // Force update mechanism
        var updateTimestamp: TimeInterval
        var updateCounter: Int
    }
    
    // Static properties
    var sessionId: String
    var startTime: Date
}
