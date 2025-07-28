import SwiftUI
import SwiftData

struct TaskTableView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @State private var searchText = ""
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var showOnlyWithNotes = false
    @State private var selectedTask: Task?
    @State private var showNotes = false
    @State private var taskToDelete: Task?
    @State private var showDeleteConfirmation = false
    
    var filteredTasks: [Task] {
        tasks.filter { task in
            guard let taskDate = task.date else { return false }
            
            let dateInRange = taskDate >= startDate && taskDate <= endDate
            let matchesSearch = searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText)
            let hasNotesFilter = !showOnlyWithNotes || (task.notes != nil && !task.notes!.isEmpty)
            
            return dateInRange && matchesSearch && hasNotesFilter
        }.sorted { $0.date ?? Date() > $1.date ?? Date() }
    }
    
    var body: some View {
        VStack {
            filterSection
            
            List(filteredTasks) { task in
                TaskRowView(task: task) {
                    selectedTask = task
                    showNotes = true
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        taskToDelete = task
                        showDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Task Table")
        .sheet(isPresented: $showNotes) {
            if let task = selectedTask {
                NotesView(task: task)
            }
        }
        .alert("Delete Task", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let task = taskToDelete {
                    modelContext.delete(task)
                }
            }
        } message: {
            Text("Are you sure you want to delete this task?")
        }
    }
    
    private var filterSection: some View {
        VStack(spacing: 12) {
            TextField("Search tasks...", text: $searchText)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, displayedComponents: .date)
            }
            
            Toggle("Only tasks with notes", isOn: $showOnlyWithNotes)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

struct TaskRowView: View {
    let task: Task
    let onNotesAction: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.title)
                    .font(.headline)
                Spacer()
                Text(task.date?.formatted(date: .abbreviated, time: .omitted) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text("\(task.startTime) - \(task.endTime)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if !task.taskDescription.isEmpty {
                Text(task.taskDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                if task.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if task.notCompleted {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                if task.notes != nil && !task.notes!.isEmpty {
                    Button(action: onNotesAction) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Text("Weight: \(Int(task.weight))")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}