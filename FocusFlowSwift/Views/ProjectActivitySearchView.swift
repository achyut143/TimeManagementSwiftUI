import SwiftUI
import SwiftData

// Same activity name can recur across many days (each day is a separate ProjectActivity
// row), so search results are grouped by name with hours summed across every match.
private struct ActivitySearchGroup: Identifiable {
    let name: String
    let totalMinutes: Double
    let matches: [ProjectActivity]

    var id: String { name }
}

struct ProjectActivitySearchView: View {
    let project: Project
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activityGroups: [ActivitySearchGroup] {
        guard !trimmedQuery.isEmpty else { return [] }

        let matches = project.activities.filter { activity in
            activity.name.localizedCaseInsensitiveContains(trimmedQuery)
                || (activity.notes?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }

        var byName: [String: [ProjectActivity]] = [:]
        for activity in matches {
            byName[activity.name, default: []].append(activity)
        }

        return byName.map { name, activities in
            ActivitySearchGroup(
                name: name,
                totalMinutes: activities.reduce(0.0) { $0 + $1.totalMinutes },
                matches: activities.sorted { $0.date > $1.date }
            )
        }
        .sorted { $0.totalMinutes > $1.totalMinutes }
    }

    // Direct "Project time" entries (not tied to an activity) whose note matches.
    private var directTimeMatches: [ProjectTimeEntry] {
        guard !trimmedQuery.isEmpty else { return [] }
        return project.directTimeEntries
            .filter { $0.note.localizedCaseInsensitiveContains(trimmedQuery) }
            .sorted { $0.date > $1.date }
    }

    // Aggregate across every kind of match, so the total reflects everything found.
    private var totalMatchedMinutes: Double {
        activityGroups.reduce(0.0) { $0 + $1.totalMinutes }
            + directTimeMatches.reduce(0.0) { $0 + $1.durationMinutes }
    }

    private var hasResults: Bool {
        !activityGroups.isEmpty || !directTimeMatches.isEmpty
    }

    var body: some View {
        List {
            if !trimmedQuery.isEmpty {
                if hasResults {
                    Section {
                        HStack {
                            Text("Total matched")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(DurationInput.string(from: totalMatchedMinutes))
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("No matching activities or notes")
                        .foregroundColor(.secondary)
                }
            }

            if !activityGroups.isEmpty {
                Section("Activities") {
                    ForEach(activityGroups) { group in
                        DisclosureGroup {
                            ForEach(group.matches) { activity in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(activity.date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(DurationInput.string(from: activity.totalMinutes))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if let notes = activity.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.caption)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } label: {
                            HStack {
                                Text(group.name)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(DurationInput.string(from: group.totalMinutes))
                                    .foregroundColor(.secondary)
                                Text("(\(group.matches.count))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            if !directTimeMatches.isEmpty {
                Section("Project Time") {
                    ForEach(directTimeMatches) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(DurationInput.string(from: entry.durationMinutes))
                                    .foregroundColor(.secondary)
                            }
                            Text(entry.note)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search activity names or notes")
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}
