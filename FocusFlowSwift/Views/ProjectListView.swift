import SwiftUI
import SwiftData

struct DateRange: Equatable {
    var start: Date
    var end: Date

    // Inclusive count of calendar days spanned by the range.
    var dayCount: Int {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        let days = cal.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(days + 1, 1)
    }

    // Minutes actually elapsed within the range as of `now`: past days count as a
    // full 24h, today counts only the hours elapsed since midnight, future days count as 0.
    func elapsedMinutes(asOf now: Date = Date()) -> Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let endDay = cal.startOfDay(for: end)
        var day = cal.startOfDay(for: start)
        var total = 0.0
        while day <= endDay {
            if day < today {
                total += 24 * 60
            } else if day == today {
                total += min(max(now.timeIntervalSince(today) / 60, 0), 24 * 60)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    static func day(_ date: Date) -> DateRange {
        let start = Calendar.current.startOfDay(for: date)
        return DateRange(start: start, end: start)
    }

    static func currentWeek() -> DateRange {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1=Sun...7=Sat
        let daysSinceMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let sunday = cal.date(byAdding: .day, value: 6, to: monday) ?? today
        return DateRange(start: monday, end: sunday)
    }

    // Moves the whole window forward/backward by its own length, so consecutive
    // ranges tile back-to-back (e.g. a 7-day range shifts by 7 days).
    func shifted(by direction: Int) -> DateRange {
        let cal = Calendar.current
        let offset = dayCount * direction
        guard let newStart = cal.date(byAdding: .day, value: offset, to: start),
              let newEnd = cal.date(byAdding: .day, value: offset, to: end) else { return self }
        return DateRange(start: newStart, end: newEnd)
    }
}

// Reusable "< range label >" control: tapping the arrows shifts the bound range
// forward/backward by its own length (a week stays a week, a day stays a day, etc).
struct DateRangeNavigatorView: View {
    @Binding var range: DateRange
    var isDark: Bool = false

    var body: some View {
        HStack {
            Button {
                range = range.shifted(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundColor(isDark ? .cyan : .accentColor)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(rangeLabel)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isDark ? .white : .primary)

            Spacer()

            Button {
                range = range.shifted(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundColor(isDark ? .cyan : .accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var rangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        if Calendar.current.isDate(range.start, inSameDayAs: range.end) {
            return formatter.string(from: range.start)
        }
        return "\(formatter.string(from: range.start)) – \(formatter.string(from: range.end))"
    }
}

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    @State private var useCustomRange = false
    @State private var range: DateRange = .currentWeek()

    @State private var showCreate = false
    @State private var projectToEdit: Project?
    @State private var projectToDelete: Project?
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            Section {
                DateRangeNavigatorView(range: $range)
                Toggle("Custom Range", isOn: $useCustomRange)
                    .onChange(of: useCustomRange) { _, newValue in
                        if !newValue { range = .currentWeek() }
                    }

                if useCustomRange {
                    DatePicker("Start", selection: Binding(
                        get: { range.start },
                        set: { range = DateRange(start: Calendar.current.startOfDay(for: $0), end: range.end) }
                    ), displayedComponents: .date)
                    DatePicker("End", selection: Binding(
                        get: { range.end },
                        set: { range = DateRange(start: range.start, end: Calendar.current.startOfDay(for: $0)) }
                    ), displayedComponents: .date)
                }
            }

            if projects.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No projects yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap + to create your first project")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(projects) { project in
                        NavigationLink(destination: ProjectDetailView(project: project, range: range)) {
                            ProjectRowView(project: project, range: range)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                projectToDelete = project
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                projectToEdit = project
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button(action: { projectToEdit = project }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive, action: {
                                projectToDelete = project
                                showDeleteConfirm = true
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    NavigationLink(destination: ProjectTimelineView(range: range)) {
                        Image(systemName: "calendar.day.timeline.left")
                            .foregroundColor(.indigo)
                    }
                    NavigationLink(destination: TimeInsightsView(range: range)) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.indigo)
                    }
                    NavigationLink(destination: ProjectGoalsView()) {
                        Image(systemName: "target")
                            .foregroundColor(.indigo)
                    }
                    Button(action: { showCreate = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateProjectView()
        }
        .sheet(item: $projectToEdit) { project in
            CreateProjectView(project: project)
        }
        .confirmationDialog("Delete Project?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let p = projectToDelete { modelContext.delete(p) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the project, its activities, and all logged time.")
        }
    }

}

private struct ProjectRowView: View {
    let project: Project
    let range: DateRange

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                if !project.projectDescription.isEmpty {
                    Text(project.projectDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(DurationInput.string(from: project.totalMinutes(from: range.start, to: range.end)))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct CreateProjectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var project: Project?

    @State private var name: String
    @State private var description: String

    init(project: Project? = nil) {
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _description = State(initialValue: project?.projectDescription ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Website Redesign, Sleep", text: $name)
                }
                Section("Description") {
                    TextField("Optional", text: $description, axis: .vertical)
                }
            }
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let project {
            project.name = trimmedName
            project.projectDescription = description
        } else {
            let project = Project(name: trimmedName, projectDescription: description)
            modelContext.insert(project)
        }
        try? modelContext.save()
        dismiss()
    }
}
