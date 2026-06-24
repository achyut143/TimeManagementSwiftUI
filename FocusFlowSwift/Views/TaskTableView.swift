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
    @State private var appliedSearch = ""
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var pendingStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var pendingEndDate = Date()
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
    @State private var statusFilter: StatusFilter = .all
    @AppStorage("taskTableShowTodayOnly") private var showTodayOnly: Bool = false
    @AppStorage("metricDays") private var metricDays: Int = 30
    @AppStorage("habitPercentageFilter") private var percentageFilter: String = "all"

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case pending = "Pending"
        case completed = "Completed"
        case notCompleted = "Not Completed"
    }

    var allTags: [String] {
        var tagSet = Set<String>()
        for task in tasks {
            let parts = task.taskDescription.split(separator: ",")
            for part in parts {
                tagSet.insert(part.trimmingCharacters(in: .whitespaces).lowercased())
            }
        }
        var tags = tagSet.sorted()
        tags.insert("No Tag", at: 0)
        return tags
    }

    private func taskMatchesStatus(completed: Bool, notCompleted: Bool) -> Bool {
        switch statusFilter {
        case .all: return true
        case .pending: return !completed && !notCompleted
        case .completed: return completed
        case .notCompleted: return notCompleted
        }
    }

    private func taskMatchesTags(description: String) -> Bool {
        guard !selectedTags.isEmpty else { return true }
        let taskTags = Set(description.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let hasNoTag = description.trimmingCharacters(in: .whitespaces).isEmpty
        return !taskTags.isDisjoint(with: selectedTags) || (selectedTags.contains("No Tag") && hasNoTag)
    }

    var filteredTasks: [Task] {
        let calendar = Calendar.current
        let effectiveStart: Date
        let effectiveEnd: Date
        if showTodayOnly {
            effectiveStart = calendar.startOfDay(for: Date())
            effectiveEnd = calendar.date(byAdding: .day, value: 1, to: effectiveStart)!
        } else {
            effectiveStart = calendar.startOfDay(for: startDate)
            effectiveEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
        }
        let rangeStart = effectiveStart
        let rangeEnd = effectiveEnd

        // Pre-compute metrics for habit tasks once — avoids calling calculateMetrics inside the filter (O(n²))
        var completionRateCache: [ObjectIdentifier: Double] = [:]
        if percentageFilter != "all" {
            let allTasksArray = Array(tasks)
            for task in tasks where task.repeatAgain != nil {
                let m = task.calculateMetrics(days: metricDays, allTasks: allTasksArray, referenceDate: task.date ?? Date())
                completionRateCache[ObjectIdentifier(task)] = m.completionRate
            }
        }

        return tasks.filter { task in
            guard let taskDate = task.date else { return false }
            guard taskDate >= rangeStart && taskDate < rangeEnd else { return false }
            guard appliedSearch.isEmpty || task.title.localizedCaseInsensitiveContains(appliedSearch) else { return false }
            guard !showOnlyWithNotes || (task.notes != nil && !task.notes!.isEmpty) else { return false }
            guard !showOnlyWithAttachments || (task.attachments != nil && !task.attachments!.isEmpty) else { return false }
            guard taskMatchesStatus(completed: task.completed, notCompleted: task.notCompleted) else { return false }
            guard taskMatchesTags(description: task.taskDescription) else { return false }
            if percentageFilter != "all" && task.repeatAgain != nil {
                let rate = completionRateCache[ObjectIdentifier(task)] ?? 0
                if percentageFilter == "above" { guard rate >= 85 else { return false } }
                else { guard rate < 85 else { return false } }
            }
            return true
        }.sorted(by: taskDisplayOrder)
    }

    // Morning -> Afternoon -> Untimed (at the 4pm mark) -> 4pm-and-later tasks, per day.
    private enum TimeSlot: Int {
        case morning = 0
        case afternoon = 1
        case untimed = 2
        case evening = 3
    }

    private func startMinutes(_ time: String) -> Int? {
        let components = time.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return nil }
        return components[0] * 60 + components[1]
    }

    private func timeSlot(for task: Task) -> TimeSlot {
        guard !task.startTime.isEmpty || !task.endTime.isEmpty else { return .untimed }
        guard let minutes = startMinutes(task.startTime) else { return .untimed }
        if minutes < 12 * 60 { return .morning }
        if minutes < 16 * 60 { return .afternoon }
        return .evening
    }

    private func taskDisplayOrder(_ lhs: Task, _ rhs: Task) -> Bool {
        let lhsDay = Calendar.current.startOfDay(for: lhs.date ?? Date())
        let rhsDay = Calendar.current.startOfDay(for: rhs.date ?? Date())
        if lhsDay != rhsDay { return lhsDay > rhsDay }

        let lhsSlot = timeSlot(for: lhs)
        let rhsSlot = timeSlot(for: rhs)
        if lhsSlot != rhsSlot { return lhsSlot.rawValue < rhsSlot.rawValue }

        guard lhsSlot != .untimed else { return false }
        return (startMinutes(lhs.startTime) ?? 0) < (startMinutes(rhs.startTime) ?? 0)
    }

    private func taskRowBackground(_ task: Task) -> Color {
        if task.completed { return .green.opacity(0.3) }
        if task.notCompleted { return .red.opacity(0.3) }
        if (task.timeSpent ?? 0) > 0 { return .orange.opacity(0.3) }
        return .clear
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
                    TaskRowView(task: task, allTasks: Array(tasks), metricDays: metricDays, onNotesAction: {
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
                .listRowBackground(taskRowBackground(task))
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
            HStack(spacing: 8) {
                TextField("Search tasks...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    appliedSearch = searchText
                } label: {
                    Text("Search")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))
                }
                if !appliedSearch.isEmpty {
                    Button { searchText = ""; appliedSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $showTodayOnly) {
                    Label("Today", systemImage: "calendar.badge.clock")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(showTodayOnly ? .indigo : .gray)
            }

            HStack {
                DatePicker("From", selection: $pendingStartDate, displayedComponents: .date)
                DatePicker("To", selection: $pendingEndDate, displayedComponents: .date)
                Button {
                    startDate = pendingStartDate
                    endDate = pendingEndDate
                } label: {
                    Text("Apply")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .disabled(showTodayOnly)
            .opacity(showTodayOnly ? 0.4 : 1)
            
            Picker("Status", selection: $statusFilter) {
                ForEach(StatusFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

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
    var allTasks: [Task] = []
    var metricDays: Int = 30
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

    private func calculatePoints() -> (earned: Double, allocated: Double) {
        let refDate = task.date ?? Date()
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: refDate)
        let start = calendar.date(byAdding: .day, value: -metricDays, to: end) ?? end
        let habitTasks = allTasks.filter { $0.title == task.title && $0.repeatAgain != nil }
        var earned = 0.0, allocated = 0.0
        var day = start
        while day <= end {
            for t in habitTasks where calendar.isDate(t.date ?? .distantPast, inSameDayAs: day) {
                allocated += t.weight
                if t.completed { earned += t.effectiveWeight }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return (earned, allocated)
    }

    @ViewBuilder
    private var metricsStrip: some View {
        if task.repeatAgain != nil {
            let metrics = task.calculateMetrics(days: metricDays, allTasks: allTasks, referenceDate: task.date ?? Date())
            let points = calculatePoints()
            let rateColor: Color = metrics.completionColor == "green" ? .green : (metrics.completionColor == "orange" ? .orange : .red)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    metricBadge(label: "Score", value: metrics.formattedScore, color: .blue)
                    metricBadge(label: "Rate", value: metrics.formattedCompletionRate, color: rateColor)
                    metricBadge(label: "Points", value: "\(Int(points.earned))/\(Int(points.allocated))", color: .purple)
                    if metrics.currentStreak > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill").font(.caption2)
                            Text("\(metrics.currentStreak)").font(.caption2).fontWeight(.bold)
                        }
                        .foregroundColor(.orange)
                        .frame(width: 50, height: 28)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .frame(height: 28)
        }
    }

    private func metricBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.caption2).fontWeight(.bold).foregroundColor(color)
            Text(label).font(.system(size: 8)).foregroundColor(.secondary)
        }
        .frame(width: 50, height: 28)
        .background(color.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

            metricsStrip
            
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
                if let goal = task.goal {
                    Text(goal.name)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.teal)
                        .clipShape(Capsule())
                        .lineLimit(1)
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
        
        try? modelContext.save()
    }

    private func addElapsedTime(_ minutes: Double) {
        let currentElapsedTime = task.elapsedTime ?? 0.0
        let newElapsedTime = currentElapsedTime + minutes
        
        // Capture the current effective weight BEFORE making any changes
        let oldEffectiveWeight = task.effectiveWeight
        
        task.elapsedTime = newElapsedTime
        elapsedTimeMinutes = String(Int(newElapsedTime))
        
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
