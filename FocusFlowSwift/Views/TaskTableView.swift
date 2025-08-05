import SwiftUI
import SwiftData

struct TaskTableView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @State private var searchText = ""
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var showOnlyWithNotes = false
    @State private var selectedTags: Set<String> = []
    @State private var selectedTask: Task?
    @State private var showNotes = false
    @State private var showPersistentNotes = false
    @State private var taskToDelete: Task?
    @State private var showDeleteConfirmation = false
    @State private var showTagAnalytics = false
    @State private var selectedTasks: Set<Task> = []
    @State private var isSelectionMode = false
    @State private var showBulkUpdate = false
    @State private var bulkUpdateText = ""
    @State private var showBulkDeleteConfirmation = false
    
    var allTags: [String] {
        var tags = Array(Set(tasks.flatMap { $0.taskDescription.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() } })).sorted()
        tags.insert("No Tag", at: 0)
        return tags
    }
    
    var filteredTasks: [Task] {
        tasks.filter { task in
            guard let taskDate = task.date else { return false }
            
            let dateInRange = taskDate >= startDate && taskDate <= endDate
            let matchesSearch = searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText)
            let hasNotesFilter = !showOnlyWithNotes || (task.notes != nil && !task.notes!.isEmpty)
            let taskTags = Set(task.taskDescription.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
            let hasNoTag = task.taskDescription.trimmingCharacters(in: .whitespaces).isEmpty
            let matchesTags = selectedTags.isEmpty || 
                             (!taskTags.isDisjoint(with: selectedTags)) ||
                             (selectedTags.contains("No Tag") && hasNoTag)
            
            return dateInRange && matchesSearch && hasNotesFilter && matchesTags
        }.sorted { $0.date ?? Date() > $1.date ?? Date() }
    }
    
    var body: some View {
        VStack {
            filterSection
            
            List(filteredTasks) { task in
                HStack {
                    if isSelectionMode {
                        Button {
                            if selectedTasks.contains(task) {
                                selectedTasks.remove(task)
                            } else {
                                selectedTasks.insert(task)
                            }
                        } label: {
                            Image(systemName: selectedTasks.contains(task) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedTasks.contains(task) ? .blue : .gray)
                        }
                    }
                    TaskRowView(task: task, onNotesAction: {
                        if !isSelectionMode {
                            selectedTask = task
                            showNotes = true
                        }
                    }, onPersistentNotesAction: {
                        if !isSelectionMode {
                            selectedTask = task
                            showPersistentNotes = true
                        }
                    })
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if isSelectionMode {
                        if !selectedTasks.isEmpty {
                            Button("Update") {
                                showBulkUpdate = true
                            }
                        }
                        Button("Cancel") {
                            isSelectionMode = false
                            selectedTasks.removeAll()
                        }
                    } else {
                        Button("Select") {
                            isSelectionMode = true
                        }
                        Button {
                            showTagAnalytics = true
                        } label: {
                            Image(systemName: "chart.bar")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showNotes) {
            if let task = selectedTask {
                NotesView(task: task)
            }
        }
        .sheet(isPresented: $showPersistentNotes) {
            if let task = selectedTask {
                PersistentNotesView(task: task)
            }
        }
        .sheet(isPresented: $showTagAnalytics) {
            NavigationView {
                TagAnalyticsView()
            }
        }
        .sheet(isPresented: $showBulkUpdate) {
            NavigationView {
                VStack(spacing: 20) {
                    Text("\(selectedTasks.count) tasks selected")
                        .font(.headline)
                        .padding()
                    
                    VStack(spacing: 16) {
                        TextField("New tags (comma separated)", text: $bulkUpdateText)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Update Tags") {
                            for task in selectedTasks {
                                task.taskDescription = bulkUpdateText
                            }
                            try? modelContext.save()
                            showBulkUpdate = false
                            bulkUpdateText = ""
                            selectedTasks.removeAll()
                            isSelectionMode = false
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        
                        Button("Delete Tasks", role: .destructive) {
                            showBulkDeleteConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                    
                    Button("Cancel") {
                        showBulkUpdate = false
                        bulkUpdateText = ""
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                .navigationTitle("Bulk Actions")
                .navigationBarTitleDisplayMode(.inline)
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
        .alert("Delete \(selectedTasks.count) Tasks", isPresented: $showBulkDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                for task in selectedTasks {
                    modelContext.delete(task)
                }
                try? modelContext.save()
                showBulkUpdate = false
                selectedTasks.removeAll()
                isSelectionMode = false
            }
        } message: {
            Text("Are you sure you want to delete these tasks? This action cannot be undone.")
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
            
            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(allTags, id: \.self) { tag in
                            Button(tag) {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedTags.contains(tag) ? .blue : .gray.opacity(0.2))
                            .foregroundColor(selectedTags.contains(tag) ? .white : .primary)
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

struct TaskRowView: View {
    let task: Task
    let onNotesAction: () -> Void
    let onPersistentNotesAction: () -> Void
    
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
                if task.persistentNotes != nil && !task.persistentNotes!.isEmpty {
                    Button(action: onPersistentNotesAction) {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.purple)
                    }
                }
                Spacer()
                let taskTags = task.taskDescription.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if !taskTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(taskTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                }
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