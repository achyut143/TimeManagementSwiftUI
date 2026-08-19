import SwiftUI
import SwiftData
import AVFoundation
import Foundation

struct UntimedTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDate = Date()
    @State private var tasks: [Task] = []
    @State private var allTasks: [Task] = [] // For metrics calculation
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var editingTask: Task?
    @State private var showEditDialog = false
    @State private var taskTitle = ""
    @State private var taskTags = ""
    @State private var taskWeight = 1.0
    @State private var taskPriority = "P3"
    @State private var repeatDays = 0
    @State private var showNotesDialog = false
    @State private var notesTask: Task?
    @State private var showDeleteConfirmation = false
    @State private var taskToDelete: Task?
    @State private var showTaskActions = false
    @State private var selectedTaskForActions: Task?
    @State private var showTaskCreation = false
    @State private var showQuickTaskInput = false
    @State private var quickTaskInput = ""
    @State private var showMarkAllNotCompletedConfirmation = false
    @AppStorage("metricDays") private var metricDays: Int = 30 // Use AppStorage for cross-view sync
    @AppStorage("habitPercentageFilter") private var percentageFilter: String = "all"
    
    var body: some View {
        VStack(spacing: 0) {
            PointsIndicatorView(tasks: tasks)
            
            HStack {
                Button(showTaskCreation ? "Close" : "Add Untimed Task") {
                    showTaskCreation.toggle()
                }
                .buttonStyle(.borderedProminent)
                
                Toggle("Quick", isOn: $showQuickTaskInput)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: selectedDate) { _, _ in
                        updateQuery()
                    }
                
                Spacer()
            }
            .padding()
            
            if showTaskCreation {
                if showQuickTaskInput {
                    quickTaskInputView
                } else {
                    taskCreationHeader
                }
            }
            
            VStack(spacing: 4) {
                Text("Untimed Tasks")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks.filter { passesPercentageFilter($0) }) { task in
                        untimedTaskRow(task: task)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Untimed Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showMarkAllNotCompletedConfirmation = true
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            updateQuery()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TaskCreated"))) { _ in
            updateQuery()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TaskUpdated"))) { _ in
            updateQuery()
        }
        .sheet(isPresented: $showEditDialog) {
            if let task = editingTask {
                EditTaskView(task: task)
            }
        }
        .sheet(isPresented: $showNotesDialog) {
            if let task = notesTask {
                TaskNotesPagerView(task: task)
            }
        }
        .alert("Delete Task", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let task = taskToDelete {
                    deleteTask(task)
                }
            }
        } message: {
            Text("Are you sure you want to delete this task?")
        }
        .alert("Mark All as Not Completed", isPresented: $showMarkAllNotCompletedConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Mark All", role: .destructive) {
                markAllTasksAsNotCompleted()
            }
        } message: {
            let count = tasks.filter { task in
                guard let taskDate = task.date else { return false }
                let isSameDay = Calendar.current.isDate(taskDate, inSameDayAs: selectedDate)
                return isSameDay && !task.completed && !task.notCompleted
            }.count
            Text("This will mark \(count) task(s) as not completed for \(selectedDate.formatted(date: .abbreviated, time: .omitted)). Continue?")
        }
        .sheet(isPresented: $showTaskActions) {
            if let task = selectedTaskForActions {
                TaskActionsView(task: task, selectedDate: selectedDate, onTaskDeleted: updateQuery)
                    .presentationDetents([.medium])
            }
        }
    }
    
    private func untimedTaskRow(task: Task) -> some View {
        let metrics = task.repeatAgain != nil ? task.calculateMetrics(days: metricDays, allTasks: allTasks, referenceDate: selectedDate) : nil
        
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    // Show metrics for repeat tasks
                    if let metrics = metrics {
                        let pointsStats = calculatePointsForTask(task)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                // Score (completed/total)
                                VStack(spacing: 0) {
                                    Text(metrics.formattedScore)
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                    Text("Score")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 50, height: 35)
                                .background(Color.blue.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                
                                // Completion rate
                                VStack(spacing: 0) {
                                    Text(metrics.formattedCompletionRate)
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(metrics.completionColor == "green" ? .green : (metrics.completionColor == "orange" ? .orange : .red))
                                    Text("Rate")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 50, height: 35)
                                .background(Color(metrics.completionColor == "green" ? .green : (metrics.completionColor == "orange" ? .orange : .red)).opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                
                                // Points
                                VStack(spacing: 0) {
                                    Text("\(Int(pointsStats.earned))/\(Int(pointsStats.allocated))")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.purple)
                                    Text("Points")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 50, height: 35)
                                .background(Color.purple.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                
                                // Current streak
                                if metrics.currentStreak > 0 {
                                    VStack(spacing: 0) {
                                        HStack(spacing: 2) {
                                            Image(systemName: "flame.fill")
                                                .font(.caption2)
                                            Text("\(metrics.currentStreak)")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                        }
                                        .foregroundColor(.orange)
                                        Text("Streak")
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(width: 50, height: 35)
                                    .background(Color.orange.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                        .frame(height: 35)
                    }
                }
                
                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let taskDate = task.date {
                    Text(taskDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                HStack(spacing: 8) {
                    Text(String(format: "%.1f", task.weight))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(weightColor(task.weight))
                        .clipShape(Capsule())
                    
                    Text(task.priority)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(priorityColor(task.priority))
                        .clipShape(Capsule())
                    
                    if let elapsedTime = task.elapsedTime, elapsedTime > 0 {
                        Text("⏱️ \(Int(elapsedTime))m")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue)
                            .clipShape(Capsule())
                    }
                    
                    if let timeSpent = task.timeSpent, timeSpent > 0 {
                        Text("✓ \(Int(timeSpent))m")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.purple)
                            .clipShape(Capsule())
                    }
                    
                    if let repeatDays = task.repeatAgain {
                        HStack(spacing: 2) {
                            Image(systemName: "repeat")
                            Text("\(repeatDays)")
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                    
                    if task.notes != nil && !task.notes!.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundStyle(.orange)
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
                    
                    if task.repeatAgain != nil {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundColor(task.reassign ? .red : .green)
                            .onTapGesture {
                                // Toggle or clear the reassign flag
                                task.reassign.toggle()
                                // Persist the change
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("Failed to save reassign flag:", error)
                                }
                            }
                    }
                    
                    SubtaskCountButton(task: task)
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Button(action: {
                    toggleTaskCompletion(task)
                }) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(task.completed ? .green : .gray)
                }
                
                Button(action: {
                    selectedTaskForActions = task
                    showTaskActions = true
                }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding()
        .background(taskBackgroundColor(task))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var quickTaskInputView: some View {
        QuickTaskInputView(input: $quickTaskInput) { parsedTask in
            createQuickTask(from: parsedTask)
        }
    }
    
    private var taskCreationHeader: some View {
        VStack(spacing: 12) {
            Text("Create New Untimed Task")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            
            VStack(spacing: 8) {
                TextField("Task Title", text: $taskTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Tags (comma separated)", text: $taskTags)
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
                        Text("Repeat (days)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("0 = no repeat", value: $repeatDays, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
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
                    
                    Spacer()
                    
                    Button("Add") {
                        createUntimedTask()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private func updateQuery() {
        print("Querying untimed tasks for \(selectedDate)")
        
        let descriptor = FetchDescriptor<Task>(
            sortBy: [SortDescriptor(\.title)]
        )
        
        do {
            allTasks = try modelContext.fetch(descriptor) // Load all tasks for metrics
            tasks = allTasks.filter { task in
                // Filter for tasks with empty start/end times (untimed) and matching date
                guard let taskDate = task.date else { return false }
                return task.startTime.isEmpty && task.endTime.isEmpty && 
                       Calendar.current.isDate(taskDate, inSameDayAs: selectedDate)
            }
            
            // Fix any duplicate UUIDs before displaying
            Task.fixDuplicateUUIDs(in: tasks)
            
            print("Fetched \(tasks.count) untimed tasks for \(selectedDate)")
        } catch {
            print("Error fetching untimed tasks: \(error)")
            tasks = []
            allTasks = []
        }
    }
    
    private func createUntimedTask() {
        guard !taskTitle.isEmpty else { return }
        
        let task = Task(
            title: taskTitle,
            taskDescription: taskTags,
            startTime: "", // No start time for untimed tasks
            endTime: "", // No end time for untimed tasks
            weight: taskWeight,
            date: selectedDate, // Keep the date
            repeatAgain: repeatDays > 0 ? repeatDays : nil,
            priority: taskPriority
        )
        
        modelContext.insert(task)
        
        do {
            try modelContext.save()
            updateQuery()
        } catch {
            print("Error saving untimed task: \(error)")
        }
        
        // Reset form
        taskTitle = ""
        taskTags = ""
        taskWeight = 1.0
        taskPriority = "P3"
        repeatDays = 0
    }
    
    private func createQuickTask(from parsed: QuickTaskParser.ParsedTask) {
        let task = Task(
            title: parsed.title,
            taskDescription: "",
            startTime: parsed.startTime,
            endTime: parsed.endTime,
            weight: parsed.weight,
            date: selectedDate,
            repeatAgain: parsed.repeatDays,
            priority: "P3"
        )
        
        modelContext.insert(task)
        
        do {
            try modelContext.save()
            updateQuery()
        } catch {
            print("Error saving quick task: \(error)")
        }
    }
    
    private func toggleTaskCompletion(_ task: Task) {
        let wasCompleted = task.completed
        task.completed.toggle()
        print("📋 Task '\(task.title)' completion toggled. Completed: \(task.completed), Weight: \(task.weight), EffectiveWeight: \(task.effectiveWeight)")
        
        if task.completed {
            speakText("Task completed: \(task.title)")
            createRepeatTask(from: task)
        }
        try? modelContext.save()
    }
    
    private func deleteTask(_ task: Task) {
        modelContext.delete(task)
        try? modelContext.save()
        updateQuery()
    }
    
    private func markAllTasksAsNotCompleted() {
        // Filter tasks for the current selected date that are not already marked as completed or not completed
        let tasksToMark = tasks.filter { task in
            guard let taskDate = task.date else { return false }
            let isSameDay = Calendar.current.isDate(taskDate, inSameDayAs: selectedDate)
            return isSameDay && !task.completed && !task.notCompleted
        }
        
        // Mark each task as not completed using the existing logic
        for task in tasksToMark {
            task.notCompleted = true
            
            if !task.reassign {
                createRepeatTask(from: task)
            }
            
            if task.repeatAgain == nil || (task.repeatAgain != nil && task.repeatAgain! > 1) {
                createIncompleteTask(from: task)
            }
        }
        
        try? modelContext.save()
        updateQuery()
    }
    
    private func passesPercentageFilter(_ task: Task) -> Bool {
        guard percentageFilter != "all" else { return true }
        guard task.repeatAgain != nil else { return true }
        let metrics = task.calculateMetrics(days: metricDays, allTasks: allTasks, referenceDate: selectedDate)
        return percentageFilter == "above" ? metrics.completionRate >= 85 : metrics.completionRate < 85
    }

    private func taskBackgroundColor(_ task: Task) -> Color {
        if task.completed { return .green.opacity(0.3) }
        if task.notCompleted { return .red.opacity(0.3) }
        if task.five { return .blue.opacity(0.3) }
        return .gray.opacity(0.1)
    }
    
    private func weightColor(_ weight: Double) -> Color {
        if weight > 7 { return .red }
        if weight > 4 { return .orange }
        return .blue
    }
    
    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "P1": return .red
        case "P2": return .orange
        case "P3": return .blue
        case "P4": return .gray
        default: return .blue
        }
    }
    
    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        speechSynthesizer.speak(utterance)
    }
    
    private func calculatePointsForTask(_ task: Task) -> (earned: Double, allocated: Double) {
        guard task.repeatAgain != nil else {
            return (earned: 0, allocated: 0)
        }
        
        // Get all tasks with the same title (same habit)
        let habitTasks = allTasks.filter { $0.title == task.title && $0.repeatAgain != nil }
        
        var earnedPoints: Double = 0
        var allocatedPoints: Double = 0
        
        // Calculate points for the last metricDays
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: selectedDate)
        let startDate = calendar.date(byAdding: .day, value: -metricDays, to: endDate) ?? endDate
        
        var currentDate = startDate
        while currentDate <= endDate {
            let dayTasks = habitTasks.filter { habitTask in
                guard let taskDate = habitTask.date else { return false }
                return calendar.isDate(taskDate, inSameDayAs: currentDate)
            }
            
            for dayTask in dayTasks {
                allocatedPoints += dayTask.weight
                if dayTask.completed {
                    earnedPoints += dayTask.effectiveWeight
                }
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return (earned: earnedPoints, allocated: allocatedPoints)
    }
    
    private func createRepeatTask(from task: Task) {
        guard let repeatDays = task.repeatAgain, let currentDate = task.date else { return }
        
        let nextDate = Calendar.current.date(byAdding: .day, value: repeatDays, to: currentDate) ?? currentDate
        
        // Check if task already exists
        let descriptor = FetchDescriptor<Task>()
        do {
            let existingTasks = try modelContext.fetch(descriptor)
            let taskExists = existingTasks.contains { existingTask in
                guard let existingDate = existingTask.date else { return false }
                return Calendar.current.isDate(existingDate, inSameDayAs: nextDate) &&
                       existingTask.startTime == task.startTime &&
                       existingTask.endTime == task.endTime &&
                       existingTask.title == task.title
            }
            if taskExists { return }
        } catch { return }
        
        let newTask = Task(
            title: task.title,
            taskDescription: task.taskDescription,
            startTime: task.startTime,
            endTime: task.endTime,
            weight: task.weight,
            date: nextDate,
            repeatAgain: task.repeatAgain,
            priority: task.priority,
            elapsedTime: task.elapsedTime // Copy elapsed time to new task
            // timeSpent is intentionally not copied for repeat tasks
        )
        newTask.goal = task.goal

        modelContext.insert(newTask)
        try? modelContext.save()
    }

    private func createRepeatTaskFromActions(from task: Task) {
        guard let repeatDays = task.repeatAgain, let currentDate = task.date else { return }
        
        let nextDate = Calendar.current.date(byAdding: .day, value: repeatDays, to: currentDate) ?? currentDate
        
        // Check if task already exists
        let descriptor = FetchDescriptor<Task>()
        do {
            let existingTasks = try modelContext.fetch(descriptor)
            let taskExists = existingTasks.contains { existingTask in
                guard let existingDate = existingTask.date else { return false }
                return Calendar.current.isDate(existingDate, inSameDayAs: nextDate) &&
                       existingTask.startTime == task.startTime &&
                       existingTask.endTime == task.endTime &&
                       existingTask.title == task.title
            }
            if taskExists { return }
        } catch { return }
        
        let newTask = Task(
            title: task.title,
            taskDescription: task.taskDescription,
            startTime: task.startTime,
            endTime: task.endTime,
            weight: task.weight,
            date: nextDate,
            repeatAgain: task.repeatAgain,
            priority: task.priority,
            elapsedTime: task.elapsedTime // Copy elapsed time to new task
            // timeSpent is intentionally not copied for repeat tasks
        )
        newTask.goal = task.goal

        modelContext.insert(newTask)
        try? modelContext.save()
    }

    private func createIncompleteTask(from task: Task) {
        guard let currentDate = task.date else { return }
        
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        
        // Check if task already exists
        let descriptor = FetchDescriptor<Task>()
        do {
            let existingTasks = try modelContext.fetch(descriptor)
            let taskExists = existingTasks.contains { existingTask in
                guard let existingDate = existingTask.date else { return false }
                return Calendar.current.isDate(existingDate, inSameDayAs: nextDate) &&
                       existingTask.startTime == task.startTime &&
                       existingTask.endTime == task.endTime &&
                       existingTask.title == task.title
            }
            if taskExists { return }
        } catch { return }
        
        let newTask = Task(
            title: task.title,
            taskDescription: task.taskDescription,
            startTime: task.startTime,
            endTime: task.endTime,
            reassign: true,
            weight: task.weight,
            date: nextDate,
            repeatAgain: task.repeatAgain,
            priority: task.priority,
            elapsedTime: task.elapsedTime // Copy elapsed time to new task
            // timeSpent is intentionally not copied for repeat tasks
        )
        newTask.goal = task.goal

        modelContext.insert(newTask)
        try? modelContext.save()
    }
}



