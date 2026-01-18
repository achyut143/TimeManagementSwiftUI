import SwiftData
import Foundation

@Model
class Habit {
    var id: Int
    var title: String
    var habitDescription: String
    var startTime: String
    var endTime: String
    var completed: Bool
    var notCompleted: Bool
    var reassign: Bool
    var weight: Double
    var five: Bool
    var notes: String?
    var date: Date?
    var repeatAgain: Int?
    var eventDaysCount: Int
    var nonEventDaysNotCompleted: Int
    
    init(id: Int = 0, title: String = "", habitDescription: String = "", startTime: String = "", endTime: String = "", completed: Bool = false, notCompleted: Bool = false, reassign: Bool = false, weight: Double = 0.0, five: Bool = false, notes: String? = nil, date: Date? = nil, repeatAgain: Int? = nil, eventDaysCount: Int = 0, nonEventDaysNotCompleted: Int = 0) {
        self.id = id
        self.title = title
        self.habitDescription = habitDescription
        self.startTime = startTime
        self.endTime = endTime
        self.completed = completed
        self.notCompleted = notCompleted
        self.reassign = reassign
        self.weight = weight
        self.five = five
        self.notes = notes
        self.date = date
        self.repeatAgain = repeatAgain
        self.eventDaysCount = eventDaysCount
        self.nonEventDaysNotCompleted = nonEventDaysNotCompleted
    }
    
    // Helper methods for event tracking
    func updateEventStats(eventDays: [EventDay], context: ModelContext) {
        // Calculate event days count for this habit's date range
        guard let habitDate = self.date else { return }
        
        let calendar = Calendar.current
        let eventDaysForHabit = eventDays.filter { eventDay in
            calendar.isDate(eventDay.date, inSameDayAs: habitDate) && eventDay.hasAnyEvent
        }
        
        self.eventDaysCount = eventDaysForHabit.count
        
        // Calculate non-event days where habit was not completed
        // This would need to be calculated based on your habit tracking logic
        // For now, setting to 0 - you can implement this based on your specific requirements
        self.nonEventDaysNotCompleted = 0
        
        try? context.save()
    }
    
    func isEventDay(eventDays: [EventDay]) -> Bool {
        guard let habitDate = self.date else { return false }
        
        return eventDays.contains { eventDay in
            Calendar.current.isDate(eventDay.date, inSameDayAs: habitDate) && eventDay.hasAnyEvent
        }
    }
    
    func getEventTypesForDay(eventDays: [EventDay]) -> [EventType] {
        guard let habitDate = self.date else { return [] }
        
        let eventDay = eventDays.first { eventDay in
            Calendar.current.isDate(eventDay.date, inSameDayAs: habitDate)
        }
        
        return eventDay?.eventTypes ?? []
    }
}