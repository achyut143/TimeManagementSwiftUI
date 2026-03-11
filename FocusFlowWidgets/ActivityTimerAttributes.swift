import ActivityKit
import Foundation

struct ActivityTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endTime: Date
        var remainingSeconds: TimeInterval
        var activityName: String
        var isPaused: Bool
        
        // Force update mechanism
        var updateTimestamp: TimeInterval
    }
    
    // Static properties
    var timerId: String
    var totalDuration: TimeInterval
    var activityName: String
}
