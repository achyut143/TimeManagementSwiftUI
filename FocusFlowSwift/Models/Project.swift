import SwiftData
import Foundation

@Model
class Project {
    var name: String
    var projectDescription: String
    var createdAt: Date
    var colorName: String = "blue"
    var iconName: String = "folder.fill"

    @Relationship(deleteRule: .cascade, inverse: \ProjectActivity.project)
    var activities: [ProjectActivity] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectTimeEntry.project)
    var directTimeEntries: [ProjectTimeEntry] = []

    init(name: String, projectDescription: String = "") {
        self.name = name
        self.projectDescription = projectDescription
        self.createdAt = Date()
    }

    // category == nil means "all categories" (unfiltered); direct project time has no
    // category, so it's excluded whenever a specific category filter is applied.
    func totalMinutes(from start: Date, to end: Date, category: ActivityCategory? = nil) -> Double {
        let activityMinutes = activities
            .filter { $0.date >= start && $0.date <= end }
            .filter { category == nil || $0.category == category }
            .reduce(0.0) { $0 + $1.totalMinutes }
        guard category == nil else { return activityMinutes }
        let directMinutes = directTimeEntries
            .filter { $0.date >= start && $0.date <= end }
            .reduce(0.0) { $0 + $1.durationMinutes }
        return activityMinutes + directMinutes
    }
}
