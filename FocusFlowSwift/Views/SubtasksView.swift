import SwiftUI
import SwiftData

struct SubtasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subtask.createdAt) private var allSubtasks: [Subtask]
    
    let parentTask: Task?
    let parentSubtask: Subtask?
    
    @State private var showingAddSubtask = false
    @State private var newSubtaskName = ""
    @State private var newSubtaskNotes = ""
    
    init(parentTask: Task? = nil, parentSubtask: Subtask? = nil) {
        self.parentTask = parentTask
        self.parentSubtask = parentSubtask
    }
    
    /// This level's subtasks in the user's order.
    private var filteredSubtasks: [Subtask] {
        SubtaskOrder.sorted(unsortedSubtasks)
    }

    private var unsortedSubtasks: [Subtask] {
        if let parentTask = parentTask {
            // Filter subtasks that belong to this task
            return allSubtasks.filter { 
                $0.parentTask?.persistentModelID == parentTask.persistentModelID && 
                $0.parentSubtask == nil 
            }
        } else if let parentSubtask = parentSubtask {
            // Filter subtasks that belong to this subtask
            return allSubtasks.filter { 
                $0.parentSubtask?.persistentModelID == parentSubtask.persistentModelID 
            }
        }
        return []
    }
    
    var body: some View {
        NavigationStack {
            List {
                let ordered = filteredSubtasks
                ForEach(Array(ordered.enumerated()), id: \.element.persistentModelID) { index, subtask in
                    SubtaskRow(subtask: subtask, number: index + 1)
                        .contextMenu {
                            Button {
                                shift(subtask, by: -1, in: ordered)
                            } label: { Label("Move Up", systemImage: "arrow.up") }
                            .disabled(index == 0)
                            Button {
                                shift(subtask, by: 1, in: ordered)
                            } label: { Label("Move Down", systemImage: "arrow.down") }
                            .disabled(index == ordered.count - 1)
                            Button {
                                shift(subtask, by: -index, in: ordered)
                            } label: { Label("Move to Top", systemImage: "arrow.up.to.line") }
                            .disabled(index == 0)
                            Button {
                                shift(subtask, by: ordered.count - 1 - index, in: ordered)
                            } label: { Label("Move to Bottom", systemImage: "arrow.down.to.line") }
                            .disabled(index == ordered.count - 1)
                        }
                }
                .onDelete(perform: deleteSubtasks)
                .onMove(perform: moveSubtasks)

                if ordered.count > 1 {
                    Text("Drag to reorder, or long-press a subtask to move it. Tap Edit for drag handles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(parentTask?.title ?? parentSubtask?.name ?? "Subtasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if filteredSubtasks.count > 1 {
                        EditButton()
                    }
                    Button {
                        showingAddSubtask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSubtask) {
                AddSubtaskView(
                    parentTask: parentTask,
                    parentSubtask: parentSubtask,
                    nextOrder: SubtaskOrder.nextOrder(after: unsortedSubtasks)
                )
            }
        }
    }
    
    private func deleteSubtasks(at offsets: IndexSet) {
        let ordered = filteredSubtasks
        for index in offsets {
            deleteSubtaskAndChildren(ordered[index])
        }
        SubtaskOrder.renumber(ordered.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
        try? modelContext.save()
    }

    private func moveSubtasks(from source: IndexSet, to destination: Int) {
        SubtaskOrder.move(filteredSubtasks, from: source, to: destination)
        try? modelContext.save()
    }

    private func shift(_ subtask: Subtask, by step: Int, in ordered: [Subtask]) {
        withAnimation { SubtaskOrder.shift(subtask, by: step, in: ordered) }
        try? modelContext.save()
    }
    
    private func deleteSubtaskAndChildren(_ subtask: Subtask) {
        // Delete all child subtasks recursively (cascade will handle this automatically)
        modelContext.delete(subtask)
    }
}

struct SubtaskRow: View {
    @Bindable var subtask: Subtask
    /// Position shown before the name (1, 2, 3…); nil hides it.
    var number: Int? = nil
    @State private var showingSubtasks = false
    @State private var showingEditNotes = false
    
    private var subtaskCount: Int {
        return subtask.childSubtasks?.count ?? 0
    }
    
    var body: some View {
        HStack {
            Button {
                subtask.completed.toggle()
            } label: {
                Image(systemName: subtask.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(subtask.completed ? .green : .gray)
            }
            .buttonStyle(.plain)

            if let number {
                Text("\(number).")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            
            Button {
                showingEditNotes = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subtask.name)
                        .strikethrough(subtask.completed)
                        .foregroundColor(.primary)
                    
                    if let notes = subtask.notes, !notes.isEmpty {
                        MarkdownText(text: notes)
                            .lineLimit(2)
                    } else {
                        Text("Add notes...")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            if subtaskCount > 0 {
                Button {
                    showingSubtasks = true
                } label: {
                    HStack(spacing: 4) {
                        Text("\(subtaskCount)")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingSubtasks) {
            SubtasksView(parentSubtask: subtask)
        }
        .sheet(isPresented: $showingEditNotes) {
            EditSubtaskNotesView(subtask: subtask)
        }
    }
}

struct AddSubtaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let parentTask: Task?
    let parentSubtask: Subtask?
    /// Where the new subtask goes: at the end of the list.
    var nextOrder: Int = 0
    
    @State private var name = ""
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Subtask Details") {
                    TextField("Name", text: $name)
                }
                
                Section("Notes (Optional)") {
                    RichTextEditor(text: $notes)
                        .frame(height: 200)
                }
            }
            .navigationTitle("New Subtask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addSubtask()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func addSubtask() {
        let subtask = Subtask(
            name: name,
            notes: notes.isEmpty ? nil : notes,
            parentTask: parentTask,
            parentSubtask: parentSubtask,
            sortOrder: nextOrder
        )
        modelContext.insert(subtask)
        
        // Explicitly save the context
        do {
            try modelContext.save()
        } catch {
            print("Error saving subtask: \(error)")
        }
        
        dismiss()
    }
}

struct EditSubtaskNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var subtask: Subtask
    @State private var notes: String = ""
    @State private var name: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Subtask Name") {
                    TextField("Name", text: $name)
                }
                
                Section("Notes") {
                    RichTextEditor(text: $notes)
                        .frame(height: 250)
                }
            }
            .navigationTitle("Edit Subtask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
            .onAppear {
                notes = subtask.notes ?? ""
                name = subtask.name
            }
        }
    }
    
    private func saveChanges() {
        subtask.name = name
        subtask.notes = notes.isEmpty ? nil : notes
        try? modelContext.save()
        dismiss()
    }
}
