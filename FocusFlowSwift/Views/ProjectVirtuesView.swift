import SwiftUI
import SwiftData

// Manual + AI-assisted editor for a project's virtues (character strengths
// this project exercises, e.g. "Discipline", "Patience"). Mirrors
// TaskVirtuesView. Feeds ProjectTrendsView's "Virtues" timeline (time logged
// to the project, attributed to each of its virtues).
struct ProjectVirtuesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let project: Project

    @State private var virtues: [String] = []
    @State private var newVirtueText: String = ""
    @State private var isGenerating = false
    @State private var generationError: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Project") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.headline)
                        if !project.projectDescription.isEmpty {
                            Text(project.projectDescription)
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
                        TextField("e.g. Discipline", text: $newVirtueText)
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
                    Text("Suggestions are generated from this project's name and description, and won't repeat virtues already added.")
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
                virtues = project.virtues
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
        let title = project.name
        let context = project.projectDescription
        let existing = virtues

        _Concurrency.Task {
            do {
                let suggestions = try await service.suggestVirtues(itemTitle: title, itemLabel: "Project", context: context, existing: existing, count: 4)
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
        project.virtues = virtues
        try? modelContext.save()
        dismiss()
    }
}
