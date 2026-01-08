import SwiftUI
import SwiftData

struct NewScheduledActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Reward.name) private var allRewards: [Reward]
    @Query(sort: \Task.title) private var allTasks: [Task]
    
    @State private var activityName = ""
    @State private var scheduledTimes: [Date] = []
    @State private var windowDuration: Double = 10 // minutes
    @State private var showingTimePicker = false
    @State private var newTime = Date()
    
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
                        // Clear selections when changing recurrence type
                        selectedWeekdays.removeAll()
                        selectedMonthDays.removeAll()
                        selectedMonths.removeAll()
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
                        createActivity()
                    } label: {
                        Text("Create Activity")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .disabled(!isFormValid)
                }
            }
            .navigationTitle("New Activity")
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
                Text("Current: \(selectedWeekdays.sorted().map { Calendar.current.weekdaySymbols[$0 - 1] }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            
            // Debug weekday mapping
            Text("Weekday mapping: 1=\(Calendar.current.weekdaySymbols[0]), 2=\(Calendar.current.weekdaySymbols[1]), 3=\(Calendar.current.weekdaySymbols[2]), 4=\(Calendar.current.weekdaySymbols[3])")
                .font(.caption2)
                .foregroundColor(.gray)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(1...7, id: \.self) { weekday in
                    let dayName = Calendar.current.weekdaySymbols[weekday - 1]
                    let isSelected = selectedWeekdays.contains(weekday)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isSelected {
                                selectedWeekdays.remove(weekday)
                                print("🗓️ Removed weekday \(weekday) (\(dayName)). Current selection: \(selectedWeekdays)")
                            } else {
                                selectedWeekdays.insert(weekday)
                                print("🗓️ Added weekday \(weekday) (\(dayName)). Current selection: \(selectedWeekdays)")
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
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(1...31, id: \.self) { day in
                    let isSelected = selectedMonthDays.contains(day)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isSelected {
                                selectedMonthDays.remove(day)
                                print("📅 Removed month day \(day). Current selection: \(selectedMonthDays)")
                            } else {
                                selectedMonthDays.insert(day)
                                print("📅 Added month day \(day). Current selection: \(selectedMonthDays)")
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
                Text("Select Months:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
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
                Text("Select Days of Month:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
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
    
    private func createActivity() {
        let burnAmount = Double(rewardBurnAmount) ?? 0.0
        let timeAmount = Double(taskTimeAmount) ?? 0.0
        
        // Only set reward attachment if both reward and amount are provided
        let finalRewardId = (selectedReward != nil && burnAmount > 0) ? selectedReward?.id : nil
        let finalBurnAmount = finalRewardId != nil ? burnAmount : 0.0
        let finalBurnType = finalRewardId != nil ? rewardBurnType : nil
        
        // Only set task attachment if both task and amount are provided
        let finalTaskId = (selectedTask != nil && timeAmount > 0) ? selectedTask?.id : nil
        let finalTimeAmount = finalTaskId != nil ? timeAmount : 0.0
        
        let activity = ScheduledActivity(
            name: activityName,
            scheduledTimes: scheduledTimes,
            windowDuration: windowDuration * 60, // Convert minutes to seconds
            isActive: true,
            recurrenceType: recurrenceType,
            selectedWeekdays: Array(selectedWeekdays),
            selectedMonthDays: Array(selectedMonthDays),
            selectedMonths: Array(selectedMonths),
            attachedRewardId: finalRewardId,
            rewardBurnAmount: finalBurnAmount,
            rewardBurnType: finalBurnType,
            attachedTaskId: finalTaskId,
            taskTimeAmount: finalTimeAmount
        )
        
        modelContext.insert(activity)
        
        do {
            try modelContext.save()
            print("✅ Created activity '\(activityName)' with \(recurrenceType.displayName) recurrence")
            if finalRewardId != nil {
                print("🎁 Attached reward '\(selectedReward?.name ?? "")' with burn amount: \(finalBurnAmount) \(finalBurnType?.unit ?? "")")
            }
            if finalTaskId != nil {
                print("📝 Attached task '\(selectedTask?.title ?? "")' with time amount: \(finalTimeAmount) min")
            }
        } catch {
            print("❌ Error saving activity: \(error)")
        }
        
        dismiss()
    }
}

struct TimePickerSheet: View {
    @Binding var selectedTime: Date
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Select Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onSave()
                    }
                }
            }
        }
    }
}

struct RewardBurnPreview: View {
    let reward: Reward
    let burnAmount: Double
    let burnType: RewardBurnType
    
    private var pointsNeeded: Double {
        switch burnType {
        case .time:
            if reward.type == .timeReward, let rate = reward.conversionRate, rate > 0 {
                return burnAmount / rate
            } else {
                return burnAmount
            }
        case .money:
            if reward.type == .moneyReward, let rate = reward.conversionRate, rate > 0 {
                return burnAmount / rate
            } else {
                return burnAmount
            }
        case .points:
            return burnAmount
        }
    }
    
    private var canAfford: Bool {
        if reward.currentAmount >= pointsNeeded {
            return true
        } else if reward.allowOverdraft {
            return true
        } else {
            return false
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Preview:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if canAfford {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            HStack {
                Text("Will burn:")
                Spacer()
                Text("\(String(format: "%.1f", pointsNeeded)) pts")
                    .fontWeight(.semibold)
            }
            .font(.caption)
            
            HStack {
                Text("Available:")
                Spacer()
                Text(reward.formattedAmount())
                    .foregroundColor(canAfford ? .green : .red)
            }
            .font(.caption)
            
            if !canAfford && !reward.allowOverdraft {
                Text("⚠️ Not enough balance")
                    .font(.caption2)
                    .foregroundColor(.red)
            } else if !canAfford && reward.allowOverdraft {
                let shortfall = pointsNeeded - reward.currentAmount
                Text("⚠️ Will create \(String(format: "%.1f", shortfall)) pts overdraft")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct TaskTimePreview: View {
    let task: Task
    let timeAmount: Double
    
    private var currentTimeSpent: Double {
        task.timeSpent ?? 0.0
    }
    
    private var newTimeSpent: Double {
        currentTimeSpent + timeAmount
    }
    
    private var allocatedTime: Double {
        task.allocatedTimeInMinutes
    }
    
    private var completionPercentage: Double {
        guard allocatedTime > 0 else { return 0 }
        return min(newTimeSpent / allocatedTime, 1.0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Preview:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
            
            HStack {
                Text("Current time:")
                Spacer()
                Text(formatTime(currentTimeSpent))
                    .fontWeight(.medium)
            }
            .font(.caption)
            
            HStack {
                Text("Will add:")
                Spacer()
                Text(formatTime(timeAmount))
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
            .font(.caption)
            
            HStack {
                Text("New total:")
                Spacer()
                Text(formatTime(newTimeSpent))
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
            .font(.caption)
            
            if allocatedTime > 0 {
                HStack {
                    Text("Progress:")
                    Spacer()
                    Text("\(Int(completionPercentage * 100))%")
                        .fontWeight(.semibold)
                        .foregroundColor(completionPercentage >= 1.0 ? .green : .orange)
                }
                .font(.caption)
                
                if completionPercentage >= 1.0 {
                    Text("✅ Task will be complete!")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func formatTime(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(Int(minutes)) min"
        }
    }
}

#Preview {
    NewScheduledActivityView()
        .modelContainer(for: [ScheduledActivity.self, Reward.self, Task.self], inMemory: true)
}