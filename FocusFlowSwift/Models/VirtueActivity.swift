import SwiftData
import Foundation

// One value exercised (in a WhyGroup's Hows), or in some other activity's
// context, plus a short note on how it's exercised in action — e.g.
// "Discipline" -> "Show up and train even on days I don't feel like it".
struct VirtueExplanation: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var virtueName: String
    var howExercised: String

    /// Collapses entries that share the same value name (case/whitespace
    /// insensitive) into one, combining their descriptions — a defense
    /// against the AI occasionally returning the same How twice with
    /// different phrasing instead of recognizing it's the same one. Order
    /// preserved by first appearance.
    static func merged(_ hows: [VirtueExplanation]) -> [VirtueExplanation] {
        var order: [String] = []
        var nameByKey: [String: String] = [:]
        var descriptionsByKey: [String: [String]] = [:]

        for how in hows {
            let key = how.virtueName.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            let desc = how.howExercised.trimmingCharacters(in: .whitespacesAndNewlines)

            if nameByKey[key] == nil {
                order.append(key)
                nameByKey[key] = how.virtueName.trimmingCharacters(in: .whitespaces)
                descriptionsByKey[key] = []
            }
            if !desc.isEmpty && !(descriptionsByKey[key]?.contains(desc) ?? false) {
                descriptionsByKey[key]?.append(desc)
            }
        }

        return order.compactMap { key in
            guard let name = nameByKey[key] else { return nil }
            let combined = (descriptionsByKey[key] ?? []).joined(separator: "; ")
            return VirtueExplanation(virtueName: name, howExercised: combined)
        }
    }
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

// A named activity (e.g. "Cold showers", "Reading") — the WHAT in the
// WHY -> HOW -> WHAT hierarchy. Always belongs to a WhyGroup, which holds
// the shared purpose (WHY) and values-in-action (HOW) it and any sibling
// activities serve — see WhyGroup. Distinct from Task/Project virtues
// (which just tag existing tasks/projects) — this is its own standalone
// entity you create directly, not attached to anything else.
@Model
class VirtueActivity {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date
    var updatedAt: Date
    // User-arranged display order (lower sorts first). Defaults to 0 for
    // backward compatibility with rows created before this field existed —
    // those fall back to sorting by createdAt until manually reordered.
    var sortOrder: Int = 0

    // The shared purpose this activity is grouped under. Inverse declared on
    // WhyGroup.activities. Optional only because SwiftData requires it to be
    // settable before the group itself is inserted; every activity created
    // through the app's Add/Edit flows always gets one — a row that somehow
    // ends up without one is treated as orphaned data and cleaned up (see
    // VirtueActivitiesView).
    var whyGroup: WhyGroup?

    init(name: String, sortOrder: Int = 0, whyGroup: WhyGroup? = nil) {
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = sortOrder
        self.whyGroup = whyGroup
    }
}
