import SwiftUI
import SwiftData

struct TaskTableView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    
    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "P1": return .red
        case "P2": return .orange
        case "P3": return .blue
        case "P4": return .gray
        default: return .blue
        }
    }
    @State private var searchText = ""
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var showOnlyWithNotes = false
    @State private var showOnlyWithAttachments = false
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
    @State private var bulkUpdateDate = Date()
    @State private var shouldUpdateDate = false
    @State private var showBulkDeleteConfirmation = false
    @State private var showTaskActions = false
    @State private var selectedTaskForActions: Task?
    
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
            let hasAttachmentsFilter = !showOnlyWithAttachments || (task.attachments != nil && !task.attachments!.isEmpty)
            let taskTags = Set(task.taskDescription.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
            let hasNoTag = task.taskDescription.trimmingCharacters(in: .whitespaces).isEmpty
            let matchesTags = selectedTags.isEmpty || 
                             (!taskTags.isDisjoint(with: selectedTags)) ||
                             (selectedTags.contains("No Tag") && hasNoTag)
            
            return dateInRange && matchesSearch && hasNotesFilter && hasAttachmentsFilter && matchesTags
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
                    }, onTaskTap: {
                        if !isSelectionMode {
                            selectedTaskForActions = task
                            showTaskActions = true
                        }
                    }, isSelectionMode: isSelectionMode)
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
                        
                        Text("Leave empty to use default tags: work, personal, health, learning")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Toggle("Update Date", isOn: $shouldUpdateDate)
                        
                        if shouldUpdateDate {
                            DatePicker("New Date", selection: $bulkUpdateDate, displayedComponents: .date)
                        }
                        
                        Button("Update Tasks") {
                            for task in selectedTasks {
                                // Update tags
                                if bulkUpdateText.trimmingCharacters(in: .whitespaces).isEmpty {
                                    // Use default tags if empty
                                    task.taskDescription = "work, personal, health, learning"
                                } else {
                                    task.taskDescription = bulkUpdateText
                                }
                                
                                // Update date if requested
                                if shouldUpdateDate {
                                    task.date = bulkUpdateDate
                                }
                            }
                            try? modelContext.save()
                            showBulkUpdate = false
                            bulkUpdateText = ""
                            shouldUpdateDate = false
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
                        shouldUpdateDate = false
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
                bulkUpdateText = ""
                shouldUpdateDate = false
                selectedTasks.removeAll()
                isSelectionMode = false
            }
        } message: {
            Text("Are you sure you want to delete these tasks? This action cannot be undone.")
        }
        .sheet(isPresented: $showTaskActions) {
            if let task = selectedTaskForActions {
                TaskActionsView(task: task, selectedDate: task.date ?? Date(), onTaskDeleted: {
                    selectedTaskForActions = nil
                })
                    .presentationDetents([.medium, .large])
            }
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
            
            Toggle("Only tasks with attachments", isOn: $showOnlyWithAttachments)
            
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
    var onTaskTap: (() -> Void)? = nil
    var isSelectionMode: Bool = false
    @State private var showTimeSpentEditor = false
    
    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "P1": return .red
        case "P2": return .orange
        case "P3": return .blue
        case "P4": return .gray
        default: return .blue
        }
    }
    
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
            
            HStack {
                Text("\(task.startTime) - \(task.endTime)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                // Show time spent for all tasks
                Button(action: { 
                    if !isSelectionMode {
                        showTimeSpentEditor = true
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                        if let timeSpent = task.timeSpent {
                            Text("\(Int(timeSpent))m")
                                .font(.caption2)
                        } else {
                            Text("Set time")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.purple.opacity(0.1))
                    .cornerRadius(4)
                }
            }
            
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
                if let attachments = task.attachments, !attachments.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.blue)
                        Text("\(attachments.count)")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                SubtaskCountButton(task: task)
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
                
                // Show effective weight if different from base weight
                let effectiveWeight = task.effectiveWeight
                if abs(effectiveWeight - task.weight) > 0.01 {
                    Text("Weight: \(String(format: "%.1f", effectiveWeight))/\(String(format: "%.1f", task.weight))")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                } else {
                    Text("Weight: \(String(format: "%.1f", task.weight))")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Text(task.priority)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor(task.priority))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTaskTap?()
        }
        .sheet(isPresented: $showTimeSpentEditor) {
            TimeSpentEditorView(task: task)
        }
    }
}

struct TimeSpentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: Task
    @State private var timeSpentMinutes: String = ""
    @State private var elapsedTimeMinutes: String = ""
    @State private var previousEffectiveWeight: Double = 0.0
    
    var isUntimedTask: Bool {
        task.startTime.isEmpty && task.endTime.isEmpty
    }
    
    @ViewBuilder
    private func calculationView(minutes: Double) -> some View {
        let allocated = getAllocatedTime()
        
        if allocated > 0 {
            let ratio = minutes / allocated
            let effectivePoints = task.weight * ratio
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Points Calculation:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Base points: \(String(format: "%.1f", task.weight))")
                    .font(.caption)
                Text("Time ratio: \(String(format: "%.2f", ratio)) (\(Int(minutes))m / \(Int(allocated))m)")
                    .font(.caption)
                Text("Effective points: \(String(format: "%.1f", effectivePoints))")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(ratio > 1 ? .orange : .green)
            }
            .padding()
            .background(.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private func getAllocatedTime() -> Double {
        if isUntimedTask, let elapsed = Double(elapsedTimeMinutes), elapsed > 0 {
            return elapsed
        } else {
            return task.allocatedTimeInMinutes
        }
    }
    
    private func addTimeSpent(_ minutes: Double) {
        let currentTimeSpent = task.timeSpent ?? 0.0
        let newTimeSpent = currentTimeSpent + minutes
        
        // Capture the current effective weight BEFORE making any changes
        let oldEffectiveWeight = task.effectiveWeight
        
        task.timeSpent = newTimeSpent
        timeSpentMinutes = String(Int(newTimeSpent))
        
        // Update reward points if task is completed
        if task.completed {
            let newEffectiveWeight = task.effectiveWeight
            let pointsDifference = newEffectiveWeight - oldEffectiveWeight
            
            print("⏱️ Time spent updated: \(currentTimeSpent)m → \(newTimeSpent)m")
            print("📊 Effective weight changed: \(oldEffectiveWeight) → \(newEffectiveWeight)")
            print("🔄 Points difference: \(pointsDifference)")
            
            // Check if task has linked rewards
            let activeRewardLinks = task.rewardLinks?.filter { $0.isActive } ?? []
            
            if !activeRewardLinks.isEmpty {
                // Add points difference to all linked rewards
                print("🎁 Updating \(activeRewardLinks.count) linked reward(s)")
                for link in activeRewardLinks {
                    if let reward = link.reward {
                        print("➕ Adding \(pointsDifference) points to '\(reward.name)'")
                        reward.addAmount(pointsDifference, context: modelContext, taskTitle: task.title, comment: "Time spent adjustment")
                    }
                }
            } else {
                // No reward links - add to Unclaimed Points
                print("➕ No reward links, adding \(pointsDifference) points to Unclaimed Points")
                Reward.addUnclaimedPoints(pointsDifference, context: modelContext)
            }
            
            // Update the stored previous weight for next time
            previousEffectiveWeight = newEffectiveWeight
        }
        
        try? modelContext.save()
    }
    
    private func addElapsedTime(_ minutes: Double) {
        let currentElapsedTime = task.elapsedTime ?? 0.0
        let newElapsedTime = currentElapsedTime + minutes
        
        // Capture the current effective weight BEFORE making any changes
        let oldEffectiveWeight = task.effectiveWeight
        
        task.elapsedTime = newElapsedTime
        elapsedTimeMinutes = String(Int(newElapsedTime))
        
        // Update reward points if task is completed
        if task.completed {
            let newEffectiveWeight = task.effectiveWeight
            let pointsDifference = newEffectiveWeight - oldEffectiveWeight
            
            print("⏱️ Elapsed time updated: \(currentElapsedTime)m → \(newElapsedTime)m")
            print("📊 Effective weight changed: \(oldEffectiveWeight) → \(newEffectiveWeight)")
            print("🔄 Points difference: \(pointsDifference)")
            
            // Check if task has linked rewards
            let activeRewardLinks = task.rewardLinks?.filter { $0.isActive } ?? []
            
            if !activeRewardLinks.isEmpty {
                // Add points difference to all linked rewards
                print("🎁 Updating \(activeRewardLinks.count) linked reward(s)")
                for link in activeRewardLinks {
                    if let reward = link.reward {
                        print("➕ Adding \(pointsDifference) points to '\(reward.name)'")
                        reward.addAmount(pointsDifference, context: modelContext, taskTitle: task.title, comment: "Elapsed time adjustment")
                    }
                }
            } else {
                // No reward links - add to Unclaimed Points
                print("➕ No reward links, adding \(pointsDifference) points to Unclaimed Points")
                Reward.addUnclaimedPoints(pointsDifference, context: modelContext)
            }
            
            // Update the stored previous weight for next time
            previousEffectiveWeight = newEffectiveWeight
        }
        
        try? modelContext.save()
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(.headline)
                    
                    if !isUntimedTask {
                        Text("\(task.startTime) - \(task.endTime)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Untimed Task")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    let allocated = task.allocatedTimeInMinutes
                    if allocated > 0 {
                        Text("Allocated: \(Int(allocated)) minutes (\(String(format: "%.1f", allocated / 60)) hours)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 12) {
                    if isUntimedTask {
                        Text("Elapsed Time (minutes)")
                            .font(.headline)
                        
                        TextField("Allocated time", text: $elapsedTimeMinutes)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                        
                        Text("How much time did you allocate for this task?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Time Spent (minutes)")
                        .font(.headline)
                    
                    TextField("Actual time", text: $timeSpentMinutes)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                    
                    if let minutes = Double(timeSpentMinutes), minutes > 0 {
                        calculationView(minutes: minutes)
                    }
                    
                    if isUntimedTask {
                        Text("Quick Elapsed Time:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("+5m") { addElapsedTime(5) }
                            Button("+15m") { addElapsedTime(15) }
                            Button("+30m") { addElapsedTime(30) }
                            Button("+60m") { addElapsedTime(60) }
                            Button("+120m") { addElapsedTime(120) }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Text("Quick Time Spent:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("+5m") { addTimeSpent(5) }
                        Button("+15m") { addTimeSpent(15) }
                        Button("+30m") { addTimeSpent(30) }
                        Button("+45m") { addTimeSpent(45) }
                        Button("+60m") { addTimeSpent(60) }
                    }
                    .buttonStyle(.bordered)
                    
                    if task.timeSpent != nil || task.elapsedTime != nil {
                        Button("Clear All Times") {
                            task.timeSpent = nil
                            if isUntimedTask {
                                task.elapsedTime = nil
                            }
                            try? modelContext.save()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding()
                
                Spacer()
            }
            .onAppear {
                if let timeSpent = task.timeSpent {
                    timeSpentMinutes = String(Int(timeSpent))
                }
                if let elapsedTime = task.elapsedTime {
                    elapsedTimeMinutes = String(Int(elapsedTime))
                }
                // Store initial effective weight for comparison
                previousEffectiveWeight = task.effectiveWeight
            }
            .navigationTitle("Set Time Spent")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Save") {
                    // Store previous effective weight before updating
                    let previousWeight = previousEffectiveWeight
                    
                    if let minutes = Double(timeSpentMinutes), minutes > 0 {
                        task.timeSpent = minutes
                    }
                    if isUntimedTask, let elapsed = Double(elapsedTimeMinutes), elapsed > 0 {
                        task.elapsedTime = elapsed
                    }
                    
                    // Update reward points if task is completed and values changed
                    if task.completed {
                        let newEffectiveWeight = task.effectiveWeight
                        let pointsDifference = newEffectiveWeight - previousWeight
                        
                        if pointsDifference != 0 {
                            print("💾 Manual save - Effective weight changed: \(previousWeight) → \(newEffectiveWeight)")
                            print("🔄 Points difference: \(pointsDifference)")
                            
                            // Check if task has linked rewards
                            let activeRewardLinks = task.rewardLinks?.filter { $0.isActive } ?? []
                            
                            if !activeRewardLinks.isEmpty {
                                // Add points difference to all linked rewards
                                print("🎁 Updating \(activeRewardLinks.count) linked reward(s)")
                                for link in activeRewardLinks {
                                    if let reward = link.reward {
                                        print("➕ Adding \(pointsDifference) points to '\(reward.name)'")
                                        reward.addAmount(pointsDifference, context: modelContext, taskTitle: task.title, comment: "Time adjustment")
                                    }
                                }
                            } else {
                                // No reward links - add to Unclaimed Points
                                print("➕ No reward links, adding \(pointsDifference) points to Unclaimed Points")
                                Reward.addUnclaimedPoints(pointsDifference, context: modelContext)
                            }
                        }
                    }
                    
                    try? modelContext.save()
                    dismiss()
                }
            )
        }
    }
}

struct NotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: Task
    @State private var notesText: String = ""
    @State private var isGeneratingSuggestions = false
    @State private var suggestionError: String?
    @State private var showSuggestionAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Task") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.headline)
                        if !task.taskDescription.isEmpty {
                            Text(task.taskDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        generateSuggestions()
                    }) {
                        HStack {
                            if isGeneratingSuggestions {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating suggestions...")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.purple)
                                Text("Get AI Suggestions")
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .disabled(isGeneratingSuggestions)
                    
                    if let error = suggestionError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("AI Assistant")
                } footer: {
                    Text("Generate suggestions based on task title, persistent notes, and current day")
                        .font(.caption2)
                }
                
                Section("Notes") {
                    RichTextEditor(text: $notesText)
                        .frame(height: 300)
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        task.notes = notesText.isEmpty ? nil : notesText
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                notesText = task.notes ?? ""
            }
        }
    }
    
    private func generateSuggestions() {
        isGeneratingSuggestions = true
        suggestionError = nil
        
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: task.date ?? Date())
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let dayName = dayNames[dayOfWeek - 1]
        
        _Concurrency.Task {
            do {
                let openAIService = OpenAIService()
                let suggestions = try await openAIService.generateTaskSuggestions(
                    taskTitle: task.title,
                    persistentNotes: task.persistentNotes,
                    currentNotes: notesText.isEmpty ? nil : notesText,
                    dayOfWeek: dayName,
                    date: task.date ?? Date()
                )
                
                await MainActor.run {
                    // Append suggestions to existing notes
                    if notesText.isEmpty {
                        notesText = suggestions
                    } else {
                        notesText += "\n\n--- AI Suggestions ---\n\(suggestions)"
                    }
                    isGeneratingSuggestions = false
                }
            } catch {
                await MainActor.run {
                    suggestionError = "Failed to generate suggestions"
                    isGeneratingSuggestions = false
                    print("❌ Error generating suggestions: \(error)")
                }
            }
        }
    }
}

struct PersistentNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: Task
    @State private var notesText: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Task") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.headline)
                        if !task.taskDescription.isEmpty {
                            Text(task.taskDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Persistent Notes") {
                    RichTextEditor(text: $notesText)
                        .frame(height: 300)
                }
            }
            .navigationTitle("Persistent Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        task.persistentNotes = notesText.isEmpty ? nil : notesText
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                notesText = task.persistentNotes ?? ""
            }
        }
    }
}
