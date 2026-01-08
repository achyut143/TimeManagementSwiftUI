import SwiftUI
import SwiftData

struct EditScheduledActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Reward.name) private var allRewards: [Reward]
    @Query(sort: \Task.title) private var allTasks: [Task]
    
    let activity: ScheduledActivity
    
    @State private var activityName = ""
    @State private var scheduledTimes: [Date] = []
    @State private var windowDuration: Double = 10 // minutes
    @State private var isActive = true
    @State private var showingTimePicker = false
    @State private var newTime = Date()
    @State private var isInitialLoad = true // Track if this is the initial load
    
    // Recurrence pattern
    @State private var recurrenceType: RecurrenceType = .daily
    @State private var selectedWeekdays: Set<Int> = []
    @State private var selectedMonthDays: Set<Int> = []
    @State private var selectedMonths: Set<Int> = []
    
    // Reward attachment
    @State private var selectedReward: Reward?
    @State private var rewardBurnAmount: String = ""
    @State private var rewardBurnType: RewardBurnType = .time
    
    // Task attachment
    @State private var selectedTask: Task?
    @State private var taskTimeAmount: String = ""
    
    // Get available tasks (non-completed tasks from today or future)
    var availableTasks: [Task] {
        let today = Calendar.current.startOfDay(for: Date())
        let filtered = allTasks.filter { task in
            // Filter by completion status
            guard !task.completed && !task.notCompleted else { return false }
            
            // Filter by date - only today or future tasks
            if let taskDate = task.date {
                return taskDate >= today
            }
            
            // Include tasks without dates (they might be ongoing/flexible tasks)
            return true
        }
        
        // Fix any duplicate UUIDs before returning
        Task.fixDuplicateUUIDs(in: filtered)
        
        return filtered
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Activity Details") {
                    TextField("Activity Name", text: $activityName)
                        .textFieldStyle(.roundedBorder)
                    
                    Toggle("Active", isOn: $isActive)
                }
                

                
                Section("Recurrence Pattern") {
                    Picker("Recurrence", selection: $recurrenceType) {
                        ForEach(RecurrenceType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }.tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: recurrenceType) { oldValue, newValue in
                        // Only clear selections if this is not the initial load
                        if !isInitialLoad {
                            selectedWeekdays.removeAll()
                            selectedMonthDays.removeAll()
                            selectedMonths.removeAll()
                        }
                    }
                    
                    Text(recurrenceType.resetDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Show appropriate selection UI based on recurrence type
                    switch recurrenceType {
                    case .daily:
                        EmptyView()
                    case .weekly:
                        weekdaySelectionView
                    case .monthly:
                        monthDaySelectionView
                    case .quarterly:
                        quarterlySelectionView
                    }
                }
                
                Section("Scheduled Times") {
                    ForEach(scheduledTimes.indices, id: \.self) { index in
                        HStack {
                            Text(scheduledTimes[index], style: .time)
                            Spacer()
                            Button("Remove") {
                                scheduledTimes.remove(at: index)
                            }
                            .foregroundColor(.red)
                        }
                    }
                    
                    Button {
                        showingTimePicker = true
                    } label: {
                        Label("Add Time", systemImage: "plus.circle")
                    }
                }
                
                Section("Window Duration") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Int(windowDuration)) minutes")
                            .font(.headline)
                        
                        Slider(value: $windowDuration, in: 1...60, step: 1)
                    }
                    .padding(.vertical, 8)
                }
                
                // Reward Attachment Section
                Section("Reward Attachment (Optional)") {
                    Picker("Select Reward", selection: $selectedReward) {
                        Text("None").tag(nil as Reward?)
                        ForEach(allRewards, id: \.id) { reward in
                            HStack {
                                Image(systemName: reward.type.icon)
                                Text(reward.name)
                                Spacer()
                                Text(reward.formattedAmount())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }.tag(reward as Reward?)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if selectedReward != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Burn Type", selection: $rewardBurnType) {
                                ForEach(RewardBurnType.allCases, id: \.self) { type in
                                    HStack {
                                        Image(systemName: type.icon)
                                        Text(type.displayName)
                                    }.tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            HStack {
                                TextField("Amount to burn", text: $rewardBurnAmount)
                                    .keyboardType(.decimalPad)
                                Text(rewardBurnType.unit)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let reward = selectedReward, !rewardBurnAmount.isEmpty, let burnAmount = Double(rewardBurnAmount) {
                                RewardBurnPreview(reward: reward, burnAmount: burnAmount, burnType: rewardBurnType)
                            }
                        }
                        
                        Text("This reward will be burned each time you use the activity during its window.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Task Attachment Section
                Section("Task Attachment (Optional)") {
                    Picker("Select Task", selection: $selectedTask) {
                        Text("None").tag(nil as Task?)
                        ForEach(availableTasks, id: \.id) { task in
                            VStack(alignment: .leading) {
                                Text(task.title)
                                    .font(.body)
                                if !task.taskDescription.isEmpty {
                                    Text(task.taskDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }.tag(task as Task?)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if selectedTask != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                TextField("Time to add (minutes)", text: $taskTimeAmount)
                                    .keyboardType(.decimalPad)
                                Text("min")
                                    .foregroundColor(.secondary)
                            }
                            
                            if let task = selectedTask, !taskTimeAmount.isEmpty, let timeAmount = Double(taskTimeAmount) {
                                TaskTimePreview(task: task, timeAmount: timeAmount)
                            }
                        }
                        
                        Text("This time will be added to the task's time spent each time you use the activity.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button {
                        saveChanges()
                    } label: {
                        Text("Save Changes")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .disabled(!isFormValid)
                }
            }
            .navigationTitle("Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingTimePicker) {
                TimePickerSheet(selectedTime: $newTime) {
                    scheduledTimes.append(newTime)
                    scheduledTimes.sort()
                    showingTimePicker = false
                }
            }
            .onAppear {
                loadActivityData()
            }
        }
    }
    
    private var weekdaySelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Select Days of Week:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("Selected: \(selectedWeekdays.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Debug info
            if !selectedWeekdays.isEmpty {
                Text("Selected: \(selectedWeekdays.sorted().map { Calendar.current.weekdaySymbols[$0 - 1] }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(1...7, id: \.self) { weekday in
                    let dayName = Calendar.current.weekdaySymbols[weekday - 1]
                    let isSelected = selectedWeekdays.contains(weekday)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isSelected {
                                selectedWeekdays.remove(weekday)
                            } else {
                                selectedWeekdays.insert(weekday)
                            }
                        }
                    } label: {
                        Text(dayName)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.blue : Color(.systemGray5))
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var monthDaySelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Select Days of Month:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("Selected: \(selectedMonthDays.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Selected days info
            if !selectedMonthDays.isEmpty {
                Text("Selected: \(selectedMonthDays.sorted().map(String.init).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(1...31, id: \.self) { day in
                    let isSelected = selectedMonthDays.contains(day)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isSelected {
                                selectedMonthDays.remove(day)
                            } else {
                                selectedMonthDays.insert(day)
                            }
                        }
                    } label: {
                        Text("\(day)")
                            .font(.caption)
                            .frame(width: 32, height: 32)
                            .background(isSelected ? Color.blue : Color(.systemGray5))
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var quarterlySelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Select Months:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("Selected: \(selectedMonths.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(1...12, id: \.self) { month in
                        let monthName = Calendar.current.monthSymbols[month - 1]
                        let isSelected = selectedMonths.contains(month)
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isSelected {
                                    selectedMonths.remove(month)
                                } else {
                                    selectedMonths.insert(month)
                                }
                            }
                        } label: {
                            Text(monthName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.blue : Color(.systemGray5))
                                .foregroundColor(isSelected ? .white : .primary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Select Days of Month:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("Selected: \(selectedMonthDays.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                    ForEach(1...31, id: \.self) { day in
                        let isSelected = selectedMonthDays.contains(day)
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isSelected {
                                    selectedMonthDays.remove(day)
                                } else {
                                    selectedMonthDays.insert(day)
                                }
                            }
                        } label: {
                            Text("\(day)")
                                .font(.caption)
                                .frame(width: 32, height: 32)
                                .background(isSelected ? Color.blue : Color(.systemGray5))
                                .foregroundColor(isSelected ? .white : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        guard !activityName.isEmpty && !scheduledTimes.isEmpty else { return false }
        
        switch recurrenceType {
        case .daily:
            return true
        case .weekly:
            return !selectedWeekdays.isEmpty
        case .monthly:
            return !selectedMonthDays.isEmpty
        case .quarterly:
            return !selectedMonths.isEmpty && !selectedMonthDays.isEmpty
        }
    }
    
    private func loadActivityData() {
        // Ensure migration before loading data
        activity.ensureMigration()
        
        activityName = activity.name
        scheduledTimes = activity.scheduledTimes
        windowDuration = activity.windowDuration / 60 // Convert seconds to minutes
        isActive = activity.isActive
        
        // Load recurrence pattern data
        recurrenceType = activity.effectiveRecurrenceType
        selectedWeekdays = Set(activity.selectedWeekdays)
        selectedMonthDays = Set(activity.selectedMonthDays)
        selectedMonths = Set(activity.selectedMonths)
        
        // Load reward attachment data
        if let rewardId = activity.attachedRewardId {
            selectedReward = allRewards.first { $0.id == rewardId }
        }
        rewardBurnAmount = activity.rewardBurnAmount > 0 ? String(activity.rewardBurnAmount) : ""
        rewardBurnType = activity.rewardBurnType ?? .time
        
        // Load task attachment data
        if let taskId = activity.attachedTaskId {
            selectedTask = allTasks.first { $0.id == taskId }
        }
        taskTimeAmount = activity.taskTimeAmount > 0 ? String(activity.taskTimeAmount) : ""
        
        // Mark that initial load is complete
        isInitialLoad = false
        
        print("✅ Loaded activity '\(activity.name)' with \(recurrenceType.displayName) recurrence")
        if let reward = selectedReward {
            print("🎁 Loaded attached reward '\(reward.name)' with burn amount: \(activity.rewardBurnAmount) \(activity.effectiveRewardBurnType.unit)")
        }
        if let task = selectedTask {
            print("📝 Loaded attached task '\(task.title)' with time amount: \(activity.taskTimeAmount) min")
        }
    }
    
    private func saveChanges() {
        activity.name = activityName
        activity.scheduledTimes = scheduledTimes
        activity.windowDuration = windowDuration * 60 // Convert minutes to seconds
        activity.isActive = isActive
        
        // Save recurrence pattern data
        activity.recurrenceType = recurrenceType
        activity.selectedWeekdays = Array(selectedWeekdays)
        activity.selectedMonthDays = Array(selectedMonthDays)
        activity.selectedMonths = Array(selectedMonths)
        
        // Save reward attachment data - only if both reward and amount are provided
        let burnAmount = Double(rewardBurnAmount) ?? 0.0
        if selectedReward != nil && burnAmount > 0 {
            activity.attachedRewardId = selectedReward?.id
            activity.rewardBurnAmount = burnAmount
            activity.rewardBurnType = rewardBurnType
        } else {
            activity.attachedRewardId = nil
            activity.rewardBurnAmount = 0.0
            activity.rewardBurnType = nil
        }
        
        // Save task attachment data - only if both task and amount are provided
        let timeAmount = Double(taskTimeAmount) ?? 0.0
        if selectedTask != nil && timeAmount > 0 {
            activity.attachedTaskId = selectedTask?.id
            activity.taskTimeAmount = timeAmount
        } else {
            activity.attachedTaskId = nil
            activity.taskTimeAmount = 0.0
        }
        
        print("💾 Saved activity '\(activityName)' with \(recurrenceType.displayName) recurrence")
        if activity.hasRewardAttachment {
            print("🎁 Saved attached reward '\(selectedReward?.name ?? "")' with burn amount: \(activity.rewardBurnAmount) \(activity.effectiveRewardBurnType.unit)")
        }
        if activity.hasTaskAttachment {
            print("📝 Saved attached task '\(selectedTask?.title ?? "")' with time amount: \(activity.taskTimeAmount) min")
        }
        
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    EditScheduledActivityView(
        activity: ScheduledActivity(
            name: "Instagram",
            scheduledTimes: [Date()],
            windowDuration: 600
        )
    )
    .modelContainer(for: [ScheduledActivity.self, Reward.self, Task.self], inMemory: true)
}