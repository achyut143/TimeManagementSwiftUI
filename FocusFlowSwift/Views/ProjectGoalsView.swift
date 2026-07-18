import SwiftUI
import SwiftData

// Config page: set a target percentage per project, either "Control" (stay under it)
// or "Improve" (reach/exceed it). Read by TimeInsightsView to color/flag bars.
struct ProjectGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    var body: some View {
        List {
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
                            Stepper(value: targetBinding(project), in: 0...100, step: 5) {
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
