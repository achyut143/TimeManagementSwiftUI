import SwiftUI
import SwiftData
import AVFoundation
import Speech
import Foundation

struct UntimedTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDate = Date()
    @State private var tasks: [Task] = []
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
    @State private var showAITaskCreation = false
    @State private var aiInput = ""
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var audioEngine = AVAudioEngine()
    @State private var recognitionTask: SFSpeechRecognitionTask?
    
    var body: some View {
        VStack(spacing: 0) {
            pointsIndicator
            
            HStack {
                Button(showTaskCreation ? "Close" : "Add Untimed Task") {
                    showTaskCreation.toggle()
                }
                .buttonStyle(.borderedProminent)
                
                Toggle("AI", isOn: $showAITaskCreation)
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
                if showAITaskCreation {
                    aiTaskCreationHeader
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
                    ForEach(tasks) { task in
                        untimedTaskRow(task: task)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Untimed Tasks")
        .navigationBarTitleDisplayMode(.inline)
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
                NotesView(task: task)
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
        .sheet(isPresented: $showTaskActions) {
            if let task = selectedTaskForActions {
                TaskActionsView(task: task, onTaskDeleted: updateQuery)
                    .presentationDetents([.medium])
            }
        }
    }
    
    private func untimedTaskRow(task: Task) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                    .fontWeight(.medium)
                
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
    
    private var aiTaskCreationHeader: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("AI Assistant")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            VStack(spacing: 12) {
                TextEditor(text: $aiInput)
                    .frame(minHeight: 90)
                    .padding(12)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                    .cornerRadius(12)
                
                HStack(spacing: 16) {
                    Button(action: toggleRecording) {
                        HStack(spacing: 8) {
                            Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title3)
                            Text(isRecording ? "Stop" : "Record")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(isRecording ? .red : .blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isRecording ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                        .cornerRadius(20)
                    }
                    
                    Spacer()
                    
                    if isProcessing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Processing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Button("Generate Tasks") {
                        generateAITask()
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(aiInput.isEmpty || isProcessing ? Color.gray : Color.blue)
                    .cornerRadius(20)
                    .disabled(aiInput.isEmpty || isProcessing)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal)
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
    
    private var pointsIndicator: some View {
        let totalPoints = tasks.reduce(0) { $0 + $1.weight }
        let completedPoints = tasks.filter { $0.completed }.reduce(0) { $0 + $1.effectiveWeight }
        
        return HStack {
            Text("Points: \(String(format: "%.1f", completedPoints))/\(Int(totalPoints))")
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
            
            if totalPoints > 0 {
                ProgressView(value: completedPoints / totalPoints)
                    .frame(width: 100)
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
            let allTasks = try modelContext.fetch(descriptor)
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
    
    private func toggleTaskCompletion(_ task: Task) {
        let wasCompleted = task.completed
        task.completed.toggle()
        print("📋 Task '\(task.title)' completion toggled. Completed: \(task.completed), Weight: \(task.weight), EffectiveWeight: \(task.effectiveWeight)")
        
        if task.completed {
            speakText("Task completed: \(task.title)")
            createRepeatTask(from: task)
            // Add points to Unclaimed Points reward
            print("➕ Adding \(task.effectiveWeight) points for completed task")
            Reward.addUnclaimedPoints(task.effectiveWeight, context: modelContext)
        } else if wasCompleted {
            // If uncompleting, subtract the points
            print("➖ Subtracting \(task.effectiveWeight) points for uncompleted task")
            Reward.addUnclaimedPoints(-task.effectiveWeight, context: modelContext)
        }
        try? modelContext.save()
    }
    
    private func deleteTask(_ task: Task) {
        modelContext.delete(task)
        try? modelContext.save()
        updateQuery()
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
    
    // MARK: - AI and Recording Functions
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
        }
        
        let recognizer = SFSpeechRecognizer()
        guard let recognizer = recognizer, recognizer.isAvailable else { return }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true)
        } catch {
            print("Audio session error: \(error)")
            return
        }
        
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self.aiInput = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stopRecording()
                    }
                }
            }
            if error != nil {
                DispatchQueue.main.async {
                    self.stopRecording()
                }
            }
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        isRecording = true
    }
    
    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isRecording = false
    }
    
    private func generateAITask() {
        isProcessing = true
        
        _Concurrency.Task {
            do {
                let openAI = OpenAIService()
                let tasksData = try await openAI.generateTasks(from: aiInput)
                
                DispatchQueue.main.async {
                    for taskData in tasksData {
                        // Create untimed tasks from AI input
                        let newTask = Task(
                            title: taskData.title,
                            taskDescription: taskData.description,
                            startTime: "", // No start time for untimed tasks
                            endTime: "", // No end time for untimed tasks
                            weight: taskData.weight,
                            date: selectedDate, // Keep the date
                            priority: taskData.priority
                        )
                        
                        self.modelContext.insert(newTask)
                    }
                    try? self.modelContext.save()
                    
                    self.updateQuery()
                    self.aiInput = ""
                    self.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.createTaskWithFallback()
                }
            }
        }
    }
    
    private func createTaskWithFallback() {
        let newTask = Task(
            title: aiInput.components(separatedBy: .newlines).first ?? "AI Task",
            taskDescription: "ai-generated",
            startTime: "", // No start time
            endTime: "", // No end time
            weight: 1.0,
            date: selectedDate // Keep the date
        )
        
        modelContext.insert(newTask)
        try? modelContext.save()
        updateQuery()
        aiInput = ""
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
            persistentNotes: task.persistentNotes,
            date: nextDate,
            repeatAgain: task.repeatAgain,
            priority: task.priority,
            elapsedTime: task.elapsedTime // Copy elapsed time to new task
            // timeSpent is intentionally not copied for repeat tasks
        )
        
        modelContext.insert(newTask)
        
        // Copy reward workflows from original task
        if let rewardLinks = task.rewardLinks?.filter({ $0.isActive }) {
            for link in rewardLinks {
                if let reward = link.reward {
                    let newLink = TaskRewardLink(task: newTask, reward: reward)
                    modelContext.insert(newLink)
                }
            }
        }
        
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
            persistentNotes: task.persistentNotes,
            date: nextDate,
            repeatAgain: task.repeatAgain,
            priority: task.priority,
            elapsedTime: task.elapsedTime // Copy elapsed time to new task
            // timeSpent is intentionally not copied for repeat tasks
        )
        
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
            persistentNotes: task.persistentNotes,
            date: nextDate,
            repeatAgain: task.repeatAgain,
            priority: task.priority,
            elapsedTime: task.elapsedTime // Copy elapsed time to new task
            // timeSpent is intentionally not copied for repeat tasks
        )
        
        modelContext.insert(newTask)
        try? modelContext.save()
    }
}



