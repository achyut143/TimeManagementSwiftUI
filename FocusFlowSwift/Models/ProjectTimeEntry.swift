import SwiftData
import Foundation

// Named "ProjectTimeEntry" (not "TimeEntry") to avoid colliding with the
// unrelated TimeEntry struct in Views/DailyNotesView.swift.
@Model
class ProjectTimeEntry {
    var activity: ProjectActivity?  // set when logged against a ProjectActivity
    var project: Project?           // set when logged directly on a Project
    var date: Date                  // start-of-day this entry counts toward
    var durationMinutes: Double
    var enteredAt: Date             // audit timestamp of when the entry was created
    var note: String

    var isDirectProjectTime: Bool { project != nil }

    init(activity: ProjectActivity, durationMinutes: Double, date: Date, note: String = "") {
        self.activity = activity
        self.project = nil
        self.durationMinutes = durationMinutes
        self.date = Calendar.current.startOfDay(for: date)
        self.enteredAt = Date()
        self.note = note
    }

    init(project: Project, durationMinutes: Double, date: Date, note: String = "") {
        self.activity = nil
        self.project = project
        self.durationMinutes = durationMinutes
        self.date = Calendar.current.startOfDay(for: date)
        self.enteredAt = Date()
        self.note = note
    }
}
