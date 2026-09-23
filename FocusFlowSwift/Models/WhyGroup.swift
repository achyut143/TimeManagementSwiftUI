import SwiftData
import Foundation

// A shared purpose ("Why") that one or more VirtueActivity rows ("What") sit
// under, per Simon Sinek's "Start With Why" / "Find Your Why" framework:
// WHY (purpose) -> HOW (values in action) -> WHAT (the activity itself).
//
// Distinct from VirtueActivity's own legacy `whyReason`/`explanations`
// fields (kept for backward compatibility with rows created before this
// model existed): once an activity is assigned a WhyGroup, its shared why
// and hows come from here instead, so multiple activities that serve the
// same underlying purpose can be grouped under one Why with a combined set
// of Hows, rather than each restating its own near-duplicate why.
@Model
class WhyGroup {
    var id: UUID = UUID()
    var whyStatement: String
    var howsData: Data // JSON [VirtueExplanation] — reused as (value name, how-it-looks-in-action) pairs
    var createdAt: Date
    var updatedAt: Date
    // User-arranged display order (lower sorts first), same convention as
    // VirtueActivity.sortOrder.
    var sortOrder: Int = 0

    // Inverse of VirtueActivity.whyGroup. .nullify (not .cascade): deleting a
    // Why group un-groups its activities rather than deleting them.
    @Relationship(deleteRule: .nullify, inverse: \VirtueActivity.whyGroup)
    var activities: [VirtueActivity]? = []

    init(whyStatement: String, hows: [VirtueExplanation] = [], sortOrder: Int = 0) {
        self.whyStatement = whyStatement
        self.howsData = (try? JSONEncoder().encode(VirtueExplanation.merged(hows))) ?? Data()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = sortOrder
    }

    // Both directions run through VirtueExplanation.merged so a How that
    // somehow got stored twice under the same value name (the AI
    // occasionally does this, or manual editing could) self-heals on the
    // very next read/write anywhere in the app, not just at generation time.
    var hows: [VirtueExplanation] {
        get { VirtueExplanation.merged((try? JSONDecoder().decode([VirtueExplanation].self, from: howsData)) ?? []) }
        set { howsData = (try? JSONEncoder().encode(VirtueExplanation.merged(newValue))) ?? Data() }
    }
}
