import SwiftUI
import SwiftData

// Manual + AI-assisted editor for a task's virtues (character strengths this
// task exercises, e.g. "Self-Discipline", "Patience"). Opened from Task
// Actions → Virtues. Feeds VirtueHabitTrendsView's "Virtues" timeline.
struct TaskVirtuesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let task: Task

    @State private var virtues: [String] = []
    @State private var newVirtueText: String = ""
    @State private var isGenerating = false
    @State private var generationError: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Task") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.headline)
                        if let info = task.info, !info.isEmpty {
                            Text(info)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if !task.taskDescription.isEmpty {
                            Text(task.taskDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Virtues") {
                    if virtues.isEmpty {
                        Text("No virtues added yet")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(virtues, id: \.self) { virtue in
                            HStack {
                                Text(virtue)
                                Spacer()
                                Button {
                                    removeVirtue(virtue)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Add Manually") {
                    HStack {
                        TextField("e.g. Self-Discipline", text: $newVirtueText)
                            .onSubmit { addManualVirtue() }
                        Button("Add") { addManualVirtue() }
                            .disabled(newVirtueText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    Button {
                        generateMore()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(virtues.isEmpty ? "Generate 4 Virtues with AI" : "4 More with AI")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isGenerating)

                    if let generationError {
                        Text(generationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Suggestions are generated from this task's title and Info (set it via Edit), and won't repeat virtues already added.")
                }
            }
            .navigationTitle("Virtues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                virtues = task.virtues
            }
        }
    }

    private func addManualVirtue() {
        let trimmed = newVirtueText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !virtues.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newVirtueText = ""
            return
        }
        virtues.append(trimmed)
        newVirtueText = ""
    }

    private func removeVirtue(_ virtue: String) {
        virtues.removeAll { $0 == virtue }
    }

    private func generateMore() {
        isGenerating = true
        generationError = nil

        let service = VirtueSuggestionService()
        let title = task.title
        let existing = virtues

        // Prefer the free-text Info field; fall back to tags (taskDescription)
        // as weaker context if Info hasn't been set.
        var contextParts: [String] = []
        if let info = task.info, !info.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contextParts.append("Info: \(info)")
        }
        if !task.taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contextParts.append("Tags: \(task.taskDescription)")
        }
        let context = contextParts.joined(separator: "\n")

        _Concurrency.Task {
            do {
                let suggestions = try await service.suggestVirtues(itemTitle: title, itemLabel: "Task", context: context, existing: existing, count: 4)
                await MainActor.run {
                    virtues.append(contentsOf: suggestions)
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
        task.virtues = virtues
        try? modelContext.save()
        dismiss()
    }
}
