import SwiftData
import Foundation
import CoreTransferable

@Model
class Task: Transferable {
    var title: String
    var taskDescription: String
    var startTime: String
    var endTime: String
    var completed: Bool
    var notCompleted: Bool
    var reassign: Bool
    var weight: Double
    var five: Bool
    var notes: String?
    var persistentNotes: String?
    var date: Date?
    var repeatAgain: Int?
    var priority: String = "P3"
    var timeSpent: Double? // Actual time spent in minutes
    var elapsedTime: Double? // Allocated/elapsed time in minutes for untimed tasks
    
    init(title: String = "", taskDescription: String = "", startTime: String = "", endTime: String = "", completed: Bool = false, notCompleted: Bool = false, reassign: Bool = false, weight: Double = 0.0, five: Bool = false, notes: String? = nil, persistentNotes: String? = nil, date: Date? = nil, repeatAgain: Int? = nil, priority: String = "P3", timeSpent: Double? = nil, elapsedTime: Double? = nil) {
        self.title = title
        self.taskDescription = taskDescription
        self.startTime = startTime
        self.endTime = endTime
        self.completed = completed
        self.notCompleted = notCompleted
        self.reassign = reassign
        self.weight = weight
        self.five = five
        self.notes = notes
        self.persistentNotes = persistentNotes
        self.date = date
        self.repeatAgain = repeatAgain
        self.priority = priority
        self.timeSpent = timeSpent
        self.elapsedTime = elapsedTime
    }
    
    // Helper method to get calculated time for timed tasks or timeSpent for untimed tasks
    var effectiveTimeInMinutes: Double {
        // For untimed tasks, use timeSpent if available
        if startTime.isEmpty && endTime.isEmpty {
            return timeSpent ?? 0.0
        }
        
        // For timed tasks, use timeSpent if set, otherwise calculate from start/end times
        if let timeSpent = timeSpent {
            return timeSpent
        }
        
        let start = timeToMinutes(startTime)
        let end = timeToMinutes(endTime)
        return Double(end > start ? end - start : (24 * 60 - start) + end)
    }
    
    // Get allocated time for timed tasks (from start/end times) or elapsedTime for untimed tasks
    var allocatedTimeInMinutes: Double {
        // For untimed tasks, use elapsedTime if available
        if startTime.isEmpty && endTime.isEmpty {
            return elapsedTime ?? 0.0
        }
        
        // For timed tasks, calculate from start/end times
        let start = timeToMinutes(startTime)
        let end = timeToMinutes(endTime)
        return Double(end > start ? end - start : (24 * 60 - start) + end)
    }
    
    // Calculate proportional points based on time spent vs allocated time
    var effectiveWeight: Double {
        // If no timeSpent is set, use full weight
        guard let timeSpent = timeSpent else {
            return weight
        }
        
        let allocated = allocatedTimeInMinutes
        
        // If no allocated time, use full weight
        guard allocated > 0 else { return weight }
        
        // Calculate proportional weight
        let ratio = timeSpent / allocated
        return weight * ratio
    }
    
    private func timeToMinutes(_ time: String) -> Int {
        let components = time.split(separator: ":").compactMap { Int($0) }
        return components.count == 2 ? components[0] * 60 + components[1] : 0
    }
    
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.title)
    }
}