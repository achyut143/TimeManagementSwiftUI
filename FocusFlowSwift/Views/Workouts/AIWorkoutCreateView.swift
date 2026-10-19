import SwiftUI

/// Paste a workout description; AI builds it and opens the editor pre-filled
/// so it can be checked before saving.
struct AIWorkoutCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("workout.weightUnit") private var weightUnit = "kg"

    @State private var text = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var result: WorkoutAIService.Result?

    var body: some View {
        switch result {
        case .tabata(let draft):
            // The editor's Save/Cancel close this whole sheet.
            TabataEditorView(workout: nil, prefill: draft)
        case .reps(let name, let sets, let rest):
            RepWorkoutEditorView(workout: nil, prefill: (name, sets, rest))
        case nil:
            input
        }
    }

    private var input: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(placeholder)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Workout description")
                } footer: {
                    Text("Paste or type a Tabata or rep workout. AI fills in the form; you can check and change it before saving.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Create with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Create", action: create)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Paste", systemImage: "doc.on.clipboard") {
                        if let pasted = UIPasteboard.general.string { text = pasted }
                    }
                }
            }
            .disabled(isWorking)
        }
    }

    private var placeholder: String {
        """
        e.g. Insanity warm up 1: 10s prepare, 40s work, no rest, 3 rounds with 30s between. Jog, jumping jacks, heismans, 1-2-3, butt kicks, high knees, mummy kicks.

        or: Upper body A. Set 1 × 3: bench press 10 reps 40 kg, bent-over row 10 reps 30 kg. Set 2 × 2: shoulder press 12 × 15 kg, bicep curl 12 × 10 kg.
        """
    }

    private func create() {
        errorMessage = nil
        isWorking = true
        let description = text
        let unit = weightUnit
        // `Task` is the app's task model here, so use the concurrency one by its full name.
        _Concurrency.Task {
            do {
                let built = try await WorkoutAIService().createWorkout(from: description, weightUnit: unit)
                await MainActor.run {
                    isWorking = false
                    result = built
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
