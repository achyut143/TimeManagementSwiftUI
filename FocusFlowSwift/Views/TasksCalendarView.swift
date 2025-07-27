import SwiftUI
import SwiftData
import AVFoundation
import Foundation

struct TasksCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @State private var selectedDate = Date()
    @State private var currentTime = Date()
    @State private var timer: Timer?
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var editingTask: Task?
    @State private var showEditDialog = false
    @State private var taskInput = ""
    @State private var repeatDays = 0
    @State private var showNotesDialog = false
    @State private var notesTask: Task?
    @State private var showDeleteConfirmation = false
    @State private var taskToDelete: Task?
    @State private var showTaskActions = false
    @State private var selectedTaskForActions: Task?
    
    var body: some View {
        VStack(spacing: 0) {
            pointsIndicator
            taskCreationHeader
            dateHeader
            timelineView
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    NavigationLink(destination: TaskTableView()) {
                        Image(systemName: "list.bullet")
                    }
                    NavigationLink(destination: HabitDashboardView()) {
                        Image(systemName: "chart.bar")
                    }
                }
            }
        }
        .onAppear {
            startTimer()
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
                TaskActionsView(task: task)
                    .presentationDetents([.medium])
            }
        }
    }
    
    private var taskCreationHeader: some View {
        VStack(spacing: 12) {
            Text("Task Management")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Format: StartTime - EndTime - TaskName - Description")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                TextField("e.g., 9:00 - 10:00 - Meeting - Weekly sync", text: $taskInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        createTaskFromInput()
                    }
                
                Button("Add") {
                    createTaskFromInput()
                }
                .buttonStyle(.borderedProminent)
            }
            
            HStack {
                TextField("Repeat every _ days", value: $repeatDays, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var dateHeader: some View {
        VStack(spacing: 8) {
            Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
    
    private var timelineView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(timeSlots, id: \.self) { slot in
                        timeSlotView(slot: slot)
                    }
                }
                .overlay(currentTimeIndicator)
            }
            .onAppear {
                scrollToCurrentTime(proxy: proxy)
            }
        }
    }
    
    private func timeSlotView(slot: TimeSlot) -> some View {
        HStack(alignment: .top, spacing: 0) {
        Text(slot.minute == 0 ? slot.timeString : "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
                .padding(.trailing, 8)
            
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.05))
                    .frame(height: 10)
                
                GeometryReader { geometry in
                    ForEach(tasksForSlot(slot)) { task in
                        taskView(task: task, slot: slot, containerWidth: geometry.size.width)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 10)
        }
        .id("\(slot.hour)-\(slot.minute)")
    }
    
    private func taskView(task: Task, slot: TimeSlot, containerWidth: CGFloat) -> some View {
        let startMinutes = timeToMinutes(task.startTime)
        let endMinutes = timeToMinutes(task.endTime)
        let slotMinutes = slot.hour * 60 + slot.minute
        let isStartSlot = slotMinutes == startMinutes
        
        let overlappingTasks = getOverlappingTasks(for: task)
        let position = overlappingTasks.firstIndex(where: { $0.id == task.id }) ?? 0
        let totalOverlapping = overlappingTasks.count
        
        let taskWidth = totalOverlapping > 1 ? 1.0 / Double(totalOverlapping) : 1.0
        let leftOffset = totalOverlapping > 1 ? Double(position) / Double(totalOverlapping) : 0.0
        
        let duration = endMinutes > startMinutes ? endMinutes - startMinutes : (24 * 60 - startMinutes) + endMinutes
        let taskHeight = max(10.0, Double(duration) / 5.0 * 10.0)
        
        return VStack(alignment: .leading, spacing: 4) {
            if isStartSlot {
                HStack {
                    Text(task.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(Int(task.weight))")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(weightColor(task.weight), in: Circle())
                }
                
                Text("\(task.startTime) - \(task.endTime)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(isStartSlot ? 8 : 0)
        .background(taskBackgroundColor(task))
        .overlay(
            Rectangle()
                .stroke(isCurrentTask(task) ? Color.blue : Color.clear, lineWidth: 2)
        )
        .frame(width: containerWidth * taskWidth, height: isStartSlot ? max(40, taskHeight) : 10)
        .offset(x: containerWidth * leftOffset)
        .draggable(task)
        .dropDestination(for: Task.self) { droppedTasks, location in
            guard let droppedTask = droppedTasks.first else { return false }
            updateTaskTime(droppedTask, to: slot)
            return true
        }
        .onTapGesture {
              selectedTaskForActions = task
            showTaskActions = true
           
        }
        .onLongPressGesture {
            if isCurrentTask(task) {
                speakTaskAlert(task)
            }
        }
    }
    
    private func taskActionButton(systemName: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
        }
    }
    
    private var currentTimeIndicator: some View {
        Rectangle()
            .fill(Color.red)
            .frame(height: 2)
            .offset(y: currentTimeOffset)
            .opacity(Calendar.current.isDate(selectedDate, inSameDayAs: Date()) ? 1 : 0)
    }
    
    private var timeSlots: [TimeSlot] {
        var slots: [TimeSlot] = []
        for hour in 0..<24 {
            for minute in stride(from: 0, to: 60, by: 5) {
                slots.append(TimeSlot(hour: hour, minute: minute))
            }
        }
        return slots
    }
    




    private var currentTimeOffset: CGFloat {
        let hour = Calendar.current.component(.hour, from: currentTime)
        let minute = Calendar.current.component(.minute, from: currentTime)
    
    // Convert to 12-hour format where 12 PM = 0
    let adjustedHour: Int
    if hour == 0 {
        adjustedHour = -12  // 12 AM = -12
    } else if hour <= 12 {
        adjustedHour = hour - 12  // 1 AM = -11, 2 AM = -10, ..., 12 PM = 0
    } else {
        adjustedHour = hour - 12  // 1 PM = 1, 2 PM = 2, ..., 11 PM = 11
    }
    
    // Calculate offset: each hour = 180 units, plus proportional minutes
    let hourOffset = CGFloat(adjustedHour) * 170
    let minuteOffset = CGFloat(minute) * (170.0 / 60.0)  // 3 units per minute
    
    return hourOffset + minuteOffset
}

    private func tasksForSlot(_ slot: TimeSlot) -> [Task] {
        let filteredTasks = tasks.filter { task in
            guard let taskDate = task.date else { return false }
            guard Calendar.current.isDate(taskDate, inSameDayAs: selectedDate) else { return false }
            
            let startMinutes = timeToMinutes(task.startTime)
            let endMinutes = timeToMinutes(task.endTime)
            let slotMinutes = slot.hour * 60 + slot.minute
            
            return slotMinutes == startMinutes
        }
        
        return filteredTasks.sorted { task1, task2 in
            let start1 = timeToMinutes(task1.startTime)
            let start2 = timeToMinutes(task2.startTime)
            if start1 == start2 {
                return task1.title < task2.title
            }
            return start1 < start2
        }
    }
    
    private func getOverlappingTasks(for task: Task) -> [Task] {
        let taskStart = timeToMinutes(task.startTime)
        let taskEnd = timeToMinutes(task.endTime)
        
        return tasks.filter { t in
            guard let taskDate = t.date else { return false }
            guard Calendar.current.isDate(taskDate, inSameDayAs: selectedDate) else { return false }
            
            let tStart = timeToMinutes(t.startTime)
            let tEnd = timeToMinutes(t.endTime)
            
            return (tStart < taskEnd && tEnd > taskStart)
        }.sorted { t1, t2 in
            let start1 = timeToMinutes(t1.startTime)
            let start2 = timeToMinutes(t2.startTime)
            if start1 == start2 {
                return t1.title < t2.title
            }
            return start1 < start2
        }
    }
    
    private func timeToMinutes(_ timeStr: String) -> Int {
        let components = timeStr.components(separatedBy: ":")
        guard components.count >= 2,
              let hours = Int(components[0]),
              let minutes = Int(components[1]) else { return 0 }
        return hours * 60 + minutes
    }
    
    private func isCurrentTask(_ task: Task) -> Bool {
        guard Calendar.current.isDate(selectedDate, inSameDayAs: Date()) else { return false }
        let now = Calendar.current.dateComponents([.hour, .minute], from: currentTime)
        let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let startMinutes = timeToMinutes(task.startTime)
        let endMinutes = timeToMinutes(task.endTime)
        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }
    
    private func taskBackgroundColor(_ task: Task) -> Color {
        if task.completed { return .green.opacity(0.3) }
        if task.notCompleted { return .red.opacity(0.3) }
        if task.five { return .blue.opacity(0.3) }
        return .gray.opacity(0.2)
    }
    
    private func weightColor(_ weight: Double) -> Color {
        if weight > 7 { return .red }
        if weight > 4 { return .orange }
        return .blue
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            currentTime = Date()
            checkTaskAlerts()
        }
    }
    
    private func scrollToCurrentTime(proxy: ScrollViewProxy) {
        let currentHour = Calendar.current.component(.hour, from: Date())
        withAnimation {
            proxy.scrollTo(currentHour, anchor: .center)
        }
    }
    
    private func checkTaskAlerts() {
        guard Calendar.current.isDate(selectedDate, inSameDayAs: Date()) else { return }
        
        let now = Calendar.current.dateComponents([.hour, .minute], from: currentTime)
        let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        
        for task in tasks {
            let startMinutes = timeToMinutes(task.startTime)
            let endMinutes = timeToMinutes(task.endTime)
            
            if currentMinutes == startMinutes {
                speakText("Time to start: \(task.title)")
                NotificationManager.shared.scheduleTaskStartNotification(task: task)
            } else if currentMinutes == endMinutes {
                speakText("Time to end: \(task.title)")
                NotificationManager.shared.scheduleTaskEndNotification(task: task)
            }
        }
    }
    
    private func speakTaskAlert(_ task: Task) {
        speakText("Current task: \(task.title), from \(task.startTime) to \(task.endTime)")
    }
    
    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        speechSynthesizer.speak(utterance)
    }
    
    private func toggleTaskCompletion(_ task: Task) {
        task.completed.toggle()
        if task.completed {
            speakText("Task completed: \(task.title)")
            NotificationManager.shared.scheduleTaskCompletedNotification(task: task)
            createRepeatTask(from: task)
        }
        try? modelContext.save()
    }
    
    private func toggleTaskNonCompletion(_ task: Task) {
        task.notCompleted.toggle()
        if task.notCompleted {
            speakText("Task marked as not completed: \(task.title)")
            NotificationManager.shared.scheduleTaskNotCompletedNotification(task: task)
            createRepeatTask(from: task)
        }
        try? modelContext.save()
    }
    
    private func deleteTask(_ task: Task) {
        modelContext.delete(task)
        try? modelContext.save()
    }
    
    private func createTaskFromInput() {
        guard !taskInput.isEmpty else { return }
        
        let components = taskInput.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        
        if components.count >= 4 {
            let startTime = String(components[0])
            let endTime = String(components[1])
            let title = String(components[2])
            let description = String(components[3])
            let weight = components.count > 4 ? Double(components[4]) ?? 1.0 : 1.0
            
            let task = Task(
                title: title,
                taskDescription: description,
                startTime: startTime,
                endTime: endTime,
                weight: weight,
                date: selectedDate,
                repeatAgain: repeatDays > 0 ? repeatDays : nil
            )
            
            modelContext.insert(task)
        }
        try? modelContext.save()
        taskInput = ""
        repeatDays = 0
    }
    
    private func createRepeatTask(from task: Task) {
        guard let repeatDays = task.repeatAgain, let currentDate = task.date else { return }
        
        let nextDate = Calendar.current.date(byAdding: .day, value: repeatDays, to: currentDate) ?? currentDate
        
        let newTask = Task(
            title: task.title,
            taskDescription: task.taskDescription,
            startTime: task.startTime,
            endTime: task.endTime,
            weight: task.weight,
            date: nextDate,
            repeatAgain: task.repeatAgain
        )
        
        modelContext.insert(newTask)
    }
    
    private func updateTaskTime(_ task: Task, to slot: TimeSlot) {
        let startMinutes = slot.hour * 60 + slot.minute
        let endMinutes = startMinutes + 60
        
        let startHour = startMinutes / 60
        let startMin = startMinutes % 60
        let endHour = endMinutes / 60
        let endMin = endMinutes % 60
        
        task.startTime = String(format: "%d:%02d", startHour, startMin)
        task.endTime = String(format: "%d:%02d", endHour, endMin)
        task.date = selectedDate
        
        try? modelContext.save()
    }
    
    private var pointsIndicator: some View {
        let todayTasks = tasks.filter { task in
            guard let taskDate = task.date else { return false }
            return Calendar.current.isDate(taskDate, inSameDayAs: selectedDate)
        }
        
        let totalPoints = todayTasks.reduce(0) { $0 + $1.weight }
        let completedPoints = todayTasks.filter { $0.completed }.reduce(0) { $0 + $1.weight }
        let percentage = totalPoints > 0 ? (completedPoints / totalPoints) * 100 : 0
        
        return VStack(spacing: 4) {
            HStack {
                Text("Points: \(Int(completedPoints))/\(Int(totalPoints))")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text("(\(Int(percentage))%)")
                    .font(.subheadline)
            }
            .foregroundColor(pointsColor(percentage))
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
    
    private func pointsColor(_ percentage: Double) -> Color {
        if percentage >= 80 { return .green }
        if percentage >= 50 { return .orange }
        return .red
    }
}

struct TimeSlot: Hashable {
    let hour: Int
    let minute: Int
    
    var timeString: String {
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let period = hour >= 12 ? "PM" : "AM"
        return minute == 0 ? "\(displayHour):00 \(period)" : "\(displayHour):\(String(format: "%02d", minute))"
    }
    
    var isCurrentTime: Bool {
        let now = Date()
        let currentHour = Calendar.current.component(.hour, from: now)
        let currentMinute = Calendar.current.component(.minute, from: now)
        return currentHour == hour && currentMinute == minute
    }
}

struct EditTaskView: View {
    let task: Task
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var title: String
    @State private var description: String
    @State private var startTime: String
    @State private var endTime: String
    @State private var weight: Double
    
    init(task: Task) {
        self.task = task
        _title = State(initialValue: task.title)
        _description = State(initialValue: task.taskDescription)
        _startTime = State(initialValue: task.startTime)
        _endTime = State(initialValue: task.endTime)
        _weight = State(initialValue: task.weight)
    }
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $description)
                TextField("Start Time", text: $startTime)
                TextField("End Time", text: $endTime)
                
                HStack {
                    Text("Weight")
                    Slider(value: $weight, in: 1...10, step: 1)
                    Text("\(Int(weight))")
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTask()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveTask() {
        task.title = title
        task.taskDescription = description
        task.startTime = startTime
        task.endTime = endTime
        task.weight = weight
        try? modelContext.save()
    }
}

#Preview {
    TasksCalendarView()
        .modelContainer(for: [Task.self], inMemory: true)
}
struct NotesView: View {
    let task: Task
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var notes: String
    
    init(task: Task) {
        self.task = task
        _notes = State(initialValue: task.notes ?? "")
    }
    
    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $notes)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding()
            }
            .navigationTitle("Notes: \(task.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        task.notes = notes.isEmpty ? nil : notes
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TaskActionsView: View {
    let task: Task
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false
    @State private var showEditDialog = false
    @State private var showNotesDialog = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text(task.title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("\(task.startTime) - \(task.endTime)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 16) {
                actionButton("Complete", systemImage: "checkmark.circle", color: task.completed ? .green : .gray) {
                    toggleTaskCompletion()
                }
                
                actionButton("Mark Not Completed", systemImage: "xmark.circle", color: task.notCompleted ? .red : .gray) {
                    toggleTaskNonCompletion()
                }
                
                actionButton("Edit", systemImage: "pencil", color: .blue) {
                    showEditDialog = true
                }
                
                actionButton("Notes", systemImage: "note.text", color: .orange) {
                    showNotesDialog = true
                }
                
                actionButton("Delete", systemImage: "trash", color: .red) {
                    showDeleteConfirmation = true
                }
            }
            
            Spacer()
        }
        .padding()
        .alert("Delete Task", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTask()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this task?")
        }
        .sheet(isPresented: $showEditDialog) {
            EditTaskView(task: task)
        }
        .sheet(isPresented: $showNotesDialog) {
            NotesView(task: task)
        }
    }
    
    private func actionButton(_ title: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(10)
        }
    }
    
    private func toggleTaskCompletion() {
        task.completed.toggle()
        try? modelContext.save()
        dismiss()
    }
    
    private func toggleTaskNonCompletion() {
        task.notCompleted.toggle()
        try? modelContext.save()
        dismiss()
    }
    
    private func deleteTask() {
        modelContext.delete(task)
        try? modelContext.save()
    }
}