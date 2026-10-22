import SwiftUI
import SwiftData

/// Creates or edits a rep workout. Pass `workout: nil` to create a new one.
struct RepWorkoutEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("workout.weightUnit") private var weightUnit = "lb"

    let workout: RepWorkout?
    /// Called after a successful save.
    var onSaved: (() -> Void)? = nil
    @State private var name: String
    @State private var sets: [RepSet]
    @State private var restSeconds: Int
    @State private var editMode: EditMode = .inactive
    @State private var showReorderSets = false

    /// `prefill` starts a new workout from given values (e.g. built by AI).
    init(workout: RepWorkout?, prefill: (name: String, sets: [RepSet], restSeconds: Int)? = nil, onSaved: (() -> Void)? = nil) {
        self.workout = workout
        self.onSaved = onSaved
        _name = State(initialValue: workout?.name ?? prefill?.name ?? "")
        _sets = State(initialValue: workout?.sets ?? prefill?.sets ?? [RepSet(exercises: [RepExercise()])])
        _restSeconds = State(initialValue: workout?.restBetweenSetsSeconds ?? prefill?.restSeconds ?? 0)

    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name, e.g. Upper body A", text: $name)
                    WorkoutDurationRow(title: "Rest between sets", seconds: $restSeconds, zeroLabel: "None")
                } footer: {
                    Text("Rest runs after each round of a set. You can always skip it.")
                }

                ForEach($sets) { $set in
                    let setNumber = (sets.firstIndex(where: { $0.id == set.id }) ?? 0) + 1
                    Section {
                        Stepper("Repeat × \(set.repeats)", value: $set.repeats, in: 1...20)
                        ForEach($set.exercises) { $exercise in
                            ExerciseEditorRow(exercise: $exercise, unit: weightUnit)
                        }
                        .onMove { set.exercises.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { set.exercises.remove(atOffsets: $0) }
                        Button {
                            set.exercises.append(RepExercise())
                        } label: {
                            Label("Add exercise", systemImage: "plus")
                        }
                    } header: {
                        HStack {
                            Text("Set \(setNumber)")
                            Spacer()
                            Menu {
                                Button("Duplicate set", systemImage: "plus.square.on.square") { duplicate(set) }
                                Button("Delete set", systemImage: "trash", role: .destructive) {
                                    sets.removeAll { $0.id == set.id }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }

                Section {
                    Button {
                        sets.append(RepSet(exercises: [RepExercise()]))
                    } label: {
                        Label("Add set", systemImage: "plus.rectangle.on.rectangle")
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(workout == nil ? "New rep workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        WorkoutPictureStore.removeUnused(context: modelContext)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(editMode.isEditing ? "Done reordering" : "Reorder exercises") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    Spacer()
                    Button("Reorder sets") { showReorderSets = true }
                        .disabled(sets.count < 2)
                }
            }
            .sheet(isPresented: $showReorderSets) {
                ReorderSetsSheet(sets: $sets)
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        sets.contains { set in set.exercises.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    private func duplicate(_ set: RepSet) {
        guard let i = sets.firstIndex(where: { $0.id == set.id }) else { return }
        var copy = set
        copy.id = UUID()
        copy.exercises = set.exercises.map { var e = $0; e.id = UUID(); return e }
        sets.insert(copy, at: i + 1)
    }

    private func save() {
        // Drop unnamed exercises and empty sets.
        let cleaned: [RepSet] = sets.compactMap { set in
            var s = set
            s.exercises = set.exercises
                .map { var e = $0; e.name = e.name.trimmingCharacters(in: .whitespaces); e.note = e.note.trimmingCharacters(in: .whitespaces); return e }
                .filter { !$0.name.isEmpty }
            return s.exercises.isEmpty ? nil : s
        }
        let target = workout ?? {
            let new = RepWorkout(name: name)
            modelContext.insert(new)
            return new
        }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.sets = cleaned
        target.restBetweenSetsSeconds = restSeconds
        try? modelContext.save()
        WorkoutPictureStore.removeUnused(context: modelContext)
        onSaved?()
        dismiss()
    }
}

private struct ExerciseEditorRow: View {
    @Binding var exercise: RepExercise
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Exercise, e.g. Bench press", text: $exercise.name)
                    .font(.body.weight(.medium))
                WorkoutPictureButton(imageID: $exercise.imageID)
            }
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    TextField("10", value: $exercise.reps, format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                    Text("reps").foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    TextField("Weight", text: weightText)
                        .keyboardType(.decimalPad)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                    Text(unit).foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            TextField("Note (optional)", text: $exercise.note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var weightText: Binding<String> {
        WeightText.binding($exercise.weight)
    }
}

/// Shows an optional weight as editable text ("" when empty).
enum WeightText {
    static func binding(_ value: Binding<Double?>) -> Binding<String> {
        Binding(
            get: {
                guard let v = value.wrappedValue else { return "" }
                return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
            },
            set: { text in
                let cleaned = text.replacingOccurrences(of: ",", with: ".")
                value.wrappedValue = cleaned.isEmpty ? nil : (Double(cleaned) ?? value.wrappedValue)
            }
        )
    }
}

private struct ReorderSetsSheet: View {
    @Binding var sets: [RepSet]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(sets) { set in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(set.exercises.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ").ifEmpty("No exercises"))
                            .lineLimit(1)
                        Text("× \(set.repeats) · \(set.exercises.count) exercises")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onMove { sets.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
