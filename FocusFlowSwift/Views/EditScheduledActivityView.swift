import SwiftUI
import SwiftData

struct EditScheduledActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Task.title) private var allTasks: [Task]

    let activity: ScheduledActivity

    @State private var activityName = ""
    @State private var dailyNotesKeyword = ""
    @State private var isActive = true
    @State private var isInitialLoad = true // Track if this is the initial load

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
                        Text("pts").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Time per credit")
                        Spacer()
                        TextField("0", text: $timePerCredit)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("min").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Max overdraft")
                        Spacer()
                        TextField("2", text: $maxOverdraftCredits)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("credits").foregroundColor(.secondary)
                    }
                    Text("Earn 1 credit for every N task points completed. Each credit = X min of this activity.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        !activityName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private func loadActivityData() {
        // Ensure migration before loading data
        activity.ensureMigration()
        
        activityName = activity.name
        dailyNotesKeyword = activity.dailyNotesKeyword
        isActive = activity.isActive
        
        // Load recurrence pattern data
        recurrenceType = activity.effectiveRecurrenceType
        selectedWeekdays = Set(activity.selectedWeekdays)
        selectedMonthDays = Set(activity.selectedMonthDays)
        selectedMonths = Set(activity.selectedMonths)
        
        // Load task attachment data
        if let taskId = activity.attachedTaskId {
            selectedTask = allTasks.first { $0.id == taskId }
        }
        taskTimeAmount = activity.taskTimeAmount > 0 ? String(activity.taskTimeAmount) : ""

        // Load credit settings
        pointsThreshold = String(activity.pointsThreshold)
        timePerCredit = String(activity.timePerCredit)
        maxOverdraftCredits = String(activity.maxOverdraftCredits)

        // Mark that initial load is complete
        isInitialLoad = false

        print("✅ Loaded activity '\(activity.name)' with \(recurrenceType.displayName) recurrence")
        if let task = selectedTask {
            print("📝 Loaded attached task '\(task.title)' with time amount: \(activity.taskTimeAmount) min")
        }
    }
    
    private func saveChanges() {
        activity.name = activityName
        activity.dailyNotesKeyword = dailyNotesKeyword.trimmingCharacters(in: .whitespaces)
        activity.isActive = isActive
        
        // Save recurrence pattern data
        activity.recurrenceType = recurrenceType
        activity.selectedWeekdays = Array(selectedWeekdays)
        activity.selectedMonthDays = Array(selectedMonthDays)
        activity.selectedMonths = Array(selectedMonths)
        
        // Save task attachment data - only if both task and amount are provided
        let timeAmount = Double(taskTimeAmount) ?? 0.0
        if selectedTask != nil && timeAmount > 0 {
            activity.attachedTaskId = selectedTask?.id
            activity.taskTimeAmount = timeAmount
        } else {
            activity.attachedTaskId = nil
            activity.taskTimeAmount = 0.0
        }

        // Save credit settings
        activity.pointsThreshold = Double(pointsThreshold) ?? 15.0
        activity.timePerCredit = Double(timePerCredit) ?? 0.0
        activity.maxOverdraftCredits = Int(maxOverdraftCredits) ?? 2

        print("💾 Saved activity '\(activityName)' with \(recurrenceType.displayName) recurrence")
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
    .modelContainer(for: [ScheduledActivity.self, Task.self], inMemory: true)
}