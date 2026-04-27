import SwiftUI
import SwiftData

// MARK: - Templates List

struct ScheduleTemplatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ScheduleTemplate.updatedAt, order: .reverse) private var templates: [ScheduleTemplate]

    /// Called when the user applies one or more templates.
    var onApply: ([ScheduleTemplate]) -> Void

    @State private var searchText: String = ""
    @State private var selectedNames: [String] = []
    @State private var editingTemplate: ScheduleTemplate? = nil
    @State private var showNewTemplate = false
    @State private var deletePending: ScheduleTemplate? = nil
    @State private var showDeleteConfirm = false

    private var filtered: [ScheduleTemplate] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty { return templates }
        return templates.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedTemplates: [ScheduleTemplate] {
        // Preserve tap order
        selectedNames.compactMap { name in templates.first { $0.name == name } }
    }

    var body: some View {
        NavigationView {
            Group {
                if templates.isEmpty {
                    emptyState
                } else {
                    ZStack(alignment: .bottom) {
                        list
                        if !selectedNames.isEmpty {
                            applyBar
                        }
                    }
                }
            }
            .navigationTitle("Schedule Templates")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search templates")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !selectedNames.isEmpty {
                        Button("Clear") { selectedNames.removeAll() }
                            .foregroundColor(.secondary)
                    }
                }
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
                TemplateEditorView(template: template)
            }
            .sheet(isPresented: $showNewTemplate) {
                NewTemplateView()
            }
            .confirmationDialog(
                "Delete \"\(deletePending?.name ?? "")\"?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let t = deletePending {
                        selectedNames.removeAll { $0 == t.name }
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
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 52))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No Templates Yet")
                .font(.title3).fontWeight(.semibold)
            Text("Save your current schedule as a template from the Daily Notes section.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
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
                    TemplateRowView(
                        template: template,
                        selectionIndex: selectedNames.firstIndex(of: template.name).map { $0 + 1 },
                        onToggleSelect: { toggle(template) },
                        onApply: {
                            onApply([template])
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
        // Extra bottom padding so the apply bar doesn't cover last row
        .safeAreaInset(edge: .bottom) {
            if !selectedNames.isEmpty { Color.clear.frame(height: 80) }
        }
    }

    private var applyBar: some View {
        Button {
            onApply(selectedTemplates)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                Text("Apply \(selectedNames.count) Template\(selectedNames.count == 1 ? "" : "s")")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.indigo)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: selectedNames.count == 0)
    }

    private func toggle(_ template: ScheduleTemplate) {
        if let idx = selectedNames.firstIndex(of: template.name) {
            selectedNames.remove(at: idx)
        } else {
            selectedNames.append(template.name)
        }
    }
}

// MARK: - Single Template Row

private struct TemplateRowView: View {
    let template: ScheduleTemplate
    /// 1-based selection order, nil if not selected
    let selectionIndex: Int?
    var onToggleSelect: () -> Void
    var onApply: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var isSelected: Bool { selectionIndex != nil }

    @State private var isExpanded = false

    private var previewLines: [String] {
        template.content
            .components(separatedBy: .newlines)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return !t.isEmpty && t != "START" && t != "END"
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 10) {
                // Selection order badge
                Button(action: onToggleSelect) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.indigo : Color.clear)
                            .overlay(Circle().stroke(isSelected ? Color.indigo : Color.secondary.opacity(0.4), lineWidth: 1.5))
                            .frame(width: 26, height: 26)
                        if let idx = selectionIndex {
                            Text("\(idx)")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if template.isReward { Text("🎁").font(.caption) }
                        Text(template.name)
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    Text("\(previewLines.count) task\(previewLines.count == 1 ? "" : "s") · saved \(template.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundColor(.secondary)
                }

                Spacer()

                // Chevron expand/collapse
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Preview lines when expanded
            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(previewLines.prefix(8).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    if previewLines.count > 8 {
                        Text("+ \(previewLines.count - 8) more…")
                            .font(.caption2).foregroundColor(.secondary.opacity(0.6))
                    }
                }
                .padding(.leading, 34)
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Action buttons
            HStack(spacing: 8) {
                Button(action: onApply) {
                    Label("Apply Only This", systemImage: "arrow.down.doc.fill")
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
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onToggleSelect() }
    }
}

// MARK: - Template Editor

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var template: ScheduleTemplate

    @State private var name: String = ""
    @State private var content: String = ""
    @State private var isReward: Bool = false
    @State private var saveError: String? = nil

    var body: some View {
        NavigationView {
            Form {
                Section("Template Name") {
                    TextField("e.g. Morning Routine", text: $name)
                }

                Section {
                    Toggle(isOn: $isReward) {
                        Label("Reward Template", systemImage: "gift.fill")
                            .foregroundColor(isReward ? Color(hue: 0.12, saturation: 0.9, brightness: 0.85) : .primary)
                    }
                    .tint(Color(hue: 0.12, saturation: 0.9, brightness: 0.85))
                    if isReward {
                        Text("All tasks in this template will be marked as rewards (🎁) when applied.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("Schedule Content") {
                    Text("Edit the raw schedule text below. Keep the START and END markers.")
                        .font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $content)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 300)
                }

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
                content = template.content
                isReward = template.isReward
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            saveError = "Template name cannot be empty."
            return
        }
        let hasStart = content.components(separatedBy: .newlines)
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "START" }
        let hasEnd = content.components(separatedBy: .newlines)
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "END" }
        guard hasStart && hasEnd else {
            saveError = "Content must contain START and END markers."
            return
        }
        template.update(name: trimmedName, content: content, isReward: isReward)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Save-as-Template Sheet

struct SaveTemplateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let scheduleContent: String
    @State private var name: String = ""
    @State private var saveError: String? = nil

    var body: some View {
        NavigationView {
            Form {
                Section("Template Name") {
                    TextField("e.g. Morning Routine", text: $name)
                        .submitLabel(.done)
                        .onSubmit { save() }
                }

                Section {
                    Text("The schedule block (START…END) from your current notes will be saved.")
                        .font(.caption).foregroundColor(.secondary)
                }

                if let error = saveError {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Save as Template")
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
        let template = ScheduleTemplate(name: trimmedName, content: scheduleContent)
        modelContext.insert(template)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - New Template Sheet

struct NewTemplateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var content: String = "START\n\nEND"
    @State private var isReward: Bool = false
    @State private var saveError: String? = nil

    var body: some View {
        NavigationView {
            Form {
                Section("Template Name") {
                    TextField("e.g. Morning Routine", text: $name)
                }

                Section {
                    Toggle(isOn: $isReward) {
                        Label("Reward Template", systemImage: "gift.fill")
                            .foregroundColor(isReward ? Color(hue: 0.12, saturation: 0.9, brightness: 0.85) : .primary)
                    }
                    .tint(Color(hue: 0.12, saturation: 0.9, brightness: 0.85))
                    if isReward {
                        Text("All tasks in this template will be marked as rewards (🎁) when applied.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("Schedule Content") {
                    Text("Write your schedule between the START and END markers.")
                        .font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $content)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 300)
                }

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
        let hasStart = content.components(separatedBy: .newlines)
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "START" }
        let hasEnd = content.components(separatedBy: .newlines)
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "END" }
        guard hasStart && hasEnd else {
            saveError = "Content must contain START and END markers."
            return
        }
        let template = ScheduleTemplate(name: trimmedName, content: content, isReward: isReward)
        modelContext.insert(template)
        try? modelContext.save()
        dismiss()
    }
}
