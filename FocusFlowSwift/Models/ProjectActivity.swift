import SwiftData
import SwiftUI
import Foundation

// Static A–D categorization for activities, colored green (A) to red (D).
enum ActivityCategory: String, CaseIterable, Identifiable, Codable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .a: return .green
        case .b: return .yellow
        case .c: return .orange
        case .d: return .red
        }
    }
}

// Named "ProjectActivity" (not "Activity") to avoid colliding with
// ActivityKit.Activity<Attributes>, which this app already uses for Live Activities.
@Model
class ProjectActivity {
    var project: Project?
    var name: String
    var date: Date   // start-of-day, calendar date this activity is logged under
    var createdAt: Date
    var startTime: String?  // "HH:mm", nil = untimed (optional so existing rows without it stay valid)
    var endTime: String?    // "HH:mm", nil = untimed
    var categoryRaw: String?  // ActivityCategory.rawValue, nil = uncategorized (optional so existing rows stay valid)

    @Relationship(deleteRule: .cascade, inverse: \ProjectTimeEntry.activity)
    var timeEntries: [ProjectTimeEntry] = []

    init(project: Project, name: String, date: Date, startTime: String? = nil, endTime: String? = nil, category: ActivityCategory? = nil) {
        self.project = project
        self.name = name
        self.date = Calendar.current.startOfDay(for: date)
        self.createdAt = Date()
        self.startTime = startTime
        self.endTime = endTime
        self.categoryRaw = category?.rawValue
    }

    var category: ActivityCategory? {
        get { categoryRaw.flatMap { ActivityCategory(rawValue: $0) } }
        set { categoryRaw = newValue?.rawValue }
    }

    // Logged time entries plus the scheduled From/To duration (if set), so setting
    // a time range on an activity counts toward its total without requiring a
    // separate manually-logged entry for that same slot.
    var totalMinutes: Double {
        scheduledMinutes + timeEntries.reduce(0.0) { $0 + $1.durationMinutes }
    }

    var scheduledMinutes: Double {
        guard let start = startMinutes, let end = endMinutes, end > start else { return 0 }
        return Double(end - start)
    }

    // Minutes since midnight, for sorting; nil when untimed.
    var startMinutes: Int? { Self.minutes(from: startTime) }
    var endMinutes: Int? { Self.minutes(from: endTime) }

    private static func minutes(from hhmm: String?) -> Int? {
        guard let hhmm else { return nil }
        let components = hhmm.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return nil }
        return components[0] * 60 + components[1]
    }
}
