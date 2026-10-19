import SwiftUI
import SwiftData

/// Creates or edits a Tabata. Pass `workout: nil` to create a new one.
struct TabataEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let workout: TabataWorkout?
    @State private var draft: TabataDraft

    /// `prefill` starts a new Tabata from given values (e.g. built by AI).
    init(workout: TabataWorkout?, prefill: TabataDraft? = nil) {
        self.workout = workout
        var d = workout?.draft ?? prefill ?? TabataDraft()
        if d.cycleNames.count < d.cycles {
            d.cycleNames += Array(repeating: "", count: d.cycles - d.cycleNames.count)
        }
        if d.cycleImageIDs.count < d.cycles {
            d.cycleImageIDs += Array(repeating: "", count: d.cycles - d.cycleImageIDs.count)
        }
        _draft = State(initialValue: d)

    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Insanity warm up 1", text: $draft.name)
                }

                Section("Timing") {
                    WorkoutDurationRow(title: "Prepare", seconds: $draft.prepareSeconds)
                    WorkoutDurationRow(title: "Work", seconds: $draft.workSeconds, minimum: 5)
                    WorkoutDurationRow(title: "Rest", seconds: $draft.restSeconds, zeroLabel: "No rest")
                    Stepper("Cycles: \(draft.cycles)", value: $draft.cycles, in: 1...50)
                    Stepper("Tabatas (rounds): \(draft.rounds)", value: $draft.rounds, in: 1...20)
                    if draft.rounds > 1 {
                        WorkoutDurationRow(title: "Rest between rounds", seconds: $draft.restBetweenRoundsSeconds, zeroLabel: "None")
                    }
                }

                Section {
                    ForEach(0..<draft.cycles, id: \.self) { i in
                        HStack {
                            Text("\(i + 1)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 26, alignment: .leading)
                            TextField("Work", text: cycleName(i))
                            WorkoutPictureButton(imageID: cycleImage(i))
                        }
                    }
                } header: {
                    Text("Cycle names")
                } footer: {
                    Text("Optional. A blank cycle is called \"Work\". Tap the photo box to add a picture shown during that cycle; long-press it to remove.")
                }

                Section {
                    LabeledContent("Total workout time", value: WorkoutFormat.clock(draft.workoutSeconds))
                    LabeledContent("With prepare", value: WorkoutFormat.clock(draft.totalSeconds))
                    LabeledContent("Work intervals", value: "\(draft.cycles * draft.rounds)")
                }
            }
            .navigationTitle(workout == nil ? "New Tabata" : "Edit Tabata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        WorkoutPictureStore.removeUnused(context: modelContext)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: draft.cycles) { _, newValue in
                // One name box per cycle; keep names already typed.
                if draft.cycleNames.count < newValue {
                    draft.cycleNames += Array(repeating: "", count: newValue - draft.cycleNames.count)
                }
                if draft.cycleImageIDs.count < newValue {
                    draft.cycleImageIDs += Array(repeating: "", count: newValue - draft.cycleImageIDs.count)
                }
            }
        }
    }

    private func cycleName(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < draft.cycleNames.count ? draft.cycleNames[i] : "" },
            set: { value in
                if i < draft.cycleNames.count { draft.cycleNames[i] = value }
            }
        )
    }

    private func cycleImage(_ i: Int) -> Binding<UUID?> {
        Binding(
            get: { draft.imageID(cycle: i) },
            set: { id in
                if i < draft.cycleImageIDs.count { draft.cycleImageIDs[i] = id?.uuidString ?? "" }
            }
        )
    }

    private func save() {
        let target = workout ?? {
            let new = TabataWorkout(name: draft.name)
            modelContext.insert(new)
            return new
        }()
        target.apply(draft)
        try? modelContext.save()
        WorkoutPictureStore.removeUnused(context: modelContext)
        dismiss()
    }
}

/// A "0:40"-style duration with a stepper (5-second steps).
struct WorkoutDurationRow: View {
    let title: String
    @Binding var seconds: Int
    var minimum = 0
    var zeroLabel: String? = nil

    var body: some View {
        Stepper(value: $seconds, in: minimum...3600, step: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(seconds == 0 && zeroLabel != nil ? zeroLabel! : WorkoutFormat.clock(seconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
