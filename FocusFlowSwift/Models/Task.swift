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
    var date: Date?
    var repeatAgain: Int?
    
    init(title: String = "", taskDescription: String = "", startTime: String = "", endTime: String = "", completed: Bool = false, notCompleted: Bool = false, reassign: Bool = false, weight: Double = 0.0, five: Bool = false, notes: String? = nil, date: Date? = nil, repeatAgain: Int? = nil) {
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
        self.date = date
        self.repeatAgain = repeatAgain
    }
    
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.title)
    }
}