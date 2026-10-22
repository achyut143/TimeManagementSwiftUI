import SwiftUI
import SwiftData

/// A saved workout to run full screen.
enum WorkoutRunTarget: Identifiable {
    case tabata(TabataWorkout)
    case reps(RepWorkout)

    var id: UUID {
        switch self {
        case .tabata(let w): return w.id
        case .reps(let w): return w.id
        }
    }
}

/// Weekdays in display order, Monday first (Calendar numbering: 1 = Sunday).
enum WeekPlanDays {
    static let order = [2, 3, 4, 5, 6, 7, 1]

    static func name(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[(weekday - 1) % 7]
    }

    static var today: Int { Calendar.current.component(.weekday, from: Date()) }
}

/// "Today" strip at the top of the Workouts screen: today's planned
/// workouts with a Start button, or a prompt to plan the week.
struct WorkoutTodayCard: View {
    @Query(sort: \WorkoutPlanEntry.order) private var entries: [WorkoutPlanEntry]
    let tabatas: [TabataWorkout]
    let repWorkouts: [RepWorkout]
    let sessions: [WorkoutSession]
    let onStart: (WorkoutRunTarget) -> Void
    let onPlanWeek: () -> Void

    private var todaysTargets: [WorkoutRunTarget] {
        entries.filter { $0.weekday == WeekPlanDays.today }.compactMap(resolve)
    }

    private func resolve(_ entry: WorkoutPlanEntry) -> WorkoutRunTarget? {
        switch entry.kind {
        case .tabata: return tabatas.first { $0.id == entry.workoutID }.map(WorkoutRunTarget.tabata)
        case .reps: return repWorkouts.first { $0.id == entry.workoutID }.map(WorkoutRunTarget.reps)
        }
    }

    /// Completed today already.
    private func isDone(_ id: UUID) -> Bool {
        let start = Calendar.current.startOfDay(for: Date())
        return sessions.contains { $0.workoutID == id && $0.completed && $0.startedAt >= start }
    }

    var body: some View {
        if entries.isEmpty {
            Button(action: onPlanWeek) {
                Label("Plan your week: pick a workout for each day", systemImage: "calendar.badge.plus")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today · \(WeekPlanDays.name(WeekPlanDays.today))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if todaysTargets.isEmpty {
                    Text("Rest day")
                        .font(.headline)
                } else {
                    ForEach(todaysTargets) { target in
                        row(target)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func row(_ target: WorkoutRunTarget) -> some View {
        let (name, summary, icon): (String, String, String) = {
            switch target {
            case .tabata(let w): return (w.name, w.summary, WorkoutKind.tabata.icon)
            case .reps(let w): return (w.name, w.summary, WorkoutKind.reps.icon)
            }
        }()
        let done = isDone(target.id)
        return HStack {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.headline).lineLimit(1)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if done {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button {
                    onStart(target)
                } label: {
                    Label(PausedRunStore.load(target.id) != nil ? "Resume" : "Start", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Pick workouts for each weekday.
struct WeekPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutPlanEntry.order) private var entries: [WorkoutPlanEntry]
    let tabatas: [TabataWorkout]
    let repWorkouts: [RepWorkout]

    var body: some View {
        NavigationStack {
            List {
                ForEach(WeekPlanDays.order, id: \.self) { day in
                    let dayEntries = entries.filter { $0.weekday == day }
                    Section {
                        if dayEntries.isEmpty {
                            Text("Rest day").foregroundStyle(.secondary)
                        }
                        ForEach(dayEntries) { entry in
                            HStack {
                                Image(systemName: entry.kind.icon).foregroundStyle(.secondary).frame(width: 24)
                                Text(name(of: entry))
                                    .foregroundStyle(exists(entry) ? .primary : .secondary)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { dayEntries[$0] }.forEach(modelContext.delete)
                            try? modelContext.save()
                        }
                        .onMove { from, to in
                            var list = dayEntries
                            list.move(fromOffsets: from, toOffset: to)
                            for (i, e) in list.enumerated() { e.order = i }
                            try? modelContext.save()
                        }
                        addMenu(day: day, count: dayEntries.count)
                    } header: {
                        HStack {
                            Text(WeekPlanDays.name(day))
                            if day == WeekPlanDays.today {
                                Text("Today").font(.caption2.bold()).foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Week plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func addMenu(day: Int, count: Int) -> some View {
        Menu {
            if !repWorkouts.isEmpty {
                Section("Rep workouts") {
                    ForEach(repWorkouts) { w in
                        Button(w.name) { add(day: day, kind: .reps, id: w.id, order: count) }
                    }
                }
            }
            if !tabatas.isEmpty {
                Section("Tabatas") {
                    ForEach(tabatas) { w in
                        Button(w.name) { add(day: day, kind: .tabata, id: w.id, order: count) }
                    }
                }
            }
        } label: {
            Label("Add workout", systemImage: "plus")
        }
        .disabled(repWorkouts.isEmpty && tabatas.isEmpty)
    }

    private func add(day: Int, kind: WorkoutKind, id: UUID, order: Int) {
        modelContext.insert(WorkoutPlanEntry(weekday: day, kind: kind, workoutID: id, order: order))
        try? modelContext.save()
    }

    private func exists(_ entry: WorkoutPlanEntry) -> Bool {
        entry.kind == .tabata ? tabatas.contains { $0.id == entry.workoutID } : repWorkouts.contains { $0.id == entry.workoutID }
    }

    private func name(of entry: WorkoutPlanEntry) -> String {
        switch entry.kind {
        case .tabata: return tabatas.first { $0.id == entry.workoutID }?.name ?? "Deleted workout"
        case .reps: return repWorkouts.first { $0.id == entry.workoutID }?.name ?? "Deleted workout"
        }
    }
}
