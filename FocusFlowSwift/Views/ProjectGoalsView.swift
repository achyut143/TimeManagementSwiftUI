import SwiftUI
import SwiftData

// Config page: set a target percentage per project, either "Control" (stay under it)
// or "Improve" (reach/exceed it). Read by TimeInsightsView to color/flag bars.
struct ProjectGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    private let dayCounts = [1, 7, 10, 15, 30]

    private var projectsWithGoals: [Project] {
        projects.filter { $0.targetPercent != nil }
    }

    /// A target percent is "% of a full day" (see DateRange.elapsedMinutes — every day,
    /// including today, counts as a full 24h), so minutes over N days = target% × 24h × N.
    private func targetMinutes(for project: Project, days: Int) -> Double {
        (project.targetPercent ?? 0) / 100 * 24 * 60 * Double(days)
    }

    private func totalMinutes(days: Int) -> Double {
        projectsWithGoals.reduce(0) { $0 + targetMinutes(for: $1, days: days) }
    }

    var body: some View {
        List {
            if !projectsWithGoals.isEmpty {
                Section("Target Hours") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Grid(horizontalSpacing: 14, verticalSpacing: 8) {
                            GridRow {
                                Text("Project")
                                    .gridColumnAlignment(.leading)
                                ForEach(dayCounts, id: \.self) { d in
                                    Text("\(d)d")
                                        .gridColumnAlignment(.trailing)
                                }
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)

                            Divider().gridCellColumns(dayCounts.count + 1)

                            ForEach(projectsWithGoals) { project in
                                GridRow {
                                    Text(project.name)
                                        .lineLimit(1)
                                    ForEach(dayCounts, id: \.self) { d in
                                        Text(DurationInput.string(from: targetMinutes(for: project, days: d)))
                                    }
                                }
                                .font(.caption)
                            }

                            Divider().gridCellColumns(dayCounts.count + 1)

                            GridRow {
                                Text("Total")
                                ForEach(dayCounts, id: \.self) { d in
                                    Text(DurationInput.string(from: totalMinutes(days: d)))
                                }
                            }
                            .font(.caption.weight(.bold))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if projects.isEmpty {
                Section {
                    Text("No projects yet")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(projects) { project in
                    Section(project.name) {
                        Picker("Goal Type", selection: goalTypeBinding(project)) {
                            Text("None").tag(ProjectGoalType?.none)
                            ForEach(ProjectGoalType.allCases) { type in
                                Text(type.label).tag(ProjectGoalType?.some(type))
                            }
                        }
                        .pickerStyle(.segmented)

                        if let type = project.goalType {
                            Stepper(value: targetBinding(project), in: 0...100, step: 1) {
                                HStack {
                                    Text("Target")
                                    Spacer()
                                    Text("\(Int(project.targetPercent ?? 0))%")
                                        .foregroundColor(.secondary)
                                }
                            }
                            Label(type.helpText, systemImage: type.icon)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Project Goals")
    }

    private func goalTypeBinding(_ project: Project) -> Binding<ProjectGoalType?> {
        Binding(
            get: { project.goalType },
            set: { newValue in
                project.goalType = newValue
                if newValue != nil && project.targetPercent == nil {
                    project.targetPercent = 50
                }
                try? modelContext.save()
            }
        )
    }

    private func targetBinding(_ project: Project) -> Binding<Double> {
        Binding(
            get: { project.targetPercent ?? 50 },
            set: {
                project.targetPercent = $0
                try? modelContext.save()
            }
        )
    }
}
