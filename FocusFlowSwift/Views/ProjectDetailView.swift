import SwiftUI
import SwiftData

private struct DayGroup: Identifiable {
    let date: Date
    var activities: [ProjectActivity]
    var directEntries: [ProjectTimeEntry]

    var id: Date { date }

    var totalMinutes: Double {
        let activityMinutes = activities.reduce(0.0) { $0 + $1.totalMinutes }
        let directMinutes = directEntries.reduce(0.0) { $0 + $1.durationMinutes }
        return activityMinutes + directMinutes
    }

    // Timed activities first (ordered by start time), untimed activities after (by creation order).
    var sortedActivities: [ProjectActivity] {
        activities.sorted { a, b in
            switch (a.startMinutes, b.startMinutes) {
            case let (m1?, m2?): return m1 < m2
            case (nil, nil): return a.createdAt < b.createdAt
            case (nil, _?): return false
            case (_?, nil): return true
            }
        }
    }
}

private func formatTimeOfDay(_ hhmm: String?) -> String? {
    guard let hhmm, !hhmm.isEmpty else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    guard let date = formatter.date(from: hhmm) else { return nil }
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
}

struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    let range: DateRange

    // Local shift override so the < > navigator can move the window without a live
    // binding back to the caller; resets whenever the caller passes a new `range`.
    @State private var overrideRange: DateRange?

    @State private var showAddActivity = false
    @State private var showAddProjectTime = false
    @State private var showEditProject = false
    @State private var activityForNewEntry: ProjectActivity?
    @State private var activityForNotePreview: ProjectActivity?
    @State private var activityToEdit: ProjectActivity?
    @State private var activityToDelete: ProjectActivity?
    @State private var showDeleteActivityConfirm = false
    @State private var entryToDelete: ProjectTimeEntry?
    @State private var showDeleteEntryConfirm = false

    private var effectiveRange: DateRange { overrideRange ?? range }

    private var rangeBinding: Binding<DateRange> {
        Binding(get: { effectiveRange }, set: { overrideRange = $0 })
    }

    private var dayGroups: [DayGroup] {
        var byDate: [Date: DayGroup] = [:]

        for activity in project.activities where activity.date >= effectiveRange.start && activity.date <= effectiveRange.end {
            byDate[activity.date, default: DayGroup(date: activity.date, activities: [], directEntries: [])].activities.append(activity)
        }
        for entry in project.directTimeEntries where entry.date >= effectiveRange.start && entry.date <= effectiveRange.end {
            byDate[entry.date, default: DayGroup(date: entry.date, activities: [], directEntries: [])].directEntries.append(entry)
        }

        return byDate.values.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                DateRangeNavigatorView(range: rangeBinding)
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text(DurationInput.string(from: project.totalMinutes(from: effectiveRange.start, to: effectiveRange.end)))
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                Button {
                    showAddActivity = true
                } label: {
                    Label("Add Activity", systemImage: "plus.circle")
                }
                Button {
                    showAddProjectTime = true
                } label: {
                    Label("Add Project Time", systemImage: "clock.badge.plus")
                }
            }

            if dayGroups.isEmpty {
                Section {
                    Text("No time logged in this range yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(dayGroups) { day in
                    DisclosureGroup {
                        ForEach(day.sortedActivities) { activity in
                            if activity.timeEntries.isEmpty {
                                activityRow(activity)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        activitySwipeActions(activity)
                                    }
                            } else {
                                DisclosureGroup {
                                    ForEach(activity.timeEntries.sorted { $0.enteredAt > $1.enteredAt }) { entry in
                                        HStack {
                                            if let category = activity.category {
                                                Circle()
                                                    .fill(category.color)
                                                    .frame(width: 8, height: 8)
                                            }
                                            Text(entry.note.isEmpty ? "Logged time" : entry.note)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(DurationInput.string(from: entry.durationMinutes))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                entryToDelete = entry
                                                showDeleteEntryConfirm = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                } label: {
                                    activityRow(activity)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    activitySwipeActions(activity)
                                }
                            }
                        }
                        ForEach(day.directEntries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Project time")
                                    if !entry.note.isEmpty {
                                        Text(entry.note)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Text(DurationInput.string(from: entry.durationMinutes))
                                    .foregroundColor(.secondary)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    entryToDelete = entry
                                    showDeleteEntryConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(day.date, style: .date)
                                .font(.subheadline)
                            Spacer()
                            Text(DurationInput.string(from: day.totalMinutes))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .onChange(of: range) { _, _ in overrideRange = nil }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showEditProject = true }) {
                    Text("Edit")
                }
            }
        }
        .sheet(isPresented: $showAddActivity) {
            AddActivityView(project: project)
        }
        .sheet(isPresented: $showAddProjectTime) {
            AddTimeEntryView(project: project)
        }
        .sheet(isPresented: $showEditProject) {
            CreateProjectView(project: project)
        }
        .sheet(item: $activityForNewEntry) { activity in
            AddTimeEntryView(activity: activity)
        }
        .sheet(item: $activityToEdit) { activity in
            AddActivityView(project: project, activity: activity)
        }
        .popover(item: $activityForNotePreview) { activity in
            Text(activity.notes ?? "")
                .font(.subheadline)
                .padding()
                .frame(minWidth: 200, maxWidth: 320)
        }
        .confirmationDialog("Delete Time Entry?", isPresented: $showDeleteEntryConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete { modelContext.delete(entry) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete Activity?", isPresented: $showDeleteActivityConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let activity = activityToDelete { modelContext.delete(activity) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the activity and all time logged against it.")
        }
    }

    @ViewBuilder
    private func activityRow(_ activity: ProjectActivity) -> some View {
        HStack {
            if let category = activity.category {
                Circle()
                    .fill(category.color)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(activity.name)
                    if let notes = activity.notes, !notes.isEmpty {
                        activityNoteButton(activity, notes: notes)
                    }
                }
                if let start = formatTimeOfDay(activity.startTime) {
                    if let end = formatTimeOfDay(activity.endTime) {
                        Text("\(start) – \(end)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(start)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Text(DurationInput.string(from: activity.totalMinutes))
                .foregroundColor(.secondary)
            Button {
                activityForNewEntry = activity
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func activityNoteButton(_ activity: ProjectActivity, notes: String) -> some View {
        Button {
            activityForNotePreview = activity
        } label: {
            Image(systemName: "note.text")
                .font(.caption)
                .foregroundColor(.orange)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func activitySwipeActions(_ activity: ProjectActivity) -> some View {
        Button(role: .destructive) {
            activityToDelete = activity
            showDeleteActivityConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        Button {
            activityToEdit = activity
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.blue)
    }
}

private struct AddActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: Project
    var activity: ProjectActivity?

    @State private var name: String
    @State private var date: Date
    @State private var setTime: Bool
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var category: ActivityCategory?
    @State private var durationText: String = ""
    @State private var showInvalidDuration = false
    @State private var notes: String

    init(project: Project, activity: ProjectActivity? = nil) {
        self.project = project
        self.activity = activity

        let hhmmFormatter = DateFormatter()
        hhmmFormatter.dateFormat = "HH:mm"

        _name = State(initialValue: activity?.name ?? "")
        _date = State(initialValue: activity?.date ?? Date())
        let hasTime = activity?.startTime != nil
        _setTime = State(initialValue: hasTime)
        _startTime = State(initialValue: activity?.startTime.flatMap { hhmmFormatter.date(from: $0) } ?? Date())
        _endTime = State(initialValue: activity?.endTime.flatMap { hhmmFormatter.date(from: $0) } ?? Date())
        _category = State(initialValue: activity?.category)
        _notes = State(initialValue: activity?.notes ?? "")
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let trimmedDuration = durationText.trimmingCharacters(in: .whitespaces)
        let durationValid = trimmedDuration.isEmpty || DurationInput.minutes(from: trimmedDuration) != nil
        return hasName && durationValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Activity name", text: $name)
                }
                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section {
                    Toggle("Set From / To Time", isOn: $setTime)
                    if setTime {
                        DatePicker("From", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("To", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Category") {
                    HStack(spacing: 10) {
                        categoryChip(nil, label: "None")
                        ForEach(ActivityCategory.allCases) { cat in
                            categoryChip(cat, label: cat.rawValue)
                        }
                    }
                }
                Section("Log Time (optional)") {
                    TextField("e.g. 1h 30m, 45m, 2.5h", text: $durationText)
                }
                Section("Notes (optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(activity == nil ? "New Activity" : "Edit Activity")
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
            .alert("Couldn't parse duration", isPresented: $showInvalidDuration) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try formats like \"1h 30m\", \"45m\", or \"2.5h\".")
            }
        }
    }

    @ViewBuilder
    private func categoryChip(_ cat: ActivityCategory?, label: String) -> some View {
        let isSelected = category == cat
        Button {
            category = cat
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(cat?.color.opacity(isSelected ? 1 : 0.25) ?? Color.secondary.opacity(isSelected ? 0.3 : 0.12))
                )
                .foregroundColor(cat == nil ? .primary : (isSelected ? .white : .primary))
                .overlay(Circle().stroke(Color.primary.opacity(isSelected ? 0.4 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let newStartTime = setTime ? formatter.string(from: startTime) : nil
        let newEndTime = setTime ? formatter.string(from: endTime) : nil
        let trimmedDuration = durationText.trimmingCharacters(in: .whitespaces)

        if !trimmedDuration.isEmpty && DurationInput.minutes(from: trimmedDuration) == nil {
            showInvalidDuration = true
            return
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNotes: String? = trimmedNotes.isEmpty ? nil : trimmedNotes

        let savedActivity: ProjectActivity
        if let activity {
            activity.name = trimmedName
            activity.date = Calendar.current.startOfDay(for: date)
            activity.startTime = newStartTime
            activity.endTime = newEndTime
            activity.category = category
            activity.notes = newNotes
            savedActivity = activity
        } else {
            let newActivity = ProjectActivity(
                project: project,
                name: trimmedName,
                date: date,
                startTime: newStartTime,
                endTime: newEndTime,
                category: category,
                notes: newNotes
            )
            modelContext.insert(newActivity)
            savedActivity = newActivity
        }

        if let minutes = DurationInput.minutes(from: trimmedDuration) {
            let entry = ProjectTimeEntry(activity: savedActivity, durationMinutes: minutes, date: savedActivity.date)
            modelContext.insert(entry)
        }

        try? modelContext.save()
        dismiss()
    }
}
