import SwiftData
import Foundation
import SwiftUI

// Two kinds of goal: "control" projects should stay UNDER their target percent
// (e.g. social media), "improve" projects should reach or exceed it (e.g. exercise).
enum ProjectGoalType: String, Codable, CaseIterable, Identifiable {
    case control
    case improve

    var id: String { rawValue }
    var label: String { self == .control ? "Control" : "Improve" }
    var icon: String { self == .control ? "hand.raised.fill" : "arrow.up.forward.circle.fill" }
    var helpText: String {
        switch self {
        case .control: return "Flagged as \"Exceeded\" when actual time goes above the target."
        case .improve: return "Flagged as \"Needs Improvement\" when actual time falls below the target."
        }
    }
}

enum ProjectGoalStatus: Equatable {
    case none
    case onTrack
    case exceeded          // control-type gone over its limit
    case needsImprovement  // improve-type under its target

    var icon: String? {
        switch self {
        case .none: return nil
        case .onTrack: return "checkmark.circle.fill"
        case .exceeded: return "exclamationmark.triangle.fill"
        case .needsImprovement: return "arrow.up.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .none: return .clear
        case .onTrack: return .green
        case .exceeded: return .red
        case .needsImprovement: return .orange
        }
    }
}

@Model
class Project {
    var name: String
    var projectDescription: String
    var createdAt: Date
    var colorName: String = "blue"
    var iconName: String = "folder.fill"
    // Optional goal config; nil targetPercent/goalTypeRaw means "no goal set" so
    // existing projects stay valid without a migration.
    var targetPercent: Double?
    var goalTypeRaw: String?

    @Relationship(deleteRule: .cascade, inverse: \ProjectActivity.project)
    var activities: [ProjectActivity] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectTimeEntry.project)
    var directTimeEntries: [ProjectTimeEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectTimer.project)
    var timer: ProjectTimer?

    init(name: String, projectDescription: String = "") {
        self.name = name
        self.projectDescription = projectDescription
        self.createdAt = Date()
    }

    var goalType: ProjectGoalType? {
        get { goalTypeRaw.flatMap(ProjectGoalType.init(rawValue:)) }
        set { goalTypeRaw = newValue?.rawValue }
    }

    func goalStatus(actualPercent: Double) -> ProjectGoalStatus {
        guard let target = targetPercent, let type = goalType else { return .none }
        switch type {
        case .control:
            return actualPercent > target ? .exceeded : .onTrack
        case .improve:
            return actualPercent >= target ? .onTrack : .needsImprovement
        }
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
