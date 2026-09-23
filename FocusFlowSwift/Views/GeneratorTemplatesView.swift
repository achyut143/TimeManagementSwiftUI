import SwiftUI
import SwiftData

// MARK: - Templates List

/// Lets the user pick (or manage) a saved Interval/Task preset for the
/// Schedule Generator. Selecting a template calls `onApply` with its
/// intervals and tasks strings so the caller can populate its text fields.
struct GeneratorTemplatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GeneratorTemplate.updatedAt, order: .reverse) private var templates: [GeneratorTemplate]

    /// Called with (intervals, tasks) when the user applies a template.
    var onApply: (String, String) -> Void

    @State private var searchText: String = ""
    @State private var editingTemplate: GeneratorTemplate? = nil
    @State private var showNewTemplate = false
    @State private var deletePending: GeneratorTemplate? = nil
    @State private var showDeleteConfirm = false

    private var filtered: [GeneratorTemplate] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty { return templates }
        return templates.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationView {
            Group {
                if templates.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Generator Templates")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search templates")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showNewTemplate = true } label: {
                            Image(systemName: "plus")
                        }
                        Button("Done") { dismiss() }
                    }
                }
            }
            .sheet(item: $editingTemplate) { template in
                GeneratorTemplateEditorView(template: template)
            }
            .sheet(isPresented: $showNewTemplate) {
                NewGeneratorTemplateView()
            }
            .confirmationDialog(
                "Delete \"\(deletePending?.name ?? "")\"?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let t = deletePending {
                        modelContext.delete(t)
                        try? modelContext.save()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: Sub-views

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.system(size: 52))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No Templates Yet")
                .font(.title3).fontWeight(.semibold)
            Text("Save a set of intervals and tasks to reuse in the Schedule Generator.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("New Template") { showNewTemplate = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            if filtered.isEmpty {
                Text("No templates match \"\(searchText)\"")
                    .font(.subheadline).foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filtered) { template in
                    GeneratorTemplateRowView(
                        template: template,
                        onApply: {
                            onApply(template.intervals, template.tasks)
                            dismiss()
                        },
                        onEdit: { editingTemplate = template },
                        onDelete: {
                            deletePending = template
                            showDeleteConfirm = true
                        }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Single Template Row

private struct GeneratorTemplateRowView: View {
    let template: GeneratorTemplate
    var onApply: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.subheadline).fontWeight(.semibold)
                Text("Interval: \(template.intervals)")
                    .font(.caption).foregroundColor(.secondary)
                Text("Task: \(template.tasks)")
                    .font(.caption).foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Button(action: onApply) {
                    Label("Apply", systemImage: "arrow.down.doc.fill")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.indigo))
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption).foregroundColor(.indigo)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.indigo.opacity(0.1)))
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption).foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onApply() }
    }
}

// MARK: - Shared Editor Fields

private struct GeneratorTemplateFields: View {
    @Binding var name: String
    @Binding var intervals: String
    @Binding var tasks: String

    var body: some View {
        Section("Template Name") {
            TextField("e.g. Deep Work Block", text: $name)
        }

        Section("Intervals (minutes, comma-separated)") {
            TextField("1,2,3,4,5,6", text: $intervals)
                .keyboardType(.numbersAndPunctuation)
        }

        Section("Tasks (comma-separated)") {
            TextField("work,eat,rest", text: $tasks)
        }

        let intervalCount = intervals.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.count
        let taskCount = tasks.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.count
        if intervalCount != taskCount {
            Section {
                Text("Interval count (\(intervalCount)) and task count (\(taskCount)) don't match. The generator cycles through both lists, so mismatched counts may produce unexpected pairings.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Template Editor

struct GeneratorTemplateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var template: GeneratorTemplate

    @State private var name: String = ""
    @State private var intervals: String = ""
    @State private var tasks: String = ""
    @State private var saveError: String? = nil

    var body: some View {
        NavigationView {
            Form {
                GeneratorTemplateFields(name: $name, intervals: $intervals, tasks: $tasks)

                if let error = saveError {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                name = template.name
                intervals = template.intervals
                tasks = template.tasks
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            saveError = "Template name cannot be empty."
            return
        }
        guard !intervals.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !tasks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            saveError = "Intervals and tasks cannot be empty."
            return
        }
        template.update(name: trimmedName, intervals: intervals, tasks: tasks)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - New Template Sheet

struct NewGeneratorTemplateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var intervals: String = ""
    @State private var tasks: String = ""
    @State private var saveError: String? = nil

    var body: some View {
        NavigationView {
            Form {
                GeneratorTemplateFields(name: $name, intervals: $intervals, tasks: $tasks)

                if let error = saveError {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            saveError = "Please enter a name."
            return
        }
        guard !intervals.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !tasks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            saveError = "Intervals and tasks cannot be empty."
            return
        }
        let template = GeneratorTemplate(name: trimmedName, intervals: intervals, tasks: tasks)
        modelContext.insert(template)
        try? modelContext.save()
        dismiss()
    }
}
