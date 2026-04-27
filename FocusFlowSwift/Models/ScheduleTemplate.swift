import Foundation
import SwiftData

@Model
class ScheduleTemplate {
    var name: String
    /// The raw schedule block — the text between (and including) the START/END markers.
    var content: String
    var isReward: Bool = false
    var createdAt: Date
    var updatedAt: Date

    init(name: String, content: String, isReward: Bool = false) {
        self.name = name
        self.content = content
        self.isReward = isReward
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func update(name: String? = nil, content: String? = nil, isReward: Bool? = nil) {
        if let name { self.name = name }
        if let content { self.content = content }
        if let isReward { self.isReward = isReward }
        self.updatedAt = Date()
    }
}
