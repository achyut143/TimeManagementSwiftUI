import Foundation
import SwiftData

@Model
class ScheduleTemplate {
    var name: String
    /// The raw schedule block — the text between (and including) the START/END markers.
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(name: String, content: String) {
        self.name = name
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func update(name: String? = nil, content: String? = nil) {
        if let name { self.name = name }
        if let content { self.content = content }
        self.updatedAt = Date()
    }
}
