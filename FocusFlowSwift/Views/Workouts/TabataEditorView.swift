import SwiftUI
import SwiftData

/// Creates or edits a Tabata. Pass `workout: nil` to create a new one.
/// A Tabata has one or more parts (e.g. warm up, circuit 1, circuit 2),
/// each with its own timing and exercises, run back to back.
struct TabataEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TabataWorkout.createdAt, order: .reverse) private var savedTabatas: [TabataWorkout]

    let workout: TabataWorkout?
    /// Called after a successful save.
    var onSaved: (() -> Void)? = nil
    @State private var draft: TabataDraft

    /// `prefill` starts a new Tabata from given values (e.g. built by AI).
    init(workout: TabataWorkout?, prefill: TabataDraft? = nil, onSaved: (() -> Void)? = nil) {
        self.workout = workout
        self.onSaved = onSaved
        var d = workout?.draft ?? prefill ?? TabataDraft()
        if d.parts.isEmpty { d.parts = [TabataPart()] }
        d.parts = d.parts.map { $0.padded() }
        _draft = State(initialValue: d)
    }

    private var isMultiPart: Bool { draft.parts.count > 1 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Insanity warm up 1", text: $draft.name)
                }

                ForEach($draft.parts) { $part in
                    let index = draft.parts.firstIndex(where: { $0.id == part.id }) ?? 0
                    partSections(part: $part, index: index)
                }

                Section {
                    Button {
                        addBlankPart()
                    } label: {
                        Label("Add part", systemImage: "plus.rectangle.on.rectangle")
                    }
                    if !importableTabatas.isEmpty {
                        Menu {
                            ForEach(importableTabatas) { saved in
                                Button("\(saved.name) — \(saved.summary)") { importParts(from: saved) }
                            }
                        } label: {
                            Label("Add a saved Tabata as a part", systemImage: "square.stack.3d.down.right")
                        }
                    }
                } footer: {
                    Text("Parts run one after another, e.g. a warm up followed by circuits. Each part has its own timing, cycles and rounds; its prepare time works as the break before it.")
                }

                Section {
                    LabeledContent("Total workout time", value: WorkoutFormat.clock(draft.workoutSeconds))
                    LabeledContent("With prepare", value: WorkoutFormat.clock(draft.totalSeconds))
                    LabeledContent("Work intervals", value: "\(draft.workIntervalCount)")
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
        }
    }

    // MARK: Part sections

    @ViewBuilder
    private func partSections(part: Binding<TabataPart>, index: Int) -> some View {
        Section {
            if isMultiPart {
                TextField("Part name, e.g. Circuit 1", text: part.name)
            }
            WorkoutDurationRow(title: "Prepare", seconds: part.prepareSeconds)
            WorkoutDurationRow(title: "Work", seconds: part.workSeconds, minimum: 5)
            WorkoutDurationRow(title: "Rest", seconds: part.restSeconds, zeroLabel: "No rest")
            Stepper("Cycles: \(part.wrappedValue.cycles)", value: cycles(part), in: 1...50)
            Stepper("Tabatas (rounds): \(part.wrappedValue.rounds)", value: part.rounds, in: 1...20)
            if part.wrappedValue.rounds > 1 {
                WorkoutDurationRow(title: "Rest between rounds", seconds: part.restBetweenRoundsSeconds, zeroLabel: "None")
            }
        } header: {
            HStack {
                Text(isMultiPart ? "\(part.wrappedValue.title(index: index)) · timing" : "Timing")
                Spacer()
                if isMultiPart {
                    partMenu(index: index)
                }
            }
        }

        Section {
            ForEach(0..<part.wrappedValue.cycles, id: \.self) { i in
                HStack {
                    Text("\(i + 1)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .leading)
                    TextField("Work", text: cycleName(part, i))
                    WorkoutPictureButton(imageID: cycleImage(part, i))
                }
            }
        } header: {
            Text(isMultiPart ? "\(part.wrappedValue.title(index: index)) · cycle names" : "Cycle names")
        } footer: {
            if index == 0 {
                Text("Optional. A blank cycle is called \"Work\". Tap the photo box to add a picture shown during that cycle; long-press it to remove.")
            }
        }
    }

    private func partMenu(index: Int) -> some View {
        Menu {
            Button("Move up", systemImage: "arrow.up") { movePart(index, by: -1) }
                .disabled(index == 0)
            Button("Move down", systemImage: "arrow.down") { movePart(index, by: 1) }
                .disabled(index == draft.parts.count - 1)
            Button("Duplicate part", systemImage: "plus.square.on.square") { duplicatePart(index) }
            Button("Delete part", systemImage: "trash", role: .destructive) {
                draft.parts.remove(at: index)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .textCase(nil)
    }

    // MARK: Bindings

    /// Changing the cycle count keeps one name and picture slot per cycle.
    private func cycles(_ part: Binding<TabataPart>) -> Binding<Int> {
        Binding(
            get: { part.wrappedValue.cycles },
            set: { value in
                part.wrappedValue.cycles = value
                part.wrappedValue = part.wrappedValue.padded()
            }
        )
    }

    private func cycleName(_ part: Binding<TabataPart>, _ i: Int) -> Binding<String> {
        Binding(
            get: { i < part.wrappedValue.cycleNames.count ? part.wrappedValue.cycleNames[i] : "" },
            set: { value in
                if i < part.wrappedValue.cycleNames.count { part.wrappedValue.cycleNames[i] = value }
            }
        )
    }

    private func cycleImage(_ part: Binding<TabataPart>, _ i: Int) -> Binding<UUID?> {
        Binding(
            get: { part.wrappedValue.imageID(cycle: i) },
            set: { id in
                if i < part.wrappedValue.cycleImageIDs.count { part.wrappedValue.cycleImageIDs[i] = id?.uuidString ?? "" }
            }
        )
    }

    // MARK: Actions

    private var importableTabatas: [TabataWorkout] {
        savedTabatas.filter { $0.id != workout?.id }
    }

    private func addBlankPart() {
        let part = TabataPart(prepareSeconds: 10, workSeconds: 30, restSeconds: 0, cycles: 3, rounds: 1,
                              restBetweenRoundsSeconds: 0)
        draft.parts.append(part.padded())
    }

    /// Copies a saved Tabata's parts in, naming each after that Tabata when unnamed.
    private func importParts(from saved: TabataWorkout) {
        let source = saved.draft
        for (i, var part) in source.parts.enumerated() {
            part.id = UUID()
            if part.name.trimmingCharacters(in: .whitespaces).isEmpty {
                part.name = source.parts.count > 1 ? "\(saved.name) \(i + 1)" : saved.name
            }
            draft.parts.append(part.padded())
        }
    }

    private func movePart(_ index: Int, by offset: Int) {
        let target = index + offset
        guard draft.parts.indices.contains(target) else { return }
        draft.parts.swapAt(index, target)
    }

    private func duplicatePart(_ index: Int) {
        var copy = draft.parts[index]
        copy.id = UUID()
        draft.parts.insert(copy, at: index + 1)
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
        onSaved?()
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
