import SwiftUI
import SwiftData

// Activities (WHAT) grouped under shared purposes (WHY), each with the
// values-in-action (HOW) that connect them — Simon Sinek's "Start With Why"
// / "Find Your Why" framework. Reachable from Main content view, Daily
// Notes, and Focus View (each opens this same list as a sheet).
//
// Adding a new activity runs it through WhyHowWhatService, which checks
// whether it genuinely fits one of the existing Why groups (and folds it in,
// updating that group's Hows) or generates a brand-new Why/How for it.
struct VirtueActivitiesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\WhyGroup.sortOrder), SortDescriptor(\WhyGroup.createdAt, order: .reverse)])
    private var whyGroups: [WhyGroup]
    @Query private var activities: [VirtueActivity]

    @State private var showAdd = false
    // Set when "+" is tapped from a specific Why group's header, so
    // AddWhyActivityView opens pre-scoped to add straight into that group
    // (still switchable to Auto/New Why from within the sheet).
    @State private var groupToAddTo: WhyGroup?
    // Set from a Why header's pencil (or tapping the Why text itself) to
    // edit the whole group at once — Why, every How, and every activity
    // under it — instead of the swipe-to-edit flow, which only opens one
    // activity at a time.
    @State private var groupToEdit: WhyGroup?
    @State private var activityToEdit: VirtueActivity?
    @State private var activityToDelete: VirtueActivity?
    @State private var showDeleteConfirm = false
    @State private var searchText = ""
    @State private var showReminderSettings = false
    @ObservedObject private var reminderManager = ActivityReminderManager.shared

    // Tapping a How chip shows its full "how it's exercised" text — rows no
    // longer open Edit on every tap, only taps outside the chips do.
    @State private var howDetailTarget: HowDetailTarget?

    private func activitiesIn(_ group: WhyGroup) -> [VirtueActivity] {
        (group.activities ?? []).sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.createdAt > b.createdAt
        }
    }

    // A group matches the search if its why/hows match, or any activity
    // under it does. Only the matching activities within it are shown.
    private func matchingActivities(in group: WhyGroup) -> [VirtueActivity] {
        let all = activitiesIn(group)
        guard !searchText.isEmpty else { return all }
        if group.whyStatement.localizedCaseInsensitiveContains(searchText) ||
            group.hows.contains(where: { $0.virtueName.localizedCaseInsensitiveContains(searchText) || $0.howExercised.localizedCaseInsensitiveContains(searchText) }) {
            return all
        }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredGroups: [WhyGroup] {
        guard !searchText.isEmpty else { return whyGroups }
        return whyGroups.filter { !matchingActivities(in: $0).isEmpty }
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

                if whyGroups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No activities yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap + to add one — AI checks your existing Whys first, and either fits it in or creates a new Why, How, What for it.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else if filteredGroups.isEmpty {
                    Text("No activities match \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredGroups) { group in
                        groupSection(group)
                    }
                    // Dragging reorders the real (unfiltered) list, so only allow
                    // it while search isn't narrowing what's shown — otherwise a
                    // dragged section's index wouldn't map to its true position.
                    .onMove(perform: searchText.isEmpty ? moveGroups : nil)
                }
            }
            .navigationTitle("Start with a Why")
            .searchable(text: $searchText, prompt: "Search activities")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !whyGroups.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showReminderSettings = true }) {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.orange)
                        }
                        Button(action: { showAdd = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showReminderSettings) {
                ActivityReminderSettingsView()
            }
            .sheet(isPresented: $showAdd) {
                AddWhyActivityView(preselectedGroup: nil)
            }
            .sheet(item: $groupToAddTo) { group in
                AddWhyActivityView(preselectedGroup: group)
            }
            .sheet(item: $activityToEdit) { activity in
                EditGroupedActivityView(activity: activity)
            }
            .sheet(item: $groupToEdit) { group in
                EditWhyGroupView(group: group)
            }
            .sheet(item: $howDetailTarget) { target in
                HowDetailView(target: target)
                    .presentationDetents([.height(260), .medium])
            }
            .confirmationDialog("Delete this activity?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let a = activityToDelete {
                        let group = a.whyGroup
                        modelContext.delete(a)
                        // An empty Why group left behind by the last activity under
                        // it is just clutter — nothing else references it.
                        if let group, (group.activities ?? []).filter({ $0.id != a.id }).isEmpty {
                            modelContext.delete(group)
                        }
                    }
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the activity and its description.")
            }
            .onAppear(perform: purgeOrphanedActivities)
        }
    }

    // Any VirtueActivity without a WhyGroup is leftover data from before
    // Why/How/What grouping existed (or a partial insert that never got a
    // group) — every activity created through the app's current flows
    // always gets one, so an orphan here is stale, not meaningful data.
    // Broken out of the outer ForEach — a Section+header+nested-ForEach
    // inlined directly there gave the type-checker a single expression
    // complex enough to time out ("unable to type-check in reasonable
    // time"), same category of issue as DailyNotesView's body-splitting
    // comments elsewhere in this codebase.
    @ViewBuilder
    private func groupSection(_ group: WhyGroup) -> some View {
        Section {
            ForEach(matchingActivities(in: group)) { activity in
                activityRow(activity)
            }
        } header: {
            WhyGroupHeader(group: group, onTapHow: { how in
                howDetailTarget = HowDetailTarget(contextLabel: "Why: \(group.whyStatement)", virtueName: how.virtueName, howExercised: how.howExercised)
            }, onAdd: {
                groupToAddTo = group
            }, onEditGroup: {
                groupToEdit = group
            })
        }
    }

    @ViewBuilder
    private func activityRow(_ activity: VirtueActivity) -> some View {
        WhatRow(activity: activity)
            .contentShape(Rectangle())
            .onTapGesture { activityToEdit = activity }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    activityToDelete = activity
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button { activityToEdit = activity } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
    }

    // Re-numbers sortOrder for every Why group based on the new arrangement,
    // same convention as the old flat activity list's own reordering.
    private func moveGroups(from source: IndexSet, to destination: Int) {
        var reordered = whyGroups
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, group) in reordered.enumerated() {
            group.sortOrder = index
        }
        try? modelContext.save()
    }

    private func purgeOrphanedActivities() {
        let orphans = activities.filter { $0.whyGroup == nil }
        guard !orphans.isEmpty else { return }
        for orphan in orphans { modelContext.delete(orphan) }
        try? modelContext.save()
    }
}

// Identifies one How pairing tapped from a group header, so its full
// "how it's exercised" text can be shown.
private struct HowDetailTarget: Identifiable {
    let id = UUID()
    let contextLabel: String
    let virtueName: String
    let howExercised: String
}

private struct HowDetailView: View {
    let target: HowDetailTarget
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(target.virtueName)
                    .font(.title2.bold())
                Text(target.contextLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Divider()
                Text(target.howExercised.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "No explanation set yet." : target.howExercised)
                    .font(.body)
                Spacer()
            }
            .padding()
            .navigationTitle("How It's Exercised")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Rows

private struct WhyGroupHeader: View {
    let group: WhyGroup
    var onTapHow: (VirtueExplanation) -> Void
    var onAdd: () -> Void
    var onEditGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(group.whyStatement)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .textCase(nil)
                    .onTapGesture(perform: onEditGroup)
                Spacer()
                Button(action: onEditGroup) {
                    Image(systemName: "pencil.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Button(action: onAdd) {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            if !group.hows.isEmpty {
                // Horizontally scrollable, un-truncated — a Why with many
                // Hows would otherwise get clipped/wrapped awkwardly inside
                // a fixed-width List section header.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(group.hows) { how in
                            Button(action: { onTapHow(how) }) {
                                Text(how.virtueName)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.yellow.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 2)
    }
}

private struct WhatRow: View {
    let activity: VirtueActivity

    var body: some View {
        Text(activity.name)
            .font(.body)
            .foregroundColor(.primary)
            .padding(.vertical, 2)
    }
}

// MARK: - Add Activity (AI-classified)

// Types an activity name, runs it through WhyHowWhatService, previews the
// result (matched existing Why, or a brand-new one), then saves.
struct AddWhyActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\WhyGroup.sortOrder)]) private var whyGroups: [WhyGroup]

    // How the typed activities should be grouped.
    enum GroupingMode: Hashable {
        case auto
        case existing(UUID)
        case newWhy
    }

    // Generate the Why/How with AI, or write it all yourself from scratch —
    // for when you already know exactly what the purpose is.
    private enum CreationMode: Hashable {
        case ai
        case manual
    }

    // When opened from a specific Why group's "+", pre-locks the picker to
    // that group (still switchable to Auto/New Why/another group).
    let preselectedGroup: WhyGroup?

    @State private var creationMode: CreationMode = .ai
    @State private var namesText: String = ""
    @State private var groupingMode: GroupingMode
    @State private var isGenerating = false
    @State private var generationError: String?
    // Usually one resulting group, but Auto mode on a batch of activities
    // that don't all share a purpose can come back with several.
    @State private var previewGroups: [WhyHowWhatService.Classification] = []

    // Manual entry — only used when creationMode == .manual and groupingMode == .newWhy.
    @State private var manualWhyStatement: String = ""
    @State private var manualHows: [VirtueExplanation] = []

    init(preselectedGroup: WhyGroup?) {
        self.preselectedGroup = preselectedGroup
        _groupingMode = State(initialValue: preselectedGroup.map { .existing($0.id) } ?? .auto)
    }

    private var activityNames: [String] {
        namesText
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var groupFooterText: String {
        switch (creationMode, groupingMode) {
        case (.ai, .auto):
            return "AI checks your existing Why groups first, and either fits each activity into one of them or clusters new activities together under a brand-new Why."
        case (.ai, .existing):
            return "These will be added to the selected Why. AI updates its Why/How statements so they genuinely cover the new activities too."
        case (.ai, .newWhy):
            return "AI generates a brand-new Why and Hows covering exactly these activities, ignoring your existing Why groups entirely."
        case (.manual, .existing):
            return "These activities are added directly to the selected Why — nothing is generated."
        case (.manual, .newWhy), (.manual, .auto):
            return "Write the Why and Hows yourself below — nothing is generated."
        }
    }

    private func sectionTitle(for group: WhyHowWhatService.Classification) -> String {
        group.matchedWhyID != nil ? "Existing Why" : "New Why"
    }

    private var canSaveManual: Bool {
        guard !activityNames.isEmpty else { return false }
        if case .newWhy = groupingMode {
            return !manualWhyStatement.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                activitiesSection
                groupPickerSection
                if creationMode == .ai {
                    generateSection
                    previewSections
                } else {
                    manualWhySections
                }
            }
            .navigationTitle("Add Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if creationMode == .ai {
                        Button("Save") { save() }
                            .disabled(previewGroups.isEmpty)
                    } else {
                        Button("Save") { saveManual() }
                            .disabled(!canSaveManual)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var modeSection: some View {
        Section {
            Picker("", selection: $creationMode) {
                Text("Generate with AI").tag(CreationMode.ai)
                Text("Write it myself").tag(CreationMode.manual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: creationMode) { _, newValue in
                previewGroups = []
                // Auto only makes sense when AI is deciding fit — manual
                // entry needs an explicit Why (existing or new) to write into.
                if newValue == .manual, groupingMode == .auto {
                    groupingMode = .newWhy
                }
            }
        }
    }

    // Each broken out into its own @ViewBuilder — a Form this deep (picker
    // with a ForEach tag list, plus a second ForEach of preview sections,
    // all inlined into one body) hit the same "unable to type-check in
    // reasonable time" wall documented elsewhere in this codebase.

    @ViewBuilder
    private var activitiesSection: some View {
        Section {
            TextEditor(text: $namesText)
                .frame(minHeight: 90)
                .onChange(of: namesText) { _, _ in previewGroups = [] }
        } header: {
            Text("Activities")
        } footer: {
            if creationMode == .ai {
                Text("One per line (or comma-separated) — add several at once to create or fit into a Why together. If you type a value/trait instead of an activity (e.g. \"Discipline\"), it's used as a How and a fitting activity is generated for it.")
            } else {
                Text("One per line (or comma-separated).")
            }
        }
    }

    @ViewBuilder
    private var groupPickerSection: some View {
        Section {
            Picker("Group under", selection: $groupingMode) {
                if creationMode == .ai {
                    Text("Auto (AI decides)").tag(GroupingMode.auto)
                }
                ForEach(whyGroups) { group in
                    Text(group.whyStatement).lineLimit(1).tag(GroupingMode.existing(group.id))
                }
                Text("New Why").tag(GroupingMode.newWhy)
            }
            .pickerStyle(.navigationLink)
            .onChange(of: groupingMode) { _, _ in previewGroups = [] }
        } footer: {
            Text(groupFooterText)
        }
    }

    @ViewBuilder
    private var generateSection: some View {
        Section {
            Button {
                generate()
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView().padding(.trailing, 4)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(previewGroups.isEmpty ? "Generate with AI" : "Re-run")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isGenerating || activityNames.isEmpty)

            if let generationError {
                Text(generationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var previewSections: some View {
        ForEach(previewGroups.indices, id: \.self) { idx in
            previewSection(previewGroups[idx])
        }
    }

    @ViewBuilder
    private func previewSection(_ group: WhyHowWhatService.Classification) -> some View {
        Section(sectionTitle(for: group)) {
            Text(group.whyStatement)
                .font(.subheadline)
            ForEach(group.hows) { how in
                VStack(alignment: .leading, spacing: 2) {
                    Text(how.virtueName).font(.subheadline.weight(.semibold))
                    Text(how.howExercised).font(.caption).foregroundColor(.secondary)
                }
            }
            ForEach(group.whats, id: \.self) { what in
                Label(what, systemImage: "checkmark.circle")
                    .font(.subheadline)
            }
        }
    }

    // Shown instead of the AI generate/preview flow when "Write it myself"
    // is selected — only relevant when writing a brand-new Why; attaching to
    // an existing one needs nothing more than the activity names above.
    @ViewBuilder
    private var manualWhySections: some View {
        if case .newWhy = groupingMode {
            Section {
                TextField("Why statement", text: $manualWhyStatement, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Why")
            } footer: {
                Text("e.g. \"To ... so that ...\"")
            }

            ForEach(manualHows.indices, id: \.self) { idx in
                Section("How") {
                    TextField("Value name", text: $manualHows[idx].virtueName)
                    TextField("What it looks like in action", text: $manualHows[idx].howExercised, axis: .vertical)
                        .lineLimit(2...4)
                    Button(role: .destructive) {
                        manualHows.remove(at: idx)
                    } label: {
                        Label("Remove How", systemImage: "minus.circle")
                    }
                }
            }

            Section {
                Button {
                    manualHows.append(VirtueExplanation(virtueName: "", howExercised: ""))
                } label: {
                    Label("Add How", systemImage: "plus.circle")
                }
            }
        }
    }

    private func generate() {
        isGenerating = true
        generationError = nil
        previewGroups = []
        let names = activityNames
        let existing = whyGroups.map { group in
            WhyHowWhatService.ExistingWhy(
                id: group.id,
                whyStatement: group.whyStatement,
                hows: group.hows,
                activityNames: (group.activities ?? []).map { $0.name }
            )
        }
        let mode = groupingMode
        let service = WhyHowWhatService()

        _Concurrency.Task {
            do {
                let results: [WhyHowWhatService.Classification]
                switch mode {
                case .auto:
                    results = try await service.classifyMultiple(newActivityNames: names, existingWhys: existing)
                case .existing(let id):
                    let forced = existing.first { $0.id == id }
                    results = [try await service.assignToWhy(activityNames: names, forcedWhy: forced)]
                case .newWhy:
                    results = [try await service.assignToWhy(activityNames: names, forcedWhy: nil)]
                }
                await MainActor.run {
                    previewGroups = results
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
        guard !previewGroups.isEmpty else { return }
        for group in previewGroups {
            if let matchedID = group.matchedWhyID, let existingGroup = whyGroups.first(where: { $0.id == matchedID }) {
                existingGroup.whyStatement = group.whyStatement
                existingGroup.hows = group.hows
                existingGroup.updatedAt = Date()
                var nextOrder = ((existingGroup.activities ?? []).map { $0.sortOrder }.max() ?? -1) + 1
                for what in group.whats {
                    modelContext.insert(VirtueActivity(name: what, sortOrder: nextOrder, whyGroup: existingGroup))
                    nextOrder += 1
                }
            } else {
                let nextGroupOrder = (whyGroups.map { $0.sortOrder }.max() ?? -1) + 1
                let newGroup = WhyGroup(whyStatement: group.whyStatement, hows: group.hows, sortOrder: nextGroupOrder)
                modelContext.insert(newGroup)
                for (i, what) in group.whats.enumerated() {
                    modelContext.insert(VirtueActivity(name: what, sortOrder: i, whyGroup: newGroup))
                }
            }
        }
        try? modelContext.save()
        dismiss()
    }

    // "Write it myself" — no AI call at all. Either attaches the typed
    // activities to an existing Why as-is, or creates a brand-new Why/How
    // from exactly what was typed.
    private func saveManual() {
        let names = activityNames
        guard !names.isEmpty else { return }

        switch groupingMode {
        case .existing(let id):
            guard let group = whyGroups.first(where: { $0.id == id }) else { return }
            var nextOrder = ((group.activities ?? []).map { $0.sortOrder }.max() ?? -1) + 1
            for name in names {
                modelContext.insert(VirtueActivity(name: name, sortOrder: nextOrder, whyGroup: group))
                nextOrder += 1
            }
        case .newWhy, .auto:
            let cleanedHows = manualHows.filter { !$0.virtueName.trimmingCharacters(in: .whitespaces).isEmpty }
            let nextGroupOrder = (whyGroups.map { $0.sortOrder }.max() ?? -1) + 1
            let newGroup = WhyGroup(whyStatement: manualWhyStatement.trimmingCharacters(in: .whitespaces), hows: cleanedHows, sortOrder: nextGroupOrder)
            modelContext.insert(newGroup)
            for (i, name) in names.enumerated() {
                modelContext.insert(VirtueActivity(name: name, sortOrder: i, whyGroup: newGroup))
            }
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Edit a grouped activity

// Editing here changes the shared Why/How for the whole group (every
// sibling activity under it), plus this activity's own name. "Re-classify
// with AI" treats it like a fresh add — it can move to a different existing
// group, or spin off into a new one — and cleans up its old group if that
// leaves it empty.
struct EditGroupedActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var whyGroups: [WhyGroup]

    let activity: VirtueActivity

    @State private var name: String
    @State private var whyStatement: String
    @State private var hows: [VirtueExplanation]
    // Full "Re-classify with AI" (regenerates why/how/what together, and can
    // move the activity to a different group entirely).
    @State private var isGenerating = false
    // Granular regeneration — one Why button, one button per How row.
    @State private var isRegeneratingWhy = false
    @State private var regeneratingHowIndex: Int?
    @State private var generationError: String?

    init(activity: VirtueActivity) {
        self.activity = activity
        _name = State(initialValue: activity.name)
        _whyStatement = State(initialValue: activity.whyGroup?.whyStatement ?? "")
        _hows = State(initialValue: activity.whyGroup?.hows ?? [])
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Only one AI call runs at a time — disables every AI button (not just
    // the one in flight) so a full re-classify can't race a granular
    // Why/How regeneration.
    private var isBusy: Bool {
        isGenerating || isRegeneratingWhy || regeneratingHowIndex != nil
    }

    private var siblingActivityNames: [String] {
        (activity.whyGroup?.activities ?? []).map { $0.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity (What)") {
                    TextField("Activity name", text: $name)
                }

                Section {
                    TextField("Why statement", text: $whyStatement, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    HStack {
                        Text("Why")
                        Spacer()
                        Button(action: regenerateWhy) {
                            if isRegeneratingWhy {
                                ProgressView()
                            } else {
                                Image(systemName: "sparkles")
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                    }
                } footer: {
                    Text("Shared with every other activity under this Why — editing it changes it for all of them. Sparkles regenerates just the Why, keeping the current Hows/activities as context.")
                }

                ForEach(hows.indices, id: \.self) { idx in
                    Section {
                        TextField("Value name", text: $hows[idx].virtueName)
                        TextField("What it looks like in action", text: $hows[idx].howExercised, axis: .vertical)
                            .lineLimit(2...4)
                        Button(role: .destructive) {
                            hows.remove(at: idx)
                        } label: {
                            Label("Remove How", systemImage: "minus.circle")
                        }
                    } header: {
                        HStack {
                            Text("How")
                            Spacer()
                            Button(action: { regenerateHow(at: idx) }) {
                                if regeneratingHowIndex == idx {
                                    ProgressView()
                                } else {
                                    Image(systemName: "sparkles")
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy)
                        }
                    }
                }

                Section {
                    Button {
                        hows.append(VirtueExplanation(virtueName: "", howExercised: ""))
                    } label: {
                        Label("Add How", systemImage: "plus.circle")
                    }
                }

                Section {
                    Button {
                        reclassify()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView().padding(.trailing, 4)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text("Re-classify with AI")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isBusy || name.trimmingCharacters(in: .whitespaces).isEmpty)

                    if let generationError {
                        Text(generationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Re-checks this activity against all Why groups (including this one) and may move it to a better-fitting one, or spin off a new Why if none fit anymore.")
                }
            }
            .navigationTitle("Edit Activity")
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

    // Regenerates just the Why text — keeps the current Hows and this
    // group's sibling activities as context so the new phrasing still
    // covers all of them, but asks for a genuinely different angle.
    private func regenerateWhy() {
        isRegeneratingWhy = true
        generationError = nil
        let currentWhy = whyStatement
        let currentHows = hows
        let names = siblingActivityNames
        let service = WhyHowWhatService()

        _Concurrency.Task {
            do {
                let newWhy = try await service.regenerateWhy(currentWhy: currentWhy, hows: currentHows, activityNames: names)
                await MainActor.run {
                    whyStatement = newWhy
                    isRegeneratingWhy = false
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    isRegeneratingWhy = false
                }
            }
        }
    }

    // Regenerates a single How row — keeps the Why, activities, and every
    // OTHER How as context so the result doesn't duplicate one already there.
    private func regenerateHow(at idx: Int) {
        guard hows.indices.contains(idx) else { return }
        regeneratingHowIndex = idx
        generationError = nil
        let currentHow = hows[idx]
        let otherHows = hows.enumerated().filter { $0.offset != idx }.map { $0.element }
        let why = whyStatement
        let names = siblingActivityNames
        let service = WhyHowWhatService()

        _Concurrency.Task {
            do {
                let newHow = try await service.regenerateHow(why: why, otherHows: otherHows, activityNames: names, currentHow: currentHow)
                await MainActor.run {
                    if hows.indices.contains(idx) {
                        hows[idx] = newHow
                    }
                    regeneratingHowIndex = nil
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    regeneratingHowIndex = nil
                }
            }
        }
    }

    private func reclassify() {
        isGenerating = true
        generationError = nil
        let activityName = name.trimmingCharacters(in: .whitespaces)
        let currentGroupID = activity.whyGroup?.id
        let existing = whyGroups.map { group -> WhyHowWhatService.ExistingWhy in
            let names = (group.activities ?? [])
                .filter { $0.id != activity.id }
                .map { $0.name }
            return WhyHowWhatService.ExistingWhy(id: group.id, whyStatement: group.whyStatement, hows: group.hows, activityNames: names)
        }
        let service = WhyHowWhatService()

        _Concurrency.Task {
            do {
                let result = try await service.classify(newActivityName: activityName, existingWhys: existing)
                await MainActor.run {
                    applyReclassification(result, previousGroupID: currentGroupID)
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

    // Applies the AI result immediately (rather than just previewing) since
    // this is an already-saved activity being re-classified, not a new one.
    private func applyReclassification(_ result: WhyHowWhatService.Classification, previousGroupID: UUID?) {
        let previousGroup = whyGroups.first { $0.id == previousGroupID }

        let targetGroup: WhyGroup
        if let matchedID = result.matchedWhyID, let existingGroup = whyGroups.first(where: { $0.id == matchedID }) {
            targetGroup = existingGroup
        } else {
            let nextGroupOrder = (whyGroups.map { $0.sortOrder }.max() ?? -1) + 1
            targetGroup = WhyGroup(whyStatement: result.whyStatement, hows: result.hows, sortOrder: nextGroupOrder)
            modelContext.insert(targetGroup)
        }
        targetGroup.whyStatement = result.whyStatement
        targetGroup.hows = result.hows
        targetGroup.updatedAt = Date()

        let cleanedName = result.whats.first ?? activity.name
        activity.name = cleanedName
        activity.whyGroup = targetGroup
        activity.updatedAt = Date()

        name = cleanedName
        whyStatement = targetGroup.whyStatement
        hows = targetGroup.hows

        // Left the old group empty — nothing else references it.
        if let previousGroup, previousGroup.id != targetGroup.id,
           (previousGroup.activities ?? []).filter({ $0.id != activity.id }).isEmpty {
            modelContext.delete(previousGroup)
        }

        try? modelContext.save()
    }

    private func save() {
        activity.name = name.trimmingCharacters(in: .whitespaces)
        activity.updatedAt = Date()
        if let group = activity.whyGroup {
            group.whyStatement = whyStatement
            group.hows = hows.filter { !$0.virtueName.trimmingCharacters(in: .whitespaces).isEmpty }
            group.updatedAt = Date()
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Edit a whole Why group at once

// Edits the Why, every How, and every activity (What) under this group
// together in one screen — reached by tapping a Why header (or its pencil
// icon). Distinct from swiping an individual activity, which only opens
// EditGroupedActivityView for that one activity.
struct EditWhyGroupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let group: WhyGroup

    private struct ActivityEdit: Identifiable {
        let activity: VirtueActivity
        var name: String
        var id: UUID { activity.id }
    }

    @State private var whyStatement: String
    @State private var hows: [VirtueExplanation]
    @State private var activityEdits: [ActivityEdit]
    @State private var showAddActivity = false

    @State private var isRegeneratingWhy = false
    @State private var regeneratingHowIndex: Int?
    @State private var generationError: String?

    init(group: WhyGroup) {
        self.group = group
        _whyStatement = State(initialValue: group.whyStatement)
        _hows = State(initialValue: group.hows)
        let sorted = (group.activities ?? []).sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.createdAt > b.createdAt
        }
        _activityEdits = State(initialValue: sorted.map { ActivityEdit(activity: $0, name: $0.name) })
    }

    private var isBusy: Bool {
        isRegeneratingWhy || regeneratingHowIndex != nil
    }

    private var activityNames: [String] {
        activityEdits.map { $0.name }
    }

    private var canSave: Bool {
        !whyStatement.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                whySection
                howsSections
                addHowSection
                activitiesSection
            }
            .navigationTitle("Edit Why")
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
            .sheet(isPresented: $showAddActivity) {
                AddWhyActivityView(preselectedGroup: group)
            }
        }
    }

    @ViewBuilder
    private var whySection: some View {
        Section {
            TextField("Why statement", text: $whyStatement, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            HStack {
                Text("Why")
                Spacer()
                Button(action: regenerateWhy) {
                    if isRegeneratingWhy {
                        ProgressView()
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        } footer: {
            if let generationError {
                Text(generationError).foregroundStyle(.red)
            } else {
                Text("Shared by every activity below — regenerating considers all of them.")
            }
        }
    }

    @ViewBuilder
    private var howsSections: some View {
        ForEach(hows.indices, id: \.self) { idx in
            Section {
                TextField("Value name", text: $hows[idx].virtueName)
                TextField("What it looks like in action", text: $hows[idx].howExercised, axis: .vertical)
                    .lineLimit(2...4)
                Button(role: .destructive) {
                    hows.remove(at: idx)
                } label: {
                    Label("Remove How", systemImage: "minus.circle")
                }
            } header: {
                HStack {
                    Text("How")
                    Spacer()
                    Button(action: { regenerateHow(at: idx) }) {
                        if regeneratingHowIndex == idx {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkles")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
        }
    }

    @ViewBuilder
    private var addHowSection: some View {
        Section {
            Button {
                hows.append(VirtueExplanation(virtueName: "", howExercised: ""))
            } label: {
                Label("Add How", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private var activitiesSection: some View {
        Section {
            ForEach($activityEdits) { $edit in
                TextField("Activity name", text: $edit.name)
            }
            .onDelete(perform: deleteActivities)
            Button {
                showAddActivity = true
            } label: {
                Label("Add Activity", systemImage: "plus.circle")
            }
        } header: {
            Text("Activities (What)")
        } footer: {
            Text("Swipe to remove one. Removing the last activity here deletes this Why group.")
        }
    }

    private func deleteActivities(at offsets: IndexSet) {
        activityEdits.remove(atOffsets: offsets)
    }

    // Regenerates just the Why text — same behavior as EditGroupedActivityView's
    // version, but naturally scoped to every activity in the group at once
    // since there's no single "current activity" here.
    private func regenerateWhy() {
        isRegeneratingWhy = true
        generationError = nil
        let currentWhy = whyStatement
        let currentHows = hows
        let names = activityNames
        let service = WhyHowWhatService()

        _Concurrency.Task {
            do {
                let newWhy = try await service.regenerateWhy(currentWhy: currentWhy, hows: currentHows, activityNames: names)
                await MainActor.run {
                    whyStatement = newWhy
                    isRegeneratingWhy = false
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    isRegeneratingWhy = false
                }
            }
        }
    }

    private func regenerateHow(at idx: Int) {
        guard hows.indices.contains(idx) else { return }
        regeneratingHowIndex = idx
        generationError = nil
        let currentHow = hows[idx]
        let otherHows = hows.enumerated().filter { $0.offset != idx }.map { $0.element }
        let why = whyStatement
        let names = activityNames
        let service = WhyHowWhatService()

        _Concurrency.Task {
            do {
                let newHow = try await service.regenerateHow(why: why, otherHows: otherHows, activityNames: names, currentHow: currentHow)
                await MainActor.run {
                    if hows.indices.contains(idx) {
                        hows[idx] = newHow
                    }
                    regeneratingHowIndex = nil
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    regeneratingHowIndex = nil
                }
            }
        }
    }

    private func save() {
        group.whyStatement = whyStatement.trimmingCharacters(in: .whitespaces)
        group.hows = hows.filter { !$0.virtueName.trimmingCharacters(in: .whitespaces).isEmpty }
        group.updatedAt = Date()

        for edit in activityEdits {
            let trimmed = edit.name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            edit.activity.name = trimmed
            edit.activity.updatedAt = Date()
        }

        // Anything swiped out of the edit list above gets deleted outright.
        let keptIDs = Set(activityEdits.map { $0.activity.id })
        for activity in (group.activities ?? []) where !keptIDs.contains(activity.id) {
            modelContext.delete(activity)
        }

        // Emptied out entirely — nothing left to reference this Why.
        if activityEdits.isEmpty {
            modelContext.delete(group)
        }

        try? modelContext.save()
        dismiss()
    }
}
