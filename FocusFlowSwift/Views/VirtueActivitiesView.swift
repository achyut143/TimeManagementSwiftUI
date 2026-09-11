import SwiftUI
import SwiftData

// List of VirtueActivity entities — activities you've defined with a
// virtue-based "why". Reachable from Main content view, Daily Notes, and
// Focus View (each opens this same list as a sheet).
struct VirtueActivitiesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\VirtueActivity.sortOrder), SortDescriptor(\VirtueActivity.createdAt, order: .reverse)])
    private var activities: [VirtueActivity]

    @State private var showCreate = false
    @State private var activityToEdit: VirtueActivity?
    @State private var activityToDelete: VirtueActivity?
    @State private var showDeleteConfirm = false
    @State private var searchText = ""
    @State private var showReminderSettings = false
    @ObservedObject private var reminderManager = ActivityReminderManager.shared

    // Matches the name, any virtue name, or the "why" text — a substring
    // anywhere in those counts as a match, case-insensitive.
    private var filteredActivities: [VirtueActivity] {
        guard !searchText.isEmpty else { return activities }
        return activities.filter { activity in
            if activity.name.localizedCaseInsensitiveContains(searchText) { return true }
            if activity.whyReason.localizedCaseInsensitiveContains(searchText) { return true }
            return activity.explanations.contains { $0.virtueName.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if reminderManager.isPendingAcknowledgment {
                    Section {
                        Button(action: { reminderManager.acknowledge() }) {
                            HStack {
                                Image(systemName: "bell.badge.fill")
                                Text("Time to enhance spiritual energy — Tap to Acknowledge")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .foregroundColor(.white)
                        }
                        .listRowBackground(Color.orange)
                    }
                }

                if activities.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No activities yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap + to add one — name it, then generate or write the 2 virtues it exercises and why you want to do it.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else if filteredActivities.isEmpty {
                    Text("No activities match \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredActivities) { activity in
                        Button {
                            activityToEdit = activity
                        } label: {
                            VirtueActivityRow(activity: activity)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                activityToDelete = activity
                                showDeleteConfirm = true
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
                    // Dragging reorders the real (unfiltered) list, so only
                    // allow it while search isn't narrowing what's shown —
                    // otherwise a dragged row's index wouldn't map to its
                    // true position.
                    .onMove(perform: searchText.isEmpty ? move : nil)
                }
            }
            .navigationTitle("Activities")
            .searchable(text: $searchText, prompt: "Search activities")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !activities.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showReminderSettings = true }) {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.orange)
                        }
                        Button(action: { showCreate = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showReminderSettings) {
                ActivityReminderSettingsView()
            }
            .sheet(isPresented: $showCreate) {
                EditVirtueActivityView(activity: nil)
            }
            .sheet(item: $activityToEdit) { activity in
                EditVirtueActivityView(activity: activity)
            }
            .confirmationDialog("Delete this activity?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let a = activityToDelete { modelContext.delete(a) }
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the activity and its description.")
            }
        }
    }

    // Re-numbers sortOrder for every activity based on the new arrangement,
    // so the ordering sticks even after createdAt-based tiebreaks would
    // otherwise apply (e.g. once every row shares sortOrder 0 on a fresh
    // install, moving anything gives all rows a real, distinct order).
    private func move(from source: IndexSet, to destination: Int) {
        var reordered = activities
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, activity) in reordered.enumerated() {
            activity.sortOrder = index
        }
        try? modelContext.save()
    }
}

private struct VirtueActivityRow: View {
    let activity: VirtueActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activity.name)
                .font(.headline)
                .foregroundColor(.primary)

            if !activity.explanations.isEmpty {
                HStack(spacing: 6) {
                    ForEach(activity.explanations) { exp in
                        Text(exp.virtueName)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.yellow.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                }
            }

            if !activity.whyReason.isEmpty {
                Text(activity.whyReason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// Create + edit in one view (matches CreateRestraintView's pattern). All
// fields are freely editable by hand; "Regenerate with AI" overwrites the
// virtues + why with a fresh call, keeping the activity name.
struct EditVirtueActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allActivities: [VirtueActivity]

    var activity: VirtueActivity?

    @State private var name: String
    @State private var explanations: [VirtueExplanation]
    @State private var whyReason: String
    @State private var isGenerating = false
    @State private var generationError: String?

    init(activity: VirtueActivity?) {
        self.activity = activity
        _name = State(initialValue: activity?.name ?? "")
        _explanations = State(initialValue: activity?.explanations ?? [])
        _whyReason = State(initialValue: activity?.whyReason ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Fixed virtue list, minus whatever's already added to this activity —
    // so the menu only offers virtues you haven't already picked.
    private var availableVirtues: [String] {
        let used = Set(explanations.map { $0.virtueName.lowercased() })
        return ActivityVirtueService.virtueList.filter { !used.contains($0.lowercased()) }
    }

    private func addVirtue(named virtue: String) {
        explanations.append(VirtueExplanation(virtueName: virtue, howExercised: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    TextField("e.g. Cold showers, Reading, Journaling", text: $name)
                }

                ForEach(explanations.indices, id: \.self) { idx in
                    Section("Virtue") {
                        TextField("Virtue name", text: $explanations[idx].virtueName)
                        TextField("How it is exercised", text: $explanations[idx].howExercised, axis: .vertical)
                            .lineLimit(2...4)
                        Button(role: .destructive) {
                            explanations.remove(at: idx)
                        } label: {
                            Label("Remove Virtue", systemImage: "minus.circle")
                        }
                    }
                }

                Section {
                    Menu {
                        ForEach(availableVirtues, id: \.self) { virtue in
                            Button(virtue) { addVirtue(named: virtue) }
                        }
                        if !availableVirtues.isEmpty {
                            Divider()
                        }
                        Button("Custom…") { addVirtue(named: "") }
                    } label: {
                        Label("Add Virtue", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("Pick from your virtue list, or add a custom one and type your own name.")
                }

                Section("Why should I do it?") {
                    TextField("A short, selfless reason", text: $whyReason, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Button {
                        regenerate()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(explanations.isEmpty && whyReason.isEmpty ? "Generate with AI" : "Regenerate with AI")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isGenerating || name.trimmingCharacters(in: .whitespaces).isEmpty)

                    if let generationError {
                        Text(generationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Uses your fixed virtue list to identify 2 virtues this activity exercises and one selfless reason to do it. Regenerating replaces the virtues and reason above — the activity name stays.")
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
        }
    }

    private func regenerate() {
        isGenerating = true
        generationError = nil
        let service = ActivityVirtueService()
        let activityName = name

        _Concurrency.Task {
            do {
                let result = try await service.generateDescription(activityName: activityName)
                await MainActor.run {
                    if !result.properName.isEmpty {
                        name = result.properName
                    }
                    explanations = result.virtues
                    whyReason = result.why
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let cleanedExplanations = explanations.filter { !$0.virtueName.trimmingCharacters(in: .whitespaces).isEmpty }
        if let activity {
            activity.name = trimmedName
            activity.explanations = cleanedExplanations
            activity.whyReason = whyReason
            activity.updatedAt = Date()
        } else {
            let nextOrder = (allActivities.map { $0.sortOrder }.max() ?? -1) + 1
            let newActivity = VirtueActivity(name: trimmedName, explanations: cleanedExplanations, whyReason: whyReason, sortOrder: nextOrder)
            modelContext.insert(newActivity)
        }
        try? modelContext.save()
        dismiss()
    }
}
