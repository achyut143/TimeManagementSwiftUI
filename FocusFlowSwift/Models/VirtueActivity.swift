import SwiftData
import Foundation

// One virtue exercised by an activity, plus a short note on how it's
// exercised. An activity normally carries exactly 2 of these (per the
// AI prompt), but nothing here enforces that — manual editing can leave 0, 1,
// or more if the user wants.
struct VirtueExplanation: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var virtueName: String
    var howExercised: String
}

// One daily reminder time for a VirtueActivity — e.g. 9:00 AM. An activity
// can have several, so it can prompt you multiple times a day.
struct ActivityReminderTime: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int

    var timeString: String {
        let h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h, minute, ampm)
    }
}

// A named activity (e.g. "Cold showers", "Reading") paired with a
// description: the 2 virtues it exercises (each with a short "how"), and a
// single selfless "why" reason for doing it. Distinct from Task/Project
// virtues (which just tag existing tasks/projects) — this is its own
// standalone entity you create directly, not attached to anything else.
@Model
class VirtueActivity {
    var id: UUID = UUID()
    var name: String
    var explanationsData: Data // JSON [VirtueExplanation]
    var whyReason: String
    var createdAt: Date
    var updatedAt: Date
    // User-arranged display order (lower sorts first). Defaults to 0 for
    // backward compatibility with rows created before this field existed —
    // those fall back to sorting by createdAt until manually reordered.
    var sortOrder: Int = 0

    init(name: String, explanations: [VirtueExplanation] = [], whyReason: String = "", sortOrder: Int = 0) {
        self.name = name
        self.explanationsData = (try? JSONEncoder().encode(explanations)) ?? Data()
        self.whyReason = whyReason
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = sortOrder
    }

    var explanations: [VirtueExplanation] {
        get { (try? JSONDecoder().decode([VirtueExplanation].self, from: explanationsData)) ?? [] }
        set { explanationsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
