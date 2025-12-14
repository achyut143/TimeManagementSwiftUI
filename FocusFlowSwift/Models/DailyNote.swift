import Foundation
import SwiftData

@Model
class DailyNote {
    var date: Date
    var content: String
    var createdAt: Date
    var updatedAt: Date
    
    init(date: Date, content: String = "") {
        self.date = Calendar.current.startOfDay(for: date)
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    func updateContent(_ newContent: String) {
        self.content = newContent
        self.updatedAt = Date()
    }
}