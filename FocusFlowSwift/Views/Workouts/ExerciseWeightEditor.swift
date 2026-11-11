import SwiftUI
import SwiftData

/// Which exercise in a rep workout is having its weight changed.
struct WeightEditTarget: Identifiable {
    let setIndex: Int
    let exercise: RepExercise
    var id: UUID { exercise.id }
}

/// Quick weight change for one exercise, from the workout's detail screen.
struct ExerciseWeightEditor: View {
    let workout: RepWorkout
    let target: WeightEditTarget

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("workout.weightUnit") private var weightUnit = "lb"

    @State private var text: String
    @State private var applyToAll = false

    init(workout: RepWorkout, target: WeightEditTarget) {
        self.workout = workout
        self.target = target
        _text = State(initialValue: target.exercise.weight.map(Self.format) ?? "")
    }

    private var value: Double? {
        let v = Double(text.replacingOccurrences(of: ",", with: "."))
        return (v ?? 0) > 0 ? v : nil
    }

    private var isValid: Bool { text.trimmed.isEmpty || value != nil }

    /// How many times this exercise appears in the workout (by name).
    private var sameNameCount: Int {
        workout.sets.flatMap(\.exercises).filter { Self.sameName($0.name, target.exercise.name) }.count
    }

    private var step: Double { weightUnit == "kg" ? 2.5 : 5 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("No weight", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.title2.monospacedDigit())
                        Text(weightUnit).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Button("−\(Self.format(step))") { bump(-step) }
                        Button("+\(Self.format(step))") { bump(step) }
                        Spacer()
                        Button("No weight", role: .destructive) { text = "" }
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text(target.exercise.name)
                } footer: {
                    Text("Set \(target.setIndex + 1) · \(target.exercise.amountText)")
                }

                if sameNameCount > 1 {
                    Section {
                        Toggle("Change all \(sameNameCount) \"\(target.exercise.name)\"", isOn: $applyToAll)
                    } footer: {
                        Text("Off: only this one in set \(target.setIndex + 1).")
                    }
                }
            }
            .navigationTitle("Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func bump(_ by: Double) {
        let next = max(0, (value ?? 0) + by)
        text = next > 0 ? Self.format(next) : ""
    }

    private func save() {
        var sets = workout.sets
        for s in sets.indices {
            for e in sets[s].exercises.indices {
                let ex = sets[s].exercises[e]
                let match = applyToAll ? Self.sameName(ex.name, target.exercise.name) : ex.id == target.exercise.id
                if match { sets[s].exercises[e].weight = value }
            }
        }
        workout.sets = sets
        try? modelContext.save()
        dismiss()
    }

    private static func sameName(_ a: String, _ b: String) -> Bool {
        a.trimmed.caseInsensitiveCompare(b.trimmed) == .orderedSame
    }

    private static func format(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}
