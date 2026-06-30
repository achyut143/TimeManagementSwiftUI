import SwiftData
import Foundation

@Model
class RestraintInstance {
    var restraint: Restraint?
    var date: Date          // start of day
    var windowHour: Int
    var windowMinute: Int
    var isPassed: Bool
    var awardedUsed: Double      // minutes or quantity used from awarded bonus
    var overusedAmount: Double   // minutes or quantity consumed beyond limit
    var notes: String
    var createdAt: Date

    init(
        restraint: Restraint,
        date: Date,
        windowHour: Int,
        windowMinute: Int
    ) {
        self.restraint = restraint
        self.date = Calendar.current.startOfDay(for: date)
        self.windowHour = windowHour
        self.windowMinute = windowMinute
        self.isPassed = true
        self.awardedUsed = 0
        self.overusedAmount = 0
        self.notes = ""
        self.createdAt = Date()
    }
}
