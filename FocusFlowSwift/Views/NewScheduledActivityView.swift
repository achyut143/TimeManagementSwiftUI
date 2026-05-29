import SwiftUI
import SwiftData

struct NewScheduledActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Task.title) private var allTasks: [Task]

    @State private var activityName = ""
    @State private var dailyNotesKeyword = ""

    // Recurrence pattern
    @State private var recurrenceType: RecurrenceType = .daily
    @State private var selectedWeekdays: Set<Int> = []
    @State private var selectedMonthDays: Set<Int> = []
    @State private var selectedMonths: Set<Int> = []

    // Task attachment
    @State private var selectedTask: Task?
    @State private var taskTimeAmount: String = ""

    // Credit settings
    @State private var pointsThreshold: String = "15"
    @State private var timePerCredit: String = "0"
    @State private var maxOverdraftCredits: String = "2"
    
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
                    TextField("Daily Notes trigger keyword (optional)", text: $dailyNotesKeyword)
                        .textFieldStyle(.roundedBorder)
                    Text("Completing a time block in Daily Notes whose description contains this keyword earns credits. Leave blank to match by activity name.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                    Text(recurrenceType.resetDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                
                Section("Credit Settings") {
                    HStack {
                        Text("Points per credit")
                        Spacer()
                        TextField("15", text: $pointsThreshold)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("pts")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Time per credit")
                        Spacer()
                        TextField("0", text: $timePerCredit)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("min")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Max overdraft")
                        Spacer()
                        TextField("2", text: $maxOverdraftCredits)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("credits")
                            .foregroundColor(.secondary)
                    }
                    Text("Earn 1 credit for every N task points completed. Each credit = X min of this activity.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        !activityName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private func createActivity() {
        let timeAmount = Double(taskTimeAmount) ?? 0.0

        // Only set task attachment if both task and amount are provided
        let finalTaskId = (selectedTask != nil && timeAmount > 0) ? selectedTask?.id : nil
        let finalTimeAmount = finalTaskId != nil ? timeAmount : 0.0

        let threshold = Double(pointsThreshold) ?? 15.0
        let timeCreditValue = Double(timePerCredit) ?? 0.0
        let maxOverdraft = Int(maxOverdraftCredits) ?? 2

        let activity = ScheduledActivity(
            name: activityName,
            scheduledTimes: [],
            windowDuration: 600,
            isActive: true,
            recurrenceType: recurrenceType,
            selectedWeekdays: Array(selectedWeekdays),
            selectedMonthDays: Array(selectedMonthDays),
            selectedMonths: Array(selectedMonths),
            attachedTaskId: finalTaskId,
            taskTimeAmount: finalTimeAmount,
            pointsThreshold: threshold,
            timePerCredit: timeCreditValue,
            maxOverdraftCredits: maxOverdraft
        )
        activity.dailyNotesKeyword = dailyNotesKeyword.trimmingCharacters(in: .whitespaces)

        modelContext.insert(activity)

        do {
            try modelContext.save()
            print("✅ Created activity '\(activityName)' with \(recurrenceType.displayName) recurrence")
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
        .modelContainer(for: [ScheduledActivity.self, Task.self], inMemory: true)
}