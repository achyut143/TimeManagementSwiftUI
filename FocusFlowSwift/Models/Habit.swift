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
    
    init(id: Int = 0, title: String = "", habitDescription: String = "", startTime: String = "", endTime: String = "", completed: Bool = false, notCompleted: Bool = false, reassign: Bool = false, weight: Double = 0.0, five: Bool = false, notes: String? = nil, date: Date? = nil, repeatAgain: Int? = nil) {
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
    }
}