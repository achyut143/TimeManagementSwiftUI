import SwiftUI
import SwiftData

/// Pick, create and review workouts: Tabata, Reps and History tabs.
struct WorkoutsView: View {
    enum WorkoutTab: String, CaseIterable, Identifiable {
        case tabata = "Tabata", reps = "Reps", history = "History"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TabataWorkout.createdAt, order: .reverse) private var tabatas: [TabataWorkout]
    @Query(sort: \RepWorkout.createdAt, order: .reverse) private var repWorkouts: [RepWorkout]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @AppStorage("workout.lastTab") private var sectionRaw = WorkoutTab.tabata.rawValue

    @State private var editingTabata: TabataWorkout?
    @State private var editingReps: RepWorkout?
    @State private var creatingTabata = false
    @State private var creatingReps = false
    @State private var showSettings = false
    @State private var creatingWithAI = false

    private var section: WorkoutTab { WorkoutTab(rawValue: sectionRaw) ?? .tabata }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $sectionRaw) {
                ForEach(WorkoutTab.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            switch section {
            case .tabata: tabataList
            case .reps: repList
            case .history: historyList
            }
        }
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Workout settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Create with AI", systemImage: "sparkles") { creatingWithAI = true }
                    Divider()
                    Button("New Tabata", systemImage: "timer") { creatingTabata = true }
                    Button("New rep workout", systemImage: "dumbbell.fill") { creatingReps = true }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create workout")
            }
        }
        .sheet(isPresented: $creatingTabata) { TabataEditorView(workout: nil) }
        .sheet(isPresented: $creatingReps) { RepWorkoutEditorView(workout: nil) }
        .sheet(item: $editingTabata) { TabataEditorView(workout: $0) }
        .sheet(item: $editingReps) { RepWorkoutEditorView(workout: $0) }
        .sheet(isPresented: $showSettings) { WorkoutSettingsView() }
        .sheet(isPresented: $creatingWithAI) { AIWorkoutCreateView() }
    }

    // MARK: Lists

    @ViewBuilder private var tabataList: some View {
        if tabatas.isEmpty {
            emptyState("No Tabatas yet", icon: "timer", action: "New Tabata") { creatingTabata = true }
        } else {
            List {
                ForEach(tabatas) { workout in
                    NavigationLink {
                        TabataDetailView(workout: workout)
                    } label: {
                        WorkoutRow(name: workout.name, summary: workout.summary, icon: "timer")
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editingTabata = workout }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(workout) }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(workout) }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(workout) }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(workout) }.tint(.indigo)
                        Button("Edit", systemImage: "pencil") { editingTabata = workout }.tint(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder private var repList: some View {
        if repWorkouts.isEmpty {
            emptyState("No rep workouts yet", icon: "dumbbell", action: "New rep workout") { creatingReps = true }
        } else {
            List {
                ForEach(repWorkouts) { workout in
                    NavigationLink {
                        RepWorkoutDetailView(workout: workout)
                    } label: {
                        WorkoutRow(name: workout.name, summary: workout.summary, icon: "dumbbell.fill")
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editingReps = workout }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(workout) }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(workout) }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(workout) }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(workout) }.tint(.indigo)
                        Button("Edit", systemImage: "pencil") { editingReps = workout }.tint(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder private var historyList: some View {
        if sessions.isEmpty {
            ContentUnavailableView("No finished workouts", systemImage: "clock.arrow.circlepath",
                                   description: Text("Workouts you finish or stop appear here."))
        } else {
            List {
                ForEach(sessions) { session in
                    NavigationLink {
                        WorkoutSessionDetailView(session: session)
                    } label: {
                        HistoryRow(session: session)
                    }
                }
                .onDelete { offsets in
                    offsets.map { sessions[$0] }.forEach(modelContext.delete)
                    try? modelContext.save()
                }
            }
        }
    }

    private func emptyState(_ title: String, icon: String, action: String, perform: @escaping () -> Void) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } actions: {
            Button(action, action: perform).buttonStyle(.borderedProminent)
        }
    }

    // MARK: Actions

    private func duplicate(_ w: TabataWorkout) {
        let copy = TabataWorkout(name: w.name + " copy")
        copy.apply(w.draft)
        copy.name = w.name + " copy"
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func duplicate(_ w: RepWorkout) {
        let copy = RepWorkout(name: w.name + " copy")
        copy.sets = w.sets.map { set in
            var s = set
            s.id = UUID()
            s.exercises = set.exercises.map { var e = $0; e.id = UUID(); return e }
            return s
        }
        copy.restBetweenSetsSeconds = w.restBetweenSetsSeconds
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func delete(_ model: any PersistentModel) {
        modelContext.delete(model)
        try? modelContext.save()
        WorkoutPictureStore.removeUnused(context: modelContext)
    }
}

// MARK: - Rows

private struct WorkoutRow: View {
    let name: String
    let summary: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HistoryRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack {
            Image(systemName: session.kind.icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name).font(.headline)
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(WorkoutFormat.clock(session.durationSeconds)).monospacedDigit()
                Text(session.completed ? "Completed" : "Stopped early")
                    .font(.caption)
                    .foregroundStyle(session.completed ? .green : .orange)
            }
        }
    }
}

// MARK: - Details

struct TabataDetailView: View {
    @Bindable var workout: TabataWorkout
    @State private var running = false
    @State private var editing = false

    var body: some View {
        let draft = workout.draft
        List {
            SwiftUI.Section {
                LabeledContent("Prepare", value: WorkoutFormat.clock(draft.prepareSeconds))
                LabeledContent("Work", value: WorkoutFormat.clock(draft.workSeconds))
                LabeledContent("Rest", value: draft.restSeconds == 0 ? "No rest" : WorkoutFormat.clock(draft.restSeconds))
                LabeledContent("Cycles × rounds", value: "\(draft.cycles) × \(draft.rounds)")
                if draft.rounds > 1 {
                    LabeledContent("Rest between rounds", value: draft.restBetweenRoundsSeconds == 0 ? "None" : WorkoutFormat.clock(draft.restBetweenRoundsSeconds))
                }
                LabeledContent("Total time", value: WorkoutFormat.clock(draft.totalSeconds))
            }
            SwiftUI.Section("Exercises") {
                ForEach(0..<draft.cycles, id: \.self) { i in
                    HStack {
                        Text("\(i + 1)").foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
                        Text(draft.exerciseName(cycle: i))
                        Spacer()
                        WorkoutPictureThumb(imageID: draft.imageID(cycle: i))
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .safeAreaInset(edge: .bottom) {
            StartButton { running = true }
        }
        .toolbar {
            Button("Edit") { editing = true }
        }
        .sheet(isPresented: $editing) { TabataEditorView(workout: workout) }
        .fullScreenCover(isPresented: $running) {
            TabataRunView(workout: workout) { _ in running = false }
        }
    }
}

struct RepWorkoutDetailView: View {
    @Bindable var workout: RepWorkout
    @AppStorage("workout.weightUnit") private var weightUnit = "kg"
    @State private var running = false
    @State private var editing = false

    var body: some View {
        List {
            if workout.restBetweenSetsSeconds > 0 {
                LabeledContent("Rest between sets", value: WorkoutFormat.clock(workout.restBetweenSetsSeconds))
            }
            ForEach(Array(workout.sets.enumerated()), id: \.element.id) { i, set in
                SwiftUI.Section(set.repeats > 1 ? "Set \(i + 1) (× \(set.repeats))" : "Set \(i + 1)") {
                    ForEach(set.exercises) { ex in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                WorkoutPictureThumb(imageID: ex.imageID)
                                Text(ex.name)
                                Spacer()
                                Text([ "\(ex.reps) reps", WorkoutFormat.weight(ex.weight, unit: weightUnit) ]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .foregroundStyle(.secondary)
                            }
                            if !ex.note.isEmpty {
                                Text(ex.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .safeAreaInset(edge: .bottom) {
            StartButton { running = true }
        }
        .toolbar {
            Button("Edit") { editing = true }
        }
        .sheet(isPresented: $editing) { RepWorkoutEditorView(workout: workout) }
        .fullScreenCover(isPresented: $running) {
            RepRunView(workout: workout) { _ in running = false }
        }
    }
}

private struct StartButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Start", systemImage: "play.fill")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .background(.bar)
    }
}

struct WorkoutSessionDetailView: View {
    let session: WorkoutSession
    @AppStorage("workout.weightUnit") private var weightUnit = "kg"

    var body: some View {
        List {
            LabeledContent("Date", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Duration", value: WorkoutFormat.clock(session.durationSeconds))
            LabeledContent("Result", value: session.completed ? "Completed" : "Stopped early")
            if session.kind == .reps, !session.log.isEmpty {
                RepLogSummary(log: session.log, unit: weightUnit)
                    .padding(.vertical, 4)
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Settings

struct WorkoutSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("workout.voiceOn") private var voiceOn = true
    @AppStorage("workout.beepsOn") private var beepsOn = true
    @AppStorage("workout.weightUnit") private var weightUnit = "kg"

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Voice cues", isOn: $voiceOn)
                Toggle("3-2-1 beeps", isOn: $beepsOn)
                Picker("Weight unit", selection: $weightUnit) {
                    Text("kg").tag("kg")
                    Text("lb").tag("lb")
                }
            }
            .navigationTitle("Workout settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
