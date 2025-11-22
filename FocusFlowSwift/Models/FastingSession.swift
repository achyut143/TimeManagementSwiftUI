import SwiftData
import Foundation

@Model
class FastingSession {
    var startTime: Date
    var endTime: Date
    var status: String // "active", "success", "failed"
    var notes: String?
    var completedAt: Date?
    
    init(startTime: Date = Date(), endTime: Date, status: String = "active", notes: String? = nil, completedAt: Date? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.notes = notes
        self.completedAt = completedAt
    }
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    var remainingTime: TimeInterval {
        max(0, endTime.timeIntervalSince(Date()))
    }
    
    var isActive: Bool {
        status == "active" && Date() < endTime
    }
    
    var isCompleted: Bool {
        status == "success" || status == "failed"
    }
    
    var progressPercentage: Double {
        let total = duration
        let elapsed = Date().timeIntervalSince(startTime)
        return min(1.0, max(0.0, elapsed / total))
    }
}
