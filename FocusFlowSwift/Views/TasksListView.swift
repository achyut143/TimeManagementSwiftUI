import SwiftUI
import SwiftData

struct TasksListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var tasks: [Task] = []
    @State private var expandedParents: Set<String> = []
    @State private var showTaskCreation = false
    @State private var taskTitle = ""
    @State private var taskDescription = ""
    @State private var taskWeight = 1.0
    @State private var taskPriority = "P3"
    @State private var selectedParentTask: Task?
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            if showTaskCreation {
                taskCreationView
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(parentTasks, id: \.id) { parentTask in
                        parentTaskView(parentTask)
                    }
                    
                    if !orphanTasks.isEmpty {
                        Section("Tasks without Parent") {
                            ForEach(orphanTasks, id: \.id) { task in
                                taskRowView(task, isChild: false)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Tasks List")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateQuery()
        }
    }
    
    private var headerView: some View {
        HStack {
            Button(showTaskCreation ? "Cancel" : "Add Task") {
                showTaskCreation.toggle()
                if !showTaskCreation {
                    clearForm()
                }
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
            
            Text("\(tasksWithoutTime.count) tasks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var taskCreationView: some View {
        VStack(spacing: 12) {
            Text("Create New Task")
                .font(.title3)
                .fontWeight(.medium)
            
            VStack(spacing: 8) {
                TextField("Task Title", text: $taskTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Description", text: $taskDescription)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Weight")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. 5.5", value: $taskWeight, format: .number.precision(.fractionLength(0...2)))
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Priority")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Priority", selection: $taskPriority) {
                            Text("P1").tag("P1")
                            Text("P2").tag("P2")
                            Text("P3").tag("P3")
                            Text("P4").tag("P4")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Parent Task")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Parent", selection: $selectedParentTask) {
                            Text("None").tag(nil as Task?)
                            ForEach(parentTasks, id: \.id) { task in
                                Text(task.title).tag(task as Task?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                    
                    Button("Add") {
                        createTask()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(taskTitle.isEmpty)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private func parentTaskView(_ parentTask: Task) -> some View {
        let childTasks = getChildTasks(for: parentTask)
        let taskId = parentTask.persistentModelID.hashValue.description
        let isExpanded = expandedParents.contains(taskId)
        
        return VStack(spacing: 0) {
            // Parent task row
            HStack {
                Button(action: {
                    toggleExpansion(for: parentTask)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(parentTask.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            if !parentTask.taskDescription.isEmpty {
                                Text(parentTask.taskDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Text("\(childTasks.count)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue)
                                .clipShape(Capsule())
                            
                            if let attachments = parentTask.attachments, !attachments.isEmpty {
                                HStack(spacing: 2) {
                                    Image(systemName: "paperclip")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                    Text("\(attachments.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.blue)
                                        .clipShape(Capsule())
                                }
                            }
                            
                            Text(String(format: "%.1f", parentTask.weight))
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(weightColor(parentTask.weight))
                                .clipShape(Capsule())
                            
                            Text(parentTask.priority)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(priorityColor(parentTask.priority))
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(taskBackgroundColor(parentTask))
            .cornerRadius(12)
            .contextMenu {
                Button {
                    toggleTaskCompletion(parentTask)
                } label: {
                    Label(parentTask.completed ? "Mark Incomplete" : "Mark Complete", systemImage: parentTask.completed ? "xmark.circle" : "checkmark.circle")
                }
            }
            
            // Child tasks (when expanded)
            if isExpanded && !childTasks.isEmpty {
                VStack(spacing: 4) {
                    ForEach(childTasks, id: \.id) { childTask in
                        taskRowView(childTask, isChild: true)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 8)
            }
        }
    }
    
    private func taskRowView(_ task: Task, isChild: Bool) -> some View {
        HStack {
            if isChild {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(isChild ? .subheadline : .headline)
                    .foregroundStyle(.primary)
                
                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if task.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if task.notCompleted {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                
                if let attachments = task.attachments, !attachments.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text("\(attachments.count)")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue)
                            .clipShape(Capsule())
                    }
                }
                
                Text(String(format: "%.1f", task.weight))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(weightColor(task.weight))
                    .clipShape(Capsule())
                
                Text(task.priority)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor(task.priority))
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(taskBackgroundColor(task))
        .cornerRadius(isChild ? 8 : 12)
        .onTapGesture {
            toggleTaskCompletion(task)
        }
        .contextMenu {
            Button {
                toggleTaskCompletion(task)
            } label: {
                Label(task.completed ? "Mark Incomplete" : "Mark Complete", systemImage: task.completed ? "xmark.circle" : "checkmark.circle")
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var tasksWithoutTime: [Task] {
        tasks.filter { task in
            task.startTime.isEmpty || task.endTime.isEmpty
        }
    }
    
    private var parentTasks: [Task] {
        tasksWithoutTime.filter { task in
            !hasParentTask(task)
        }
    }
    
    private var orphanTasks: [Task] {
        tasksWithoutTime.filter { task in
            !hasParentTask(task) && getChildTasks(for: task).isEmpty
        }
    }
    
    // MARK: - Helper Methods
    
    private func hasParentTask(_ task: Task) -> Bool {
        // Since Task model doesn't have parentTask, we'll use a naming convention
        // Tasks with parent will have a specific pattern in their title or description
        return task.title.contains("[Child]")
    }
    
    private func getChildTasks(for parentTask: Task) -> [Task] {
        return tasks.filter { task in
            task.title.contains("[Child of: \(parentTask.title)]")
        }
    }
    
    private func updateQuery() {
        // Fetch tasks from SwiftData
        let descriptor = FetchDescriptor<Task>()
        do {
            tasks = try modelContext.fetch(descriptor)
            // Fix any duplicate UUIDs
            Task.fixDuplicateUUIDs(in: tasks)
        } catch {
            print("Failed to fetch tasks: \(error)")
        }
    }
    
    private func clearForm() {
        taskTitle = ""
        taskDescription = ""
        taskWeight = 1.0
        taskPriority = "P3"
        selectedParentTask = nil
    }
    
    private func createTask() {
        let newTask = Task(
            title: selectedParentTask != nil ? "[Child of: \(selectedParentTask!.title)] \(taskTitle)" : taskTitle,
            taskDescription: taskDescription,
            weight: taskWeight,
            priority: taskPriority
        )
        
        modelContext.insert(newTask)
        
        do {
            try modelContext.save()
            updateQuery()
            clearForm()
            showTaskCreation = false
        } catch {
            print("Failed to save task: \(error)")
        }
    }
    
    private func toggleExpansion(for task: Task) {
        let taskId = task.persistentModelID.hashValue.description
        if expandedParents.contains(taskId) {
            expandedParents.remove(taskId)
        } else {
            expandedParents.insert(taskId)
        }
    }
    
    private func toggleTaskCompletion(_ task: Task) {
        let wasCompleted = task.completed
        task.completed.toggle()
        print("📋 Task '\(task.title)' completion toggled. Completed: \(task.completed), Weight: \(task.weight), EffectiveWeight: \(task.effectiveWeight)")
        
        if task.completed {
            task.notCompleted = false
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to update task: \(error)")
        }
    }
    
    private func weightColor(_ weight: Double) -> Color {
        switch weight {
        case 1...3:
            return .green
        case 4...6:
            return .orange
        case 7...10:
            return .red
        default:
            return .gray
        }
    }
    
    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "P1":
            return .red
        case "P2":
            return .orange
        case "P3":
            return .blue
        case "P4":
            return .gray
        default:
            return .gray
        }
    }
    
    private func taskBackgroundColor(_ task: Task) -> Color {
        if task.completed {
            return .green.opacity(0.1)
        } else if task.notCompleted {
            return .red.opacity(0.1)
        } else {
            return .gray.opacity(0.05)
        }
    }}
