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
    
    private var filteredSubtasks: [Subtask] {
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
                ForEach(filteredSubtasks) { subtask in
                    SubtaskRow(subtask: subtask)
                }
                .onDelete(perform: deleteSubtasks)
            }
            .navigationTitle(parentTask?.title ?? parentSubtask?.name ?? "Subtasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
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
                    parentSubtask: parentSubtask
                )
            }
        }
    }
    
    private func deleteSubtasks(at offsets: IndexSet) {
        for index in offsets {
            let subtask = filteredSubtasks[index]
            deleteSubtaskAndChildren(subtask)
        }
    }
    
    private func deleteSubtaskAndChildren(_ subtask: Subtask) {
        // Delete all child subtasks recursively (cascade will handle this automatically)
        modelContext.delete(subtask)
    }
}

struct SubtaskRow: View {
    @Bindable var subtask: Subtask
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
            parentSubtask: parentSubtask
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
