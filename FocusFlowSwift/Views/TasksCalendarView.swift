import SwiftUI
import SwiftData
import AVFoundation
import Foundation
import UniformTypeIdentifiers
import QuickLook
import PhotosUI
import CoreTransferable

/// Lightweight drag payload carrying just a task's id. `Task.transferRepresentation`
/// only exports its title (for dragging text out of the app), so it can't be
/// reconstructed on drop — this round-trips the id instead so the drop handler can
/// look up the actual persisted `Task` in `modelContext`.
struct TaskDragPayload: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { $0.id.uuidString },
            importing: { TaskDragPayload(id: UUID(uuidString: $0) ?? UUID()) }
        )
    }
}

struct TasksCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedDate: Date
    var onOpenFocusMode: () -> Void = {}
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @State private var showTaskTable = false
    @State private var tasks: [Task] = []
    @State private var allTasks: [Task] = [] // For metrics calculation
    @State private var currentTime = Date()
    /// Where each 5-minute row actually sits in the timeline, so the red
    /// now-line lines up with the real rows (their heights vary).
    @State private var slotFrames: [Int: CGRect] = [:]
    @State private var timer: Timer?
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var editingTask: Task?
    @State private var showEditDialog = false
    @State private var taskInput = ""
    @State private var taskTitle = ""
    @State private var taskTags = ""
    @State private var startTime = roundToNearestFiveMinutes(Date())
    @State private var endTime = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
    @State private var taskDurationMinutes = 15
    @State private var repeatDays = 0
    @State private var repeatDraft = RepeatDraft()
    @State private var taskWeight = 1.0
    @State private var taskPriority = "P3"
    @State private var isUntimedTask = false
    @State private var copySubtasks = false
    @State private var showNotesDialog = false
    @State private var notesTask: Task?
    @State private var showDeleteConfirmation = false
    @State private var taskToDelete: Task?
    @State private var showTaskActions = false
    @State private var selectedTaskForActions: Task?
    @State private var showTaskCreation = false
    @State private var showQuickTaskInput = true
    @State private var quickTaskInput = ""
    @State private var showUntimedTasks = false
    @State private var showMarkAllNotCompletedConfirmation = false
    @State private var showBulkMoveTasks = false
    @State private var isUntimedDropTargeted = false
    // Driven by FocusTimerIndicatorView.onPendingChange — a full-width
    // acknowledge banner (matching Focus Mode's own) shown in place of the
    // compact pill while a Start/End, Begin/Stop, or calendar task
    // occurrence is awaiting acknowledgment.
    @State private var focusAckPending = false
    @State private var focusAckName = ""
    @State private var focusAckColor: Color = .indigo
    @State private var focusAckAction: () -> Void = {}
    @State private var showBacklogDrawer = false
    @State private var showBacklogScreen = false
    @State private var showBacklogPicker = false
    @State private var backlogSourceTask: Task?
    @AppStorage("metricDays") private var metricDays: Int = 30 // Use AppStorage for cross-view sync
    @AppStorage("habitPercentageFilter") private var percentageFilter: String = "all"
    @Query(sort: \Goal.name) private var goals: [Goal]
    @AppStorage(TaskGoalFilter.storageKey) private var goalFilterRaw: String = ""
    @Query private var allSubtasks: [Subtask]
    @State private var selectedGoalForNewTask: Goal?
    @Query(sort: \ImpulseType.sortOrder) private var impulseTypes: [ImpulseType]
    @State private var selectedImpulseTypeID: UUID?
    @State private var showPlannerSettings = false
    @State private var showPeriodGoals = false
    @State private var showPlannerMetrics = false
    @State private var showIfThenPlans = false
    @State private var showEventDayConfig = false
    @State private var showRoutineSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
        VStack(spacing: 0) {
            PointsIndicatorView(tasks: getAllTasksForDate())
                .overlay(alignment: .trailing) {
                    HStack(spacing: 12) {
                        selfEfficacyBadge
                        FocusTimerIndicatorView(onOpenFocusMode: onOpenFocusMode) { pending, name, color, action in
                            focusAckPending = pending
                            focusAckName = name
                            focusAckColor = color
                            focusAckAction = action
                        }
                    }
                    .padding(.trailing, 16)
                }

            if focusAckPending {
                Button(action: focusAckAction) {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                        Text("\(focusAckName) started — Tap to Acknowledge")
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(focusAckColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }

            HStack {
                Button(showTaskCreation ? "Close" : "Add Task") {
                    showTaskCreation.toggle()
                    if !showTaskCreation {
                        showQuickTaskInput = true // reset to Quick Task for next open
                        backlogSourceTask = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Toggle(showUntimedTasks ? "Timed" : "Untimed", isOn: $showUntimedTasks)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .onChange(of: showUntimedTasks) { _, _ in
                        updateQuery()
                    }
                    .dropDestination(for: TaskDragPayload.self) { payloads, _ in
                        guard let payload = payloads.first, let droppedTask = findTask(withID: payload.id) else { return false }
                        scheduleAsUntimed(droppedTask)
                        return true
                    } isTargeted: { targeted in
                        isUntimedDropTargeted = targeted
                    }
                    .overlay(
                        Capsule().stroke(Color.blue, lineWidth: isUntimedDropTargeted ? 2 : 0)
                    )

                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: selectedDate) { _, _ in
                        // Opening a day (today or later) adds its repeat tasks.
                        RepeatScheduler.fill(day: selectedDate, context: modelContext)
                        updateQuery()
                    }
                
                TaskGoalFilterMenu()
                    .buttonStyle(.bordered)
                    .onChange(of: goalFilterRaw) { _, _ in
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
            
            // Pinned above the calendar (not inside its scroll) — the
            // timeline auto-scrolls to the current time, which hid it.
            PlannerHeaderView(date: selectedDate)

            if showUntimedTasks {
                untimedTasksList
            } else {
                timelineView
            }
        }

            if showBacklogDrawer {
                BacklogView(
                    isDrawer: true,
                    isPresented: $showBacklogDrawer,
                    targetDate: selectedDate,
                    onSchedule: updateQuery,
                    onExpand: {
                        showBacklogDrawer = false
                        showBacklogScreen = true
                    }
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            } else {
                // Moved out of the toolbar — it was crowding out the
                // self-efficacy score in the nav bar. Bottom-leading keeps it
                // clear of the app's other floating buttons (bottom-trailing).
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showBacklogDrawer = true
                            }
                        } label: {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.indigo)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.leading, 20)
                        .padding(.bottom, 20)

                        Spacer()
                    }
                }
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showBacklogDrawer)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // One menu for every right-side action — separate icons overflow
            // into a system "…" that doesn't respond on narrower phones.
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showEventDayConfig = true
                    } label: {
                        Label("Event Day", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        showPeriodGoals = true
                    } label: {
                        Label("Goals", systemImage: "flag")
                    }
                    Button {
                        showIfThenPlans = true
                    } label: {
                        Label("If-then Plans", systemImage: "arrow.triangle.branch")
                    }
                    Button {
                        showPlannerMetrics = true
                    } label: {
                        Label("Planner Metrics", systemImage: "chart.bar.xaxis")
                    }
                    Button {
                        showPlannerSettings = true
                    } label: {
                        Label("Impulses & Sleep Settings", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        showRoutineSettings = true
                    } label: {
                        Label("Routine Reminder", systemImage: "figure.stand")
                    }
                    Divider()
                    Button {
                        showBulkMoveTasks = true
                    } label: {
                        Label("Move Tasks", systemImage: "clock.arrow.2.circlepath")
                    }
                    Button {
                        showTaskTable = true
                    } label: {
                        Label("Task Table", systemImage: "list.bullet")
                    }
                    Button(role: .destructive) {
                        showMarkAllNotCompletedConfirmation = true
                    } label: {
                        Label("Mark All Not Completed", systemImage: "xmark.circle")
                    }
                    Divider()
                    Button {
                        isDarkMode.toggle()
                    } label: {
                        Label(isDarkMode ? "Switch to Light" : "Switch to Dark",
                              systemImage: isDarkMode ? "sun.max.fill" : "moon.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showTaskTable) {
            TaskTableView()
        }
        .sheet(isPresented: $showBacklogScreen) {
            BacklogView(isDrawer: false, isPresented: $showBacklogScreen, targetDate: selectedDate, onSchedule: updateQuery)
        }
        .sheet(isPresented: $showPlannerSettings) {
            NavigationStack { PlannerSettingsView() }
        }
        .sheet(isPresented: $showPeriodGoals) {
            NavigationStack { PeriodGoalsView(date: selectedDate) }
        }
        .sheet(isPresented: $showPlannerMetrics) {
            NavigationStack { PlannerMetricsView() }
        }
        .sheet(isPresented: $showIfThenPlans) {
            IfThenPlansSheet()
        }
        .sheet(isPresented: $showEventDayConfig) {
            EventDayEditorSheet(selectedDate: selectedDate)
        }
        .sheet(isPresented: $showRoutineSettings) {
            NavigationStack { RoutineReminderSettingsView() }
        }
        .sheet(isPresented: $showBulkMoveTasks) {
            BulkMoveTasksView(selectedDate: selectedDate, tasks: tasks, isPresented: $showBulkMoveTasks) { ids, targetTime in
                bulkMoveTasks(ids: ids, to: targetTime)
            }
        }
        .onAppear {
            updateQuery()
            startTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TaskCreated"))) { _ in
            updateQuery()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TaskUpdated"))) { _ in
            updateQuery()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TasksSnoozed"))) { note in
            // Move start/end alerts to the snoozed times.
            guard let ids = note.object as? [UUID] else { return }
            let idSet = Set(ids)
            let all = (try? modelContext.fetch(FetchDescriptor<Task>())) ?? []
            for task in all where idSet.contains(task.id) {
                scheduleTaskNotifications(for: task)
            }
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
        .taskDeleteAlert(isPresented: $showDeleteConfirmation, task: taskToDelete) { _ in
            updateQuery()
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
        .sheet(isPresented: $showBacklogPicker) {
            BacklogPickerView { task in
                populateFromBacklog(task)
            }
        }

    }
    
    private var quickTaskInputView: some View {
        QuickTaskInputView(input: $quickTaskInput, onSubmit: { parsedTask in
            createQuickTask(from: parsedTask)
        }, onOpenFullForm: {
            showQuickTaskInput = false
        })
    }
    
    private var taskCreationHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: { showQuickTaskInput = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                        Text("Quick")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.indigo)
                }

                Text("Create New Task")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()
            }

            if let source = backlogSourceTask {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                    Text("From Backlog: \(source.title)")
                        .lineLimit(1)
                    Spacer()
                    Button {
                        backlogSourceTask = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.indigo)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.indigo.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Button {
                    showBacklogPicker = true
                } label: {
                    Label("Pick from Backlog", systemImage: "tray.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            }

            VStack(spacing: 8) {
                TextField("Task Title", text: $taskTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Tags (comma separated)", text: $taskTags)
                    .textFieldStyle(.roundedBorder)
                
                Toggle("Untimed Task", isOn: $isUntimedTask)
                    .padding(.horizontal)
                    .onAppear {
                        isUntimedTask = showUntimedTasks
                    }
                
                if !isUntimedTask {
                    HStack {
                        DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .onChange(of: startTime) { _, newValue in
                                startTime = roundToNearestFiveMinutes(newValue)
                                endTime = Calendar.current.date(byAdding: .minute, value: taskDurationMinutes, to: startTime) ?? startTime
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Duration (min)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("30", value: $taskDurationMinutes, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                .frame(width: 70)
                                .onChange(of: taskDurationMinutes) { _, newValue in
                                    // Don't clamp the live value while typing — e.g. typing
                                    // "30" passes through "3" first, and clamping that up to
                                    // 5 would stomp the digit before "0" ever gets typed. The
                                    // real 5-minute floor is enforced on save instead.
                                    endTime = Calendar.current.date(byAdding: .minute, value: max(newValue, 0), to: startTime) ?? startTime
                                }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Ends at")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(endTime.formatted(date: .omitted, time: .shortened))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }

                    TaskConflictWarning(date: selectedDate, start: startTime, end: endTime,
                                        excluding: backlogSourceTask?.id)
                }
                
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
                    
                    Button("Add") {
                        createTaskFromSeparateFields()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                RepeatSummaryButton(draft: $repeatDraft, taskDate: selectedDate)
                    .font(.caption)
                    .padding(.horizontal)
                    .onChange(of: repeatDraft) { _, d in repeatDays = d.repeatAgain }

                if repeatDays > 0 {
                    Toggle("Copy Subtasks on Repeat", isOn: $copySubtasks)
                        .padding(.horizontal)
                        .font(.caption)
                }

                if impulseTypes.contains(where: { !$0.isArchived }) {
                    HStack {
                        Text("Impulse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Impulse", selection: $selectedImpulseTypeID) {
                            Text("None (regular task)").tag(UUID?.none)
                            ForEach(impulseTypes.filter { !$0.isArchived }) { type in
                                Text(type.name).tag(Optional(type.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal)

                    if let warning = ImpulseRules.unplannedWarning(
                        typeID: selectedImpulseTypeID,
                        start: isUntimedTask ? nil : ImpulseRules.combine(day: selectedDate, time: startTime),
                        types: impulseTypes,
                        noImpulseDay: PlannerDay.fetch(for: selectedDate, context: modelContext)?.noImpulseDay ?? false
                    ) {
                        UnplannedImpulseWarning(text: warning)
                            .padding(.horizontal)
                    }
                }

                if !goals.isEmpty {
                    HStack {
                        Text("Goal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Goal", selection: $selectedGoalForNewTask) {
                            Text("None").tag(Optional<Goal>.none)
                            ForEach(goals) { goal in
                                Text(goal.name).tag(Optional(goal))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var untimedTasksList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(tasks.filter { passesPercentageFilter($0) }) { task in
                    untimedTaskRow(task: task)
                }
            }
            .padding()
        }
    }

    private func passesPercentageFilter(_ task: Task) -> Bool {
        guard percentageFilter != "all" else { return true }
        guard task.repeatAgain != nil else { return true }
        let metrics = task.calculateMetrics(days: metricDays, allTasks: allTasks, referenceDate: selectedDate)
        // completionRate is already 0-100
        return percentageFilter == "above" ? metrics.completionRate >= 85 : metrics.completionRate < 85
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

                if let goal = task.goal {
                    Text(goal.name)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.teal)
                        .clipShape(Capsule())
                        .lineLimit(1)
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
                    
                    if let timeSpent = task.timeSpent, timeSpent > 0 {
                        Text("\(Int(timeSpent))m")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.purple)
                            .clipShape(Capsule())
                    }
                    
                    if let rule = task.repeatRule {
                        HStack(spacing: 2) {
                            Image(systemName: "repeat")
                            Text(rule.badge)
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
                                task.reassign.toggle()
                                try? modelContext.save()
                            }
                    }
                    
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
        .overlay(alignment: .topTrailing) { impulseStatusBadge(task).padding(4) }
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var timelineView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(timeSlots, id: \.self) { slot in
                        timeSlotView(slot: slot)
                            .background {
                                GeometryReader { g in
                                    Color.clear.preference(
                                        key: TimelineSlotFramesKey.self,
                                        value: [slot.index: g.frame(in: .named("timeline"))]
                                    )
                                }
                            }
                    }
                }
                .coordinateSpace(name: "timeline")
                .onPreferenceChange(TimelineSlotFramesKey.self) { slotFrames = $0 }
                .overlay(alignment: .topLeading) { taskLayer }
                .overlay(alignment: .top) { currentTimeIndicator }
            }
            .onAppear {
                scrollToCurrentTime(proxy: proxy)
            }
        }
    }
    
    private func timeSlotView(slot: TimeSlot) -> some View {
        HStack(alignment: .top, spacing: 0) {
        Text(slot.minute == 0 ? slot.timeString : "")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 60, height: Self.slotHeight, alignment: .topTrailing)
                .padding(.trailing, 8)
                // Tasks never cover the time column, so tapping here always creates
                // a task at this row — even inside a longer task (2:15 in 1:00–3:00).
                .contentShape(Rectangle())
                .onTapGesture {
                    startTaskCreation(atHour: slot.hour, minute: slot.minute)
                }
            
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.05))
                    .frame(height: Self.slotHeight)
                    .overlay(alignment: .top) {
                        // Hour line, plus a faint one at each half hour.
                        if slot.minute == 0 || slot.minute == 30 {
                            Rectangle()
                                .fill(Color.gray.opacity(slot.minute == 0 ? 0.25 : 0.12))
                                .frame(height: 0.5)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        startTaskCreation(atHour: slot.hour, minute: slot.minute)
                    }
                    .dropDestination(for: TaskDragPayload.self) { payloads, _ in
                        guard let payload = payloads.first,
                              let droppedTask = findTask(withID: payload.id) else { return false }
                        updateTaskTime(droppedTask, to: slot)
                        return true
                    }
            }
            .frame(maxWidth: .infinity, minHeight: Self.slotHeight, maxHeight: Self.slotHeight, alignment: .topLeading)
        }
        .frame(height: Self.slotHeight)
        .id("\(slot.hour)-\(slot.minute)")
    }

    /// Width of the time labels on the left (label + its padding).
    private static let timeLabelWidth: CGFloat = 68

    /// All tasks, drawn in one layer above the rows at their real positions.
    /// Keeping them out of the rows means a later row can never sit on top of
    /// an earlier task, and side-by-side tasks each get their own tap area.
    private var taskLayer: some View {
        GeometryReader { g in
            let width = max(0, g.size.width - Self.timeLabelWidth)
            ForEach(timeSlots, id: \.self) { slot in
                ForEach(tasksForSlot(slot)) { task in
                    // Exact minute, so a task at 2:17 sits 2/5 into the 2:15 row.
                    let start = timeToMinutes(task.startTime)
                    taskView(task: task, slot: slot, containerWidth: width)
                        .padding(.leading, Self.timeLabelWidth)
                        .padding(.top, CGFloat(start) / 5 * Self.slotHeight)
                }
            }
        }
    }

    /// Height of one 5-minute row. Tasks are exactly `minutes / 5` rows tall.
    static let slotHeight: CGFloat = 18

    /// One-line (5 min) or two-line (10 min) layout for short tasks.
    @ViewBuilder
    private func compactTaskContent(_ task: Task, duration: Int) -> some View {
        let time = "\(formatTimeToAMPM(task.startTime)) – \(formatTimeToAMPM(task.endTime))"
        let title = HStack(spacing: 4) {
            if task.completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
            Text(task.title)
                .font(.system(size: 11, weight: .semibold))
                .strikethrough(task.completed)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        if duration <= 5 {
            HStack(spacing: 6) {
                title
                Spacer(minLength: 4)
                Text(time)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                title
                Text("\(time) · \(duration)m")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
    
   private func taskView(
  task: Task,
  slot: TimeSlot,
  containerWidth: CGFloat
) -> some View {
  let startMinutes = timeToMinutes(task.startTime)
  let endMinutes   = timeToMinutes(task.endTime)
  let slotMinutes  = slot.hour * 60 + slot.minute
  let isStartSlot  = slotMinutes == startMinutes - startMinutes % 5

  let column             = taskColumns()[task.id] ?? (column: 0, columns: 1)
  let taskWidth          = 1.0 / Double(column.columns)
  let leftOffset         = Double(column.column) / Double(column.columns)

  // Compute duration in minutes, wrapping past midnight if needed
  let duration = endMinutes > startMinutes
    ? endMinutes - startMinutes
    : (24 * 60 - startMinutes) + endMinutes

  // Compute taskHeight based on duration
  // Exactly as tall as the rows it covers, less a 1pt gap before the next task.
  let taskHeight = max(Self.slotHeight, CGFloat(duration) / 5 * Self.slotHeight) - 1
  let now = Calendar.current.dateComponents([.hour, .minute], from: currentTime)
  let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
  let isCurrentTaskToday = Calendar.current.isDate(selectedDate, inSameDayAs: Date()) && 
                          currentMinutes >= startMinutes && currentMinutes < endMinutes
  let remaining = isCurrentTaskToday ? max(0, endMinutes - currentMinutes) : 0

  return VStack(alignment: .leading, spacing: 4) {
    if isStartSlot && duration <= 10 {
      compactTaskContent(task, duration: duration)
    } else if isStartSlot {
      let metrics = task.repeatAgain != nil ? task.calculateMetrics(days: metricDays, allTasks: allTasks, referenceDate: selectedDate) : nil
      
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(task.title)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
          
          // Show metrics for repeat tasks
          if let metrics = metrics {
              let pointsStats = calculatePointsForTask(task)
              
              ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 2) {
                      // Score
                      Text(metrics.formattedScore)
                          .font(.system(size: 9))
                          .fontWeight(.bold)
                          .foregroundColor(.blue)
                          .padding(.horizontal, 4)
                          .padding(.vertical, 2)
                          .background(Color.blue.opacity(0.2))
                          .clipShape(Capsule())
                      
                      // Completion rate
                      Text(metrics.formattedCompletionRate)
                          .font(.system(size: 9))
                          .fontWeight(.bold)
                          .foregroundColor(metrics.completionColor == "green" ? .green : (metrics.completionColor == "orange" ? .orange : .red))
                          .padding(.horizontal, 4)
                          .padding(.vertical, 2)
                          .background(Color(metrics.completionColor == "green" ? .green : (metrics.completionColor == "orange" ? .orange : .red)).opacity(0.2))
                          .clipShape(Capsule())
                      
                      // Points
                      Text("\(Int(pointsStats.earned))/\(Int(pointsStats.allocated))")
                          .font(.system(size: 9))
                          .fontWeight(.bold)
                          .foregroundColor(.purple)
                          .padding(.horizontal, 4)
                          .padding(.vertical, 2)
                          .background(Color.purple.opacity(0.2))
                          .clipShape(Capsule())
                      
                      // Streak
                      if metrics.currentStreak > 0 {
                          HStack(spacing: 1) {
                              Image(systemName: "flame.fill")
                                  .font(.system(size: 9))
                              Text("\(metrics.currentStreak)")
                                  .font(.system(size: 9))
                                  .fontWeight(.bold)
                          }
                          .foregroundColor(.orange)
                          .padding(.horizontal, 4)
                          .padding(.vertical, 2)
                          .background(Color.orange.opacity(0.2))
                          .clipShape(Capsule())
                      }
                  }
              }
              .frame(height: 18)
          }
          
          Spacer()
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Text("\(formatTimeToAMPM(task.startTime)) - \(formatTimeToAMPM(task.endTime)) (\(duration)m)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                if isCurrentTaskToday && remaining > 0 {
                    Text("\(remaining)m left")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fontWeight(.medium)
                }
                Text(String(format: "%.1f", task.weight))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(weightColor(task.weight))
                    .clipShape(Capsule())
                
                Text(task.priority)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor(task.priority))
                    .clipShape(Capsule())
                
                if let timeSpent = task.timeSpent, timeSpent > 0 {
                    Text("\(Int(timeSpent))m")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.purple)
                        .clipShape(Capsule())
                }
                
                if let rule = task.repeatRule {
                    HStack(spacing: 2) {
                        Image(systemName: "repeat")
                        Text(rule.badge)
                    }
                    .font(.caption2)
                    .foregroundStyle(.blue)
                }
                
                if task.notes != nil && !task.notes!.isEmpty {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                
                if let attachments = task.attachments, !attachments.isEmpty {
                    HStack(spacing: 1) {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text("\(attachments.count)")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(.blue)
                            .clipShape(Capsule())
                    }
                }

                let taskSubtasks = allSubtasks.filter {
                    $0.parentTask?.persistentModelID == task.persistentModelID &&
                    $0.parentSubtask == nil
                }
                if !taskSubtasks.isEmpty {
                    let doneCount = taskSubtasks.filter { $0.completed }.count
                    HStack(spacing: 1) {
                        Image(systemName: doneCount == taskSubtasks.count ? "checkmark.circle.fill" : "list.bullet")
                            .font(.caption2)
                            .foregroundStyle(.white)
                        Text("\(doneCount)/\(taskSubtasks.count)")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(doneCount == taskSubtasks.count ? Color.green : Color.indigo)
                    .clipShape(Capsule())
                }

                if task.repeatAgain != nil {
                    Image(systemName: "repeat")
                        .font(.caption2)
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

                if let goal = task.goal {
                    Text(goal.name)
                        .font(.system(size: 8))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.teal)
                        .clipShape(Capsule())
                        .lineLimit(1)
                }
            }
        }
}//vstacn end
    }
  }
  .padding(.leading, 7)
  .padding(.trailing, 4)
  .padding(.vertical, duration <= 10 ? 0 : 3)
  .frame(maxWidth: .infinity, minHeight: taskHeight, maxHeight: taskHeight, alignment: .topLeading)
  .background(taskBackgroundColor(task))
  .overlay(alignment: .leading) {
    // Colored edge, like most calendar apps.
    Rectangle().fill(priorityColor(task.priority)).frame(width: 3)
  }
  .clipShape(RoundedRectangle(cornerRadius: 4))
  .overlay(impulseOverlay(task))
  .overlay(alignment: .topTrailing) { impulseStatusBadge(task) }
  .overlay(
    RoundedRectangle(cornerRadius: 4)
      .stroke(isCurrentTask(task) ? Color.blue : Color.clear, lineWidth: 2)
  )
  // Use taskHeight here
  .frame(
    width: containerWidth * taskWidth,
    // height: taskHeight
  )
  // Padding (not offset) so the tap area moves with the task.
  .contentShape(Rectangle())
  .padding(.leading, containerWidth * leftOffset)
  .draggable(TaskDragPayload(id: task.id))
  .dropDestination(for: TaskDragPayload.self) { payloads, _ in
    guard let payload = payloads.first,
          let droppedTask = findTask(withID: payload.id) else { return false }
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
    
    /// The red line at the current time. Redraws at the start of every minute and
    /// is placed inside the measured row for that time, so it stays exact even
    /// though rows with labels or tasks are taller than empty ones.
    private var currentTimeIndicator: some View {
        TimelineView(.everyMinute) { context in
            if Calendar.current.isDate(selectedDate, inSameDayAs: context.date),
               let y = nowLineY(at: context.date) {
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 2)
                    .overlay(alignment: .leading) {
                        Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: 64)
                    }
                    .offset(y: y - 1)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Y position of `date`'s clock time within the measured rows.
    private func nowLineY(at date: Date) -> CGFloat? {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let minutes = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
        let index = Int(minutes / 5)
        guard let frame = slotFrames[index] else { return nil }
        let fraction = (minutes - Double(index * 5)) / 5
        return frame.minY + frame.height * fraction
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
    




    private func tasksForSlot(_ slot: TimeSlot) -> [Task] {
        let slotMinutes = slot.hour * 60 + slot.minute
        let filteredTasks = tasks.filter { task in
            // Tasks starting between marks (e.g. 2:17 after a split) belong to
            // the 5-minute row they start in.
            let startMinutes = timeToMinutes(task.startTime)
            return slotMinutes == startMinutes - startMinutes % 5 && passesPercentageFilter(task)
        }
        return filteredTasks
    }
    
    private func updateQuery() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        print("Querying \(showUntimedTasks ? "untimed" : "timed") tasks between \(startOfDay) and \(endOfDay)")
        
        let descriptor = FetchDescriptor<Task>(
            sortBy: [SortDescriptor(\.startTime)]
        )
        
        do {
            allTasks = try modelContext.fetch(descriptor) // Load all tasks for metrics
            tasks = allTasks.filter { task in
                guard let taskDate = task.date else { return false }
                guard TaskGoalFilter.matches(task, raw: goalFilterRaw) else { return false }
                let isDateMatch = Calendar.current.isDate(taskDate, inSameDayAs: selectedDate)

                if showUntimedTasks {
                    // Show untimed tasks (tasks with empty start/end times)
                    return task.startTime.isEmpty && task.endTime.isEmpty && isDateMatch
                } else {
                    // Show timed tasks (tasks with start and end times)
                    return !task.startTime.isEmpty && !task.endTime.isEmpty && isDateMatch
                }
            }
            
            // Fix any duplicate UUIDs before displaying
            Task.fixDuplicateUUIDs(in: tasks)
            
            print("Fetched \(tasks.count) \(showUntimedTasks ? "untimed" : "timed") tasks for \(selectedDate)")
        } catch {
            print("Error fetching tasks: \(error)")
            tasks = []
            allTasks = []
        }
    }

    private var selfEfficacyPercentage: Int {
        // Excludes today — a still-in-progress day full of incomplete tasks
        // would otherwise drag the percentage down before there's been any
        // chance to complete them. Window is the metricDays days ending
        // yesterday.
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let cutoff = Calendar.current.date(byAdding: .day, value: -metricDays, to: startOfToday) ?? startOfToday
        let periodTasks = allTasks.filter { task in
            guard let date = task.date else { return false }
            return date >= cutoff && date < startOfToday
        }
        let total = periodTasks.reduce(0.0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        let earned = periodTasks.filter { $0.completed }.reduce(0.0) { $0 + $1.effectiveWeight }
        return min(Int((earned / total) * 100), 100)
    }

    private func selfEfficacyColor(_ pct: Int) -> Color {
        switch pct {
        case 80...: return .green
        case 60..<80: return .orange
        case 40..<60: return .yellow
        default: return .red
        }
    }

    private func calculatePointsForTask(_ task: Task) -> (earned: Double, allocated: Double) {
        guard task.repeatAgain != nil else {
            return (earned: 0, allocated: 0)
        }
        
        // Get all tasks with the same title (same habit)
        let habitTasks = allTasks.filter { $0.repeatAgain != nil && $0.isSameHabit(as: task) }
        
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
    
    private func getAllTasksForDate() -> [Task] {
        let descriptor = FetchDescriptor<Task>()
        
        do {
            let allTasks = try modelContext.fetch(descriptor)
            return allTasks.filter { task in
                guard let taskDate = task.date else { return false }
                return Calendar.current.isDate(taskDate, inSameDayAs: selectedDate)
            }
        } catch {
            print("Error fetching all tasks for date: \(error)")
            return []
        }
    }
    
    /// Side-by-side placement for overlapping tasks, like calendar apps:
    /// each task takes the first free column, and every task in a group of
    /// overlapping tasks shares that group's column count, so none sit on top
    /// of each other.
    private func taskColumns() -> [UUID: (column: Int, columns: Int)] {
        let timed = tasks
            .filter { !$0.startTime.isEmpty && !$0.endTime.isEmpty }
            .map { t -> (id: UUID, start: Int, end: Int) in
                let start = timeToMinutes(t.startTime)
                var end = timeToMinutes(t.endTime)
                if end <= start { end = 24 * 60 }   // runs past midnight
                return (t.id, start, end)
            }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }

        var result: [UUID: (column: Int, columns: Int)] = [:]
        var group: [(id: UUID, column: Int)] = []
        var columnEnds: [Int] = []   // when each column frees up, within the group
        var groupEnd = -1

        func closeGroup() {
            for item in group { result[item.id] = (item.column, max(1, columnEnds.count)) }
            group = []; columnEnds = []
        }

        for t in timed {
            if t.start >= groupEnd { closeGroup() }
            let column = columnEnds.firstIndex { $0 <= t.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(t.end) } else { columnEnds[column] = t.end }
            group.append((t.id, column))
            groupEnd = max(groupEnd, t.end)
        }
        closeGroup()
        return result
    }

    private func timeToMinutes(_ timeStr: String) -> Int {
        let cleanTimeStr = timeStr.trimmingCharacters(in: .whitespaces)
        let components = cleanTimeStr.components(separatedBy: ":")
        guard components.count >= 2,
              let hours = Int(components[0].trimmingCharacters(in: .whitespaces)),
              let minutes = Int(components[1].trimmingCharacters(in: .whitespaces)) else { return 0 }
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
    
    private func impulseType(of task: Task) -> ImpulseType? {
        guard let id = task.impulseTypeID else { return nil }
        return impulseTypes.first { $0.id == id }
    }

    private func isOnNoImpulseDay(_ task: Task) -> Bool {
        guard let date = task.date else { return false }
        return PlannerDay.fetch(for: date, context: modelContext)?.noImpulseDay ?? false
    }

    /// Planned impulse tasks are solid; unplanned ones are striped and outlined.
    @ViewBuilder
    private func impulseOverlay(_ task: Task) -> some View {
        if task.impulseTypeID != nil, !ImpulseRules.isPlannedLabel(task, noImpulseDay: isOnNoImpulseDay(task)) {
            let color = impulseType(of: task)?.color ?? .gray
            ZStack {
                StripeFill().stroke(color.opacity(0.45), lineWidth: 2).clipped()
                Rectangle().strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }
            .allowsHitTesting(false)
        }
    }

    /// Impulse blocks are colored by type, so their done / not-done state needs its own mark.
    @ViewBuilder
    private func impulseStatusBadge(_ task: Task) -> some View {
        if task.impulseTypeID != nil, task.completed || task.notCompleted {
            Image(systemName: task.completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, task.completed ? Color.green : Color.red)
                .padding(3)
                .allowsHitTesting(false)
        }
    }

    private func taskBackgroundColor(_ task: Task) -> Color {
        if let type = impulseType(of: task) {
            if ImpulseRules.isSkipped(task) { return type.color.opacity(0.15) }
            return ImpulseRules.isPlannedLabel(task, noImpulseDay: isOnNoImpulseDay(task)) ? type.color.opacity(0.75) : type.color.opacity(0.2)
        }
        if task.completed { return .green.opacity(0.3) }
        if task.notCompleted { return .red.opacity(0.3) }
        if (task.timeSpent ?? 0) > 0 { return .orange.opacity(0.3) }
        if task.five { return .blue.opacity(0.3) }
        return .gray.opacity(0.2)
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
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            currentTime = Date()
            checkTaskAlerts()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    // Moved here from the nav bar's .principal toolbar item — with the
    // bulk-move icon added to the trailing group, there wasn't enough room
    // left for the nav bar to keep showing this without covering/clipping it.
    private var selfEfficacyBadge: some View {
        let pct = selfEfficacyPercentage
        return VStack(spacing: 0) {
            Text("\(pct)%")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(selfEfficacyColor(pct))
            Text("\(metricDays)d")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func scrollToCurrentTime(proxy: ScrollViewProxy) {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let currentMinute = Calendar.current.component(.minute, from: Date())
        let roundedMinute = (currentMinute / 5) * 5
        
        withAnimation {
            proxy.scrollTo("\(currentHour)-\(roundedMinute)", anchor: .center)
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
            } else if currentMinutes == endMinutes {
                speakText("Time to end: \(task.title)")
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
        let wasCompleted = task.completed
        task.completed.toggle()
        print("📋 Task '\(task.title)' completion toggled in TasksCalendarView. Completed: \(task.completed), Weight: \(task.weight), EffectiveWeight: \(task.effectiveWeight)")
        
        if task.completed {
            speakText("Task completed: \(task.title)")
            NotificationManager.shared.scheduleTaskCompletedNotification(task: task)
            // Red repeat icon = next occurrence already handled (same rule
            // as the task actions sheet).
            if !task.reassign {
                createRepeatTask(from: task)
            }
        }
        try? modelContext.save()
    }

    private func toggleTaskNonCompletion(_ task: Task) {
        task.notCompleted.toggle()
        if task.notCompleted {
            speakText("Task marked as not completed: \(task.title)")
            NotificationManager.shared.scheduleTaskNotCompletedNotification(task: task)
            if !task.reassign {
                createRepeatTask(from: task)
            }
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
            
            if !task.isDailyRepeat {
                createIncompleteTask(from: task)
            }
        }
        
        try? modelContext.save()
        updateQuery()
    }
    
    private func startTaskCreation(atHour hour: Int, minute: Int) {
        let calendar = Calendar.current
        let tappedStart = selectedDate.atClock(hour: hour, minute: minute)

        startTime = tappedStart
        taskDurationMinutes = 15
        endTime = calendar.date(byAdding: .minute, value: taskDurationMinutes, to: tappedStart) ?? tappedStart
        isUntimedTask = false
        showQuickTaskInput = false
        showTaskCreation = true
        backlogSourceTask = nil
    }

    private func createTaskFromSeparateFields() {
        guard !taskTitle.isEmpty else { return }

        // Enforce the 5-minute floor here (on submit) rather than while the
        // user is still typing the duration — see the field's onChange for why.
        if !isUntimedTask {
            taskDurationMinutes = max(taskDurationMinutes, 5)
            endTime = Calendar.current.date(byAdding: .minute, value: taskDurationMinutes, to: startTime) ?? startTime
        }

        if let source = backlogSourceTask {
            // Schedule the same task in place, rather than creating a new
            // row and deleting the old one — anything the create form
            // doesn't surface (notes, subtasks, attachments,
            // whyStatement, timeSpent, ...) stays intact on this task.
            source.title = taskTitle
            source.taskDescription = taskTags
            source.weight = taskWeight
            source.priority = taskPriority
            RepeatRule.apply(repeatDraft.rule, to: source)
            source.copySubtasks = copySubtasks
            let before = ImpulseRules.Snapshot(source)
            source.goal = selectedGoalForNewTask
            source.date = selectedDate
            source.impulseTypeID = selectedImpulseTypeID

            if isUntimedTask {
                source.startTime = ""
                source.endTime = ""
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "H:mm"
                source.startTime = formatter.string(from: startTime)
                source.endTime = formatter.string(from: endTime)
                scheduleTaskNotifications(for: source)
            }
            ImpulseRules.reconcile(source, before: before, types: impulseTypes)

            do {
                try modelContext.save()
                updateQuery()
            } catch {
                print("Error saving task: \(error)")
            }
        } else {
            let task: Task

            if isUntimedTask {
                task = Task(
                    title: taskTitle,
                    taskDescription: taskTags,
                    startTime: "", // No start time for untimed tasks
                    endTime: "", // No end time for untimed tasks
                    weight: taskWeight,
                    date: selectedDate, // Keep the date
                    repeatAgain: repeatDays > 0 ? repeatDays : nil, // Allow repeat for untimed tasks
                    priority: taskPriority,
                    copySubtasks: copySubtasks
                )
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "H:mm"

                let startTimeString = formatter.string(from: startTime)
                let endTimeString = formatter.string(from: endTime)

                task = Task(
                    title: taskTitle,
                    taskDescription: taskTags,
                    startTime: startTimeString,
                    endTime: endTimeString,
                    weight: taskWeight,
                    date: selectedDate,
                    repeatAgain: repeatDays > 0 ? repeatDays : nil,
                    priority: taskPriority,
                    copySubtasks: copySubtasks
                )

                scheduleTaskNotifications(for: task)
            }

            RepeatRule.apply(repeatDraft.rule, to: task)
            task.goal = selectedGoalForNewTask
            task.impulseTypeID = selectedImpulseTypeID
            ImpulseRules.reconcile(task, before: nil, types: impulseTypes)
            modelContext.insert(task)

            do {
                try modelContext.save()
                updateQuery()
            } catch {
                print("Error saving task: \(error)")
            }
        }

        // Reset form
        taskTitle = ""
        taskTags = ""
        repeatDays = 0
        repeatDraft = RepeatDraft()
        taskWeight = 1.0
        taskPriority = "P3"
        isUntimedTask = false
        taskDurationMinutes = 15
        copySubtasks = false
        selectedGoalForNewTask = nil
        selectedImpulseTypeID = nil
        backlogSourceTask = nil

        // Close the create-task form now that the task has been saved —
        // same cleanup the "Close" button does, so reopening starts fresh.
        showTaskCreation = false
        showQuickTaskInput = true
    }

    private func populateFromBacklog(_ task: Task) {
        taskTitle = task.title
        taskTags = task.taskDescription
        taskWeight = task.weight
        taskPriority = task.priority
        selectedGoalForNewTask = task.goal
        if task.repeatAgain != nil {
            repeatDays = task.repeatAgain ?? 0
        }
        repeatDraft = RepeatDraft(task: task)
        backlogSourceTask = task
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
        
        // Schedule notifications only for timed tasks
        if !parsed.isUntimed {
            scheduleTaskNotifications(for: task)
        }
        
        do {
            try modelContext.save()
            updateQuery()
        } catch {
            print("Error saving quick task: \(error)")
        }
    }
    
    private func createTaskFromInput() {
        guard !taskInput.isEmpty else { return }
        
        let components = taskInput.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        print("Input components: \(components)")
        
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
            scheduleTaskNotifications(for: task)
            print("Created task: \(title) for date: \(selectedDate) at \(startTime)-\(endTime)")
            
            do {
                try modelContext.save()
                print("Task saved successfully")
                updateQuery()
            } catch {
                print("Error saving task: \(error)")
            }
        } else {
            print("Invalid input format. Need at least 4 components, got \(components.count)")
        }
        
        taskInput = ""
        repeatDays = 0
    }
    
    private func createRepeatTask(from task: Task) {
        TaskRepeater.createNextInstance(from: task, context: modelContext)
    }

    
    private func createIncompleteTask(from task: Task) {
        // Skipped impulses don't roll over — bringing one back should be a deliberate choice.
        guard task.impulseTypeID == nil else { return }
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
            elapsedTime: task.elapsedTime,
            copySubtasks: task.copySubtasks,
            whyStatement: task.whyStatement,
            whyStatementPinned: task.whyStatementPinned
        )
        task.copyRepeat(to: newTask)
        newTask.goal = task.goal
        ImpulseRules.inherit(from: task, to: newTask, context: modelContext)

        modelContext.insert(newTask)

        // Copy subtasks if the toggle is enabled
        if task.copySubtasks {
            SubtaskOrder.copyAll(from: task, to: newTask, context: modelContext)
        }

        try? modelContext.save()
    }

    private func findTask(withID id: UUID) -> Task? {
        tasks.first { $0.id == id } ?? allTasks.first { $0.id == id }
    }

    private func updateTaskTime(_ task: Task, to slot: TimeSlot) {
        let startMinutes = slot.hour * 60 + slot.minute

        // Preserve the task's original duration instead of resetting it to a fixed
        // length — except when it had no time at all yet (a backlog task, or an
        // untimed task being dragged onto the timeline for the first time), where
        // there's no prior duration to preserve, so give it a sensible default.
        let duration: Int
        if task.startTime.isEmpty || task.endTime.isEmpty {
            duration = 15
        } else {
            let originalStart = timeToMinutes(task.startTime)
            let originalEnd = timeToMinutes(task.endTime)
            duration = originalEnd > originalStart
                ? originalEnd - originalStart
                : (24 * 60 - originalStart) + originalEnd
        }
        let endMinutes = startMinutes + max(duration, 5)

        let startHour = startMinutes / 60
        let startMin = startMinutes % 60
        let wrappedEnd = endMinutes % (24 * 60)
        let endHour = wrappedEnd / 60
        let endMin = wrappedEnd % 60

        let before = ImpulseRules.Snapshot(task)
        task.startTime = String(format: "%d:%02d", startHour, startMin)
        task.endTime = String(format: "%d:%02d", endHour, endMin)
        task.date = selectedDate
        ImpulseRules.reconcile(task, before: before, types: impulseTypes)

        scheduleTaskNotifications(for: task)
        try? modelContext.save()
        updateQuery()
    }

    /// Drops a task (typically from the Backlog) onto the selected day as an
    /// untimed task, rather than a specific time slot.
    private func scheduleAsUntimed(_ task: Task) {
        let before = ImpulseRules.Snapshot(task)
        task.startTime = ""
        task.endTime = ""
        task.date = selectedDate
        ImpulseRules.reconcile(task, before: before, types: impulseTypes)
        try? modelContext.save()
        updateQuery()
    }

    /// Shifts every selected task by the same delta — the delta that puts
    /// the earliest-starting selected task at `targetTime` — so the whole
    /// group moves together while keeping its internal spacing. e.g. Task A
    /// 2:30 PM (30m) and Task B 4:30 PM (30m), both selected, moved to
    /// 4:30 PM: delta is +2h, so A -> 4:30 PM and B -> 6:30 PM (not packed
    /// back-to-back at 4:30/5:00).
    private func bulkMoveTasks(ids: [UUID], to targetTime: Date) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let selectedTasks = tasks.filter { idSet.contains($0.id) && !$0.startTime.isEmpty && !$0.endTime.isEmpty }
        guard let earliest = selectedTasks.min(by: { timeToMinutes($0.startTime) < timeToMinutes($1.startTime) }) else { return }

        let cal = Calendar.current
        let rawTargetMinutes = cal.component(.hour, from: targetTime) * 60 + cal.component(.minute, from: targetTime)
        let targetMinutes = (rawTargetMinutes / 5) * 5
        let delta = targetMinutes - timeToMinutes(earliest.startTime)
        guard delta != 0 else { return }

        // Same rules as Snooze: tasks starting within 10 min after a moved
        // task move too (and so on), and repeat tasks get their next
        // occurrence created at the original time first, then turn red.
        let moved = TaskMover.move(selectedTasks, by: delta, context: modelContext, impulseTypes: impulseTypes)
        for task in moved {
            scheduleTaskNotifications(for: task)
        }

        updateQuery()
    }

    private func scheduleTaskNotifications(for task: Task) {
        guard let taskDate = task.date else { return }
        
        let calendar = Calendar.current
        let startMinutes = timeToMinutes(task.startTime)
        let endMinutes = timeToMinutes(task.endTime)
        
        // Create start time components
        var startComponents = calendar.dateComponents([.year, .month, .day], from: taskDate)
        startComponents.hour = startMinutes / 60
        startComponents.minute = startMinutes % 60
        
        // Create end time components  
        var endComponents = calendar.dateComponents([.year, .month, .day], from: taskDate)
        endComponents.hour = endMinutes / 60
        endComponents.minute = endMinutes % 60
        
        if let startDateTime = calendar.date(from: startComponents), startDateTime > Date() {
            let startInterval = startDateTime.timeIntervalSinceNow
            NotificationManager.shared.scheduleNotification(
                title: "Task Starting",
                body: "Time to start: \(task.title)",
                identifier: "task-start-\(task.title)-\(taskDate.timeIntervalSince1970)",
                timeInterval: startInterval
            )
        }
        
        if let endDateTime = calendar.date(from: endComponents), endDateTime > Date() {
            let endInterval = endDateTime.timeIntervalSinceNow
            NotificationManager.shared.scheduleNotification(
                title: "Task Ending", 
                body: "Time to end: \(task.title)",
                identifier: "task-end-\(task.title)-\(taskDate.timeIntervalSince1970)",
                timeInterval: endInterval
            )
        }
    }
}


/// Frames of the timeline's 5-minute rows, keyed by `TimeSlot.index`.
struct TimelineSlotFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct TimeSlot: Hashable {
    let hour: Int
    let minute: Int

    /// 0 for 12:00 AM, 1 for 12:05 AM, … 287 for 11:55 PM.
    var index: Int { hour * 12 + minute / 5 }
    
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
    @Query(sort: \Goal.name) private var goals: [Goal]

    @State private var title: String
    @State private var description: String
    @State private var info: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var durationMinutes: Int
    @State private var weight: Double
    @State private var taskDate: Date?
    @State private var repeatDays: Int
    @State private var repeatDraft: RepeatDraft
    @State private var priority: String
    @State private var isUntimed: Bool
    @State private var timeSpent: Double
    @State private var elapsedTime: Double
    @State private var copySubtasks: Bool
    @State private var selectedGoal: Goal?
    @Query(sort: \ImpulseType.sortOrder) private var impulseTypes: [ImpulseType]
    @State private var impulseTypeID: UUID?
    @State private var hasActualEnd: Bool
    @State private var actualEnd: Date
    @State private var snoozeBy: Int?
    @State private var customSnooze = 20
    @State private var showCustomSnooze = false

    private var impulseWarning: String? {
        guard impulseTypeID != nil else { return nil }
        return ImpulseRules.unplannedWarning(
            existing: task,
            typeID: impulseTypeID,
            start: isUntimed ? nil : taskDate.map { ImpulseRules.combine(day: $0, time: startTime) },
            types: impulseTypes,
            noImpulseDay: taskDate.flatMap { PlannerDay.fetch(for: $0, context: modelContext)?.noImpulseDay } ?? false
        )
    }

    init(task: Task) {
        self.task = task
        _title = State(initialValue: task.title)
        _description = State(initialValue: task.taskDescription)
        _info = State(initialValue: task.info ?? "")
        _taskDate = State(initialValue: task.date)
        _isUntimed = State(initialValue: task.startTime.isEmpty && task.endTime.isEmpty)

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let initialStart = formatter.date(from: task.startTime) ?? Date()
        let initialEnd = formatter.date(from: task.endTime) ?? Date()
        _startTime = State(initialValue: initialStart)
        _endTime = State(initialValue: initialEnd)
        let existingDuration = Int(initialEnd.timeIntervalSince(initialStart) / 60)
        _durationMinutes = State(initialValue: existingDuration > 0 ? existingDuration : 15)
        _weight = State(initialValue: task.weight)
        _repeatDays = State(initialValue: task.repeatAgain ?? 0)
        _repeatDraft = State(initialValue: RepeatDraft(task: task))
        _priority = State(initialValue: task.priority)
        _timeSpent = State(initialValue: task.timeSpent ?? 0.0)
        _elapsedTime = State(initialValue: task.elapsedTime ?? 0.0)
        _copySubtasks = State(initialValue: task.copySubtasks)
        _selectedGoal = State(initialValue: task.goal)
        _impulseTypeID = State(initialValue: task.impulseTypeID)
        _hasActualEnd = State(initialValue: task.actualEndTime != nil)
        _actualEnd = State(initialValue: task.actualEndTime.flatMap { formatter.date(from: $0) } ?? initialEnd)
    }
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Title", text: $title)
                TextField("Description (tags, comma separated)", text: $description)
                Section("Info") {
                    TextField("Extra context for this task", text: $info, axis: .vertical)
                }

                Toggle("Untimed Task", isOn: $isUntimed)
                    .onChange(of: isUntimed) { _, newValue in
                        if !newValue && taskDate == nil {
                            taskDate = Date()
                        }
                    }
                
                DatePicker("Date", selection: Binding(
                    get: { taskDate ?? Date() },
                    set: { taskDate = $0 }
                ), displayedComponents: .date)
                
                if !isUntimed {
                    DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                        .onChange(of: startTime) { _, newValue in
                            startTime = roundToNearestFiveMinutes(newValue)
                            endTime = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startTime) ?? startTime
                        }

                    HStack {
                        Text("Duration (min)")
                        TextField("30", value: $durationMinutes, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                            .onChange(of: durationMinutes) { _, newValue in
                                // Don't clamp the live value while typing — e.g. typing "30"
                                // passes through "3" first, and clamping that up to 5 would
                                // stomp the digit before "0" ever gets typed. The real
                                // 5-minute floor is enforced on save instead.
                                endTime = Calendar.current.date(byAdding: .minute, value: max(newValue, 0), to: startTime) ?? startTime
                            }
                        Spacer()
                        Text("Ends at \(endTime.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TaskConflictWarning(date: taskDate ?? Date(), start: startTime, end: endTime,
                                        excluding: task.id)
                }
                
                if !isUntimed && !task.startTime.isEmpty && task.date != nil {
                    snoozeSection
                }

                if isUntimed {
                    HStack {
                        Text("Elapsed Time (minutes)")
                        TextField("0", value: $elapsedTime, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("(allocated)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack {
                    Text("Time Spent (minutes)")
                    TextField("0", value: $timeSpent, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    if !isUntimed {
                        Text("(optional)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("(actual)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack {
                    Text("Weight")
                    TextField("e.g. 5.5", value: $weight, format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                }
                
                RepeatSummaryButton(draft: $repeatDraft, taskDate: taskDate ?? Date())
                    .onChange(of: repeatDraft) { _, d in repeatDays = d.repeatAgain }
                
                if repeatDays > 0 {
                    Toggle("Copy Subtasks on Repeat", isOn: $copySubtasks)
                }

                HStack {
                    Text("Priority")
                    Picker("Priority", selection: $priority) {
                        Text("P1").tag("P1")
                        Text("P2").tag("P2")
                        Text("P3").tag("P3")
                        Text("P4").tag("P4")
                    }
                    .pickerStyle(.segmented)
                }

                if !impulseTypes.isEmpty {
                    Section {
                        Picker("Impulse type", selection: $impulseTypeID) {
                            Text("None (regular task)").tag(UUID?.none)
                            ForEach(impulseTypes.filter { !$0.isArchived || $0.id == impulseTypeID }) { type in
                                Text(type.name).tag(Optional(type.id))
                            }
                        }
                        .pickerStyle(.menu)
                        if let warning = impulseWarning {
                            UnplannedImpulseWarning(text: warning)
                        }
                        if impulseTypeID != nil && !isUntimed {
                            Toggle("Ran longer than planned", isOn: $hasActualEnd)
                            if hasActualEnd {
                                DatePicker("Actually ended", selection: $actualEnd, displayedComponents: .hourAndMinute)
                            }
                        }
                    } header: {
                        Text("Impulse")
                    } footer: {
                        if impulseTypeID != nil {
                            Text("Moving this earlier or changing its type re-checks planned status from now. Minutes past the planned end count as unplanned.")
                        }
                    }
                }

                Section("Goal") {
                    Picker("Goal", selection: $selectedGoal) {
                        Text("No Goal").tag(Optional<Goal>.none)
                        ForEach(goals) { goal in
                            Text(goal.name).tag(Optional(goal))
                        }
                    }
                    .pickerStyle(.menu)
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
    
    // MARK: Snooze

    private var snoozeSection: some View {
        let others = TaskMover.pushes(for: [task], startDelta: snoozeBy ?? 0, endDelta: snoozeBy ?? 0, context: modelContext)
        let repeats = ([task] + others.map(\.task)).filter { $0.repeatAgain != nil && !$0.reassign }

        return Section {
            HStack(spacing: 8) {
                ForEach([5, 10, 15], id: \.self) { mins in
                    snoozeChip("\(mins)m", selected: snoozeBy == mins && !showCustomSnooze) {
                        showCustomSnooze = false
                        snoozeBy = mins
                    }
                }
                snoozeChip("Custom", selected: showCustomSnooze) {
                    showCustomSnooze = true
                    snoozeBy = customSnooze
                }
            }

            if showCustomSnooze {
                Stepper("\(customSnooze) min", value: $customSnooze, in: 1...240)
                    .onChange(of: customSnooze) { _, v in snoozeBy = v }
            }

            if let mins = snoozeBy {
                if !others.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also moves \(others.count) following task\(others.count == 1 ? "" : "s"):")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(others, id: \.task.id) { p in
                            Text("• \(p.task.title)  \(p.task.startTime) → \(p.newStartTime)\(p.delta != mins ? " (+\(p.delta)m)" : "")")
                                .font(.caption)
                        }
                    }
                }

                Button {
                    applySnooze(by: mins)
                } label: {
                    Label("Snooze by \(mins) min", systemImage: "moon.zzz.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        } header: {
            Text("Snooze")
        } footer: {
            Text(snoozeFooter(repeatCount: repeats.count))
        }
    }

    private func snoozeFooter(repeatCount: Int) -> String {
        var text = "Pushes this task later. Tasks starting within \(TaskMover.followWindowMinutes) min after it move by the same amount; later tasks it would run into are pushed just enough to not overlap."
        if repeatCount > 0 {
            text += " Repeat tasks get their next day created first at the original time, and their repeat icon turns red so it isn't created again."
        }
        return text
    }

    private func snoozeChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.indigo : Color.indigo.opacity(0.12))
                )
                .foregroundStyle(selected ? Color.white : Color.indigo)
        }
        .buttonStyle(.plain)
    }

    /// Saves any edits in the form first, then moves the task and its chain.
    private func applySnooze(by mins: Int) {
        saveTask()
        let moved = TaskMover.snooze(task, by: mins, context: modelContext, impulseTypes: impulseTypes)
        NotificationCenter.default.post(name: NSNotification.Name("TasksSnoozed"), object: moved.map(\.id))
        NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
        dismiss()
    }

    private func saveTask() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        // Capture the old effective weight before making changes
        let oldEffectiveWeight = task.effectiveWeight
        // Repeat settings edited here carry on to this series' later copies.
        let repeatChanged = RepeatDraft(task: task) != repeatDraft
        let oldDate = task.date
        let impulseBefore = ImpulseRules.Snapshot(task)

        task.title = title
        task.taskDescription = description
        let trimmedInfo = info.trimmingCharacters(in: .whitespacesAndNewlines)
        task.info = trimmedInfo.isEmpty ? nil : trimmedInfo

        if isUntimed {
            task.startTime = ""
            task.endTime = ""
            task.date = taskDate // Keep the date for untimed tasks
            RepeatRule.apply(repeatDraft.rule, to: task) // Allow repeat for untimed tasks
            task.elapsedTime = elapsedTime > 0 ? elapsedTime : nil // Set elapsed time for untimed tasks
        } else {
            // Enforce the 5-minute floor here (on save) rather than while the
            // user is still typing the duration — see the field's onChange for why.
            durationMinutes = max(durationMinutes, 5)
            endTime = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startTime) ?? startTime
            task.startTime = formatter.string(from: startTime)
            task.endTime = formatter.string(from: endTime)
            task.date = taskDate
            RepeatRule.apply(repeatDraft.rule, to: task)
            task.elapsedTime = nil // Clear elapsed time for timed tasks
        }
        
        // Set timeSpent for both timed and untimed tasks
        task.timeSpent = timeSpent > 0 ? timeSpent : nil
        
        task.weight = weight
        task.priority = priority
        task.copySubtasks = copySubtasks
        if repeatChanged { RepeatSeries.applyRuleToFuture(from: task, context: modelContext) }
        // Moved to another day: the old day keeps counting as handled, so the
        // daily fill doesn't put a copy back there.
        if let oldDate, let newDate = task.date, !Calendar.current.isDate(oldDate, inSameDayAs: newDate) {
            RepeatScheduler.markFilled(task, on: oldDate)
        }
        task.goal = selectedGoal

        task.impulseTypeID = impulseTypeID
        if impulseTypeID != nil && !isUntimed && hasActualEnd {
            let actual = formatter.string(from: actualEnd)
            let start = ImpulseRules.minutes(from: task.startTime) ?? 0
            let overrun = ImpulseRules.span(from: start, to: ImpulseRules.minutes(from: actual) ?? start)
            task.actualEndTime = overrun > ImpulseRules.scheduledMinutes(of: task) ? actual : nil
        } else {
            task.actualEndTime = nil
        }
        ImpulseRules.reconcile(task, before: impulseBefore, types: impulseTypes)

        try? modelContext.save()
        
        // Notify that a task was updated
        NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
    }
}





#Preview {
    TasksCalendarView(selectedDate: .constant(Date()))
        .modelContainer(for: [Task.self], inMemory: true)
}

struct TaskActionsView: View {
    @Query private var allSubtasks: [Subtask]
    @Query private var allTasks: [Task] // For metrics calculation
    let task: Task
    let selectedDate: Date
    let onTaskDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false
    @State private var showEditDialog = false
    @State private var showNotesDialog = false
    @State private var showTimeSpentDialog = false
    @State private var showFileAttachments = false
    @State private var showSubtasksView = false
    @State private var showDuplicate = false
    @State private var didDuplicate = false
    @State private var navigateToHabits = false
    @State private var showPartialTimeAlert = false
    @State private var subtasksAccordionExpanded = true
    @State private var showSnoozeOptions = false
    @State private var showCustomSnooze = false
    @State private var customSnoozeMinutes = 20
    @State private var showExtendOptions = false
    /// Which action the custom-minutes sheet applies.
    @State private var customIsExtend = false
    @State private var showSwap = false
    @State private var didSwap = false
    @State private var showSplitSheet = false
    @State private var didSplit = false
    @Query(sort: \ImpulseType.sortOrder) private var snoozeImpulseTypes: [ImpulseType]
    @AppStorage("metricDays") private var metricDays: Int = 30 // Use AppStorage for cross-view sync

    private var canSnooze: Bool {
        task.date != nil && !task.startTime.isEmpty && !task.endTime.isEmpty
    }

    private var snoozeMessage: String {
        "Pushes this task later. ' + rule + '"
    }

    private func snooze(by minutes: Int) {
        let moved = TaskMover.snooze(task, by: minutes, context: modelContext, impulseTypes: snoozeImpulseTypes)
        NotificationCenter.default.post(name: NSNotification.Name("TasksSnoozed"), object: moved.map(\.id))
        NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
        dismiss()
    }

    private var extendMessage: String {
        "Adds time to the end of this task. Tasks starting within \(TaskMover.followWindowMinutes) min after it are pushed later by the same amount; later tasks it would run into are pushed just enough to not overlap."
    }

    private func extend(by minutes: Int) {
        let changed = TaskMover.extend(task, by: minutes, context: modelContext, impulseTypes: snoozeImpulseTypes)
        // Same notification refresh as snooze (end alerts + moved tasks).
        NotificationCenter.default.post(name: NSNotification.Name("TasksSnoozed"), object: changed.map(\.id))
        NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
        dismiss()
    }

    private var topLevelSubtasks: [Subtask] {
        SubtaskOrder.sorted(allSubtasks.filter {
            $0.parentTask?.persistentModelID == task.persistentModelID &&
            $0.parentSubtask == nil
        })
    }

    private var subtaskCount: Int {
        topLevelSubtasks.count
    }

    private func toggleSubtaskCompletion(_ subtask: Subtask) {
        subtask.completed.toggle()
        try? modelContext.save()
    }

    private func timeToMinutes(_ timeStr: String) -> Int {
        let clean = timeStr.trimmingCharacters(in: .whitespaces)
        let parts = clean.components(separatedBy: ":")
        guard parts.count >= 2,
              let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return 0 }
        return h * 60 + m
    }

    private var allottedMinutes: Int {
        timeToMinutes(task.endTime) - timeToMinutes(task.startTime)
    }

    private var partialTimeMessage: String {
        let spent = Int(task.timeSpent ?? 0)
        return "You've logged \(spent)m of \(allottedMinutes)m allotted. How would you like to complete this task?"
    }

    @ViewBuilder
    private var repeatMetricsSection: some View {
        if task.repeatAgain != nil {
            let metrics = task.calculateMetrics(days: metricDays, allTasks: allTasks, referenceDate: selectedDate)
            let pointsStats = calculatePointsForTask(task)
            let rateColor: Color = metrics.completionColor == "green" ? .green : (metrics.completionColor == "orange" ? .orange : .red)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    VStack(spacing: 0) {
                        Text(metrics.formattedScore)
                            .font(.caption2).fontWeight(.bold).foregroundColor(.blue)
                        Text("Score").font(.system(size: 8)).foregroundColor(.secondary)
                    }
                    .frame(width: 50, height: 35)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(spacing: 0) {
                        Text(metrics.formattedCompletionRate)
                            .font(.caption2).fontWeight(.bold).foregroundColor(rateColor)
                        Text("Rate").font(.system(size: 8)).foregroundColor(.secondary)
                    }
                    .frame(width: 50, height: 35)
                    .background(rateColor.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(spacing: 0) {
                        Text("\(Int(pointsStats.earned))/\(Int(pointsStats.allocated))")
                            .font(.caption2).fontWeight(.bold).foregroundColor(.purple)
                        Text("Points").font(.system(size: 8)).foregroundColor(.secondary)
                    }
                    .frame(width: 50, height: 35)
                    .background(Color.purple.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    if metrics.currentStreak > 0 {
                        VStack(spacing: 0) {
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill").font(.caption2)
                                Text("\(metrics.currentStreak)").font(.caption2).fontWeight(.bold)
                            }
                            .foregroundColor(.orange)
                            Text("Streak").font(.system(size: 8)).foregroundColor(.secondary)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text(task.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                            
                            repeatMetricsSection
                        }
                        
                        if !task.startTime.isEmpty || !task.endTime.isEmpty {
                            Text("\(task.startTime) - \(task.endTime)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Subtasks Section
                        DisclosureGroup(isExpanded: $subtasksAccordionExpanded) {
                            VStack(alignment: .leading, spacing: 8) {
                                if topLevelSubtasks.isEmpty {
                                    Text("No subtasks yet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                } else {
                                    ForEach(topLevelSubtasks) { subtask in
                                        Button {
                                            toggleSubtaskCompletion(subtask)
                                        } label: {
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: subtask.completed ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(subtask.completed ? .green : .secondary)
                                                Text("•  \(subtask.name)")
                                                    .strikethrough(subtask.completed)
                                                    .foregroundStyle(subtask.completed ? .secondary : .primary)
                                                    .multilineTextAlignment(.leading)
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack {
                                Label("Subtasks", systemImage: "list.bullet")
                                    .font(.caption)
                                    .foregroundColor(.indigo)
                                if !topLevelSubtasks.isEmpty {
                                    Text("(\(topLevelSubtasks.filter { $0.completed }.count)/\(topLevelSubtasks.count))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top)
                    
                    // Icon-only grid keeps every action on one screen.
                    // Each tile still has an accessibility label.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                        iconTile("checkmark.circle.fill", color: .green, label: "Enjoyed it? Dedicated to God. (Complete)", isOn: task.completed) {
                            let spentMinutes = task.timeSpent ?? 0
                            if !task.completed && spentMinutes > 0 && allottedMinutes > 0 && spentMinutes < Double(allottedMinutes) {
                                showPartialTimeAlert = true
                            } else {
                                toggleTaskCompletion()
                            }
                        }
                        .confirmationDialog(
                            "Time Partially Logged",
                            isPresented: $showPartialTimeAlert,
                            titleVisibility: .visible
                        ) {
                            Button("Complete — keep \(Int(task.timeSpent ?? 0))m logged") {
                                toggleTaskCompletion()
                            }
                            Button("Complete — log full \(allottedMinutes)m") {
                                task.timeSpent = Double(allottedMinutes)
                                toggleTaskCompletion()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text(partialTimeMessage)
                        }

                        iconTile("xmark.circle.fill", color: .red, label: "Mark Not Completed", isOn: task.notCompleted) {
                            toggleTaskNonCompletion()
                        }

                        iconTile("pencil", color: .blue, label: "Edit") {
                            showEditDialog = true
                        }

                        if canSnooze {
                            iconTile("moon.zzz.fill", color: .indigo, label: "Snooze") {
                                showSnoozeOptions = true
                            }
                            .confirmationDialog("Snooze by", isPresented: $showSnoozeOptions, titleVisibility: .visible) {
                                ForEach([5, 10, 15, 30], id: \.self) { mins in
                                    Button("\(mins) min") { snooze(by: mins) }
                                }
                                Button("Custom…") {
                                    customIsExtend = false
                                    showCustomSnooze = true
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text(snoozeMessage)
                            }

                            iconTile("goforward.plus", color: .teal, label: "Extend task time") {
                                showExtendOptions = true
                            }
                            .confirmationDialog("Extend by", isPresented: $showExtendOptions, titleVisibility: .visible) {
                                ForEach([5, 10, 15, 30], id: \.self) { mins in
                                    Button("\(mins) min") { extend(by: mins) }
                                }
                                Button("Custom…") {
                                    customIsExtend = true
                                    showCustomSnooze = true
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text(extendMessage)
                            }

                            if TaskSplitter.canSplit(task) {
                                iconTile("scissors", color: .pink, label: "Split task") {
                                    showSplitSheet = true
                                }
                                .sheet(isPresented: $showSplitSheet, onDismiss: {
                                    if didSplit { dismiss() }
                                }) {
                                    SplitTaskView(task: task) { second in
                                        didSplit = true
                                        // Refresh start/end alerts for both parts.
                                        NotificationCenter.default.post(name: NSNotification.Name("TasksSnoozed"), object: [task.id, second.id])
                                        NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
                                    }
                                }
                            }

                            if !task.completed && !task.notCompleted {
                                iconTile("arrow.left.arrow.right", color: .purple, label: "Swap task") {
                                    showSwap = true
                                }
                                .sheet(isPresented: $showSwap, onDismiss: {
                                    if didSwap { dismiss() }
                                }) {
                                    SwapTaskView(task: task) { didSwap = true }
                                }
                            }
                        }

                        iconTile("list.bullet", color: .indigo, label: "Subtasks", badge: subtaskCount) {
                            showSubtasksView = true
                        }

                        iconTile("note.text", color: .orange, label: "Notes") {
                            showNotesDialog = true
                        }

                        iconTile("paperclip", color: .brown, label: "Attach Files") {
                            showFileAttachments = true
                        }

                        iconTile("clock.fill", color: .cyan, label: "Time Spent") {
                            showTimeSpentDialog = true
                        }

                        if task.repeatAgain != nil {
                            iconTile("chart.bar.fill", color: .purple, label: "View Habit Tracker") {
                                navigateToHabitTracker()
                            }

                            // Same switch as the repeat icon on the task row:
                            // green = completing creates the next occurrence,
                            // red = it won't (already handled).
                            iconTile("repeat", color: task.reassign ? .red : .green,
                                     label: task.reassign
                                        ? "Repeat: next occurrence won't be created. Tap to turn on."
                                        : "Repeat: next occurrence will be created. Tap to turn off.") {
                                task.reassign.toggle()
                                try? modelContext.save()
                                NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
                            }
                        }

                        iconTile("plus.square.on.square", color: .blue, label: "Duplicate") {
                            showDuplicate = true
                        }
                        .sheet(isPresented: $showDuplicate, onDismiss: {
                            if didDuplicate { onTaskDeleted(); dismiss() }
                        }) {
                            DuplicateTaskView(task: task) { copy in
                                didDuplicate = true
                                NotificationCenter.default.post(name: NSNotification.Name("TasksSnoozed"), object: [copy.id])
                                NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
                            }
                        }

                        if task.date != nil {
                            iconTile("tray.and.arrow.down", color: .indigo, label: "Send to Backlog") {
                                sendToBacklog()
                            }
                        } else {
                            iconTile("calendar.badge.plus", color: .indigo, label: "Schedule for \(selectedDate.formatted(date: .abbreviated, time: .omitted))") {
                                scheduleFromBacklog()
                            }
                        }

                        iconTile("trash", color: .red, label: "Delete") {
                            showDeleteConfirmation = true
                        }
                    }
                    .padding(.bottom)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Task Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .taskDeleteAlert(isPresented: $showDeleteConfirmation, task: task) { _ in
            onTaskDeleted()
            dismiss()
        }
        .sheet(isPresented: $showEditDialog) {
            EditTaskView(task: task)
        }
        .sheet(isPresented: $showNotesDialog) {
            TaskNotesPagerView(task: task)
        }
        .sheet(isPresented: $showTimeSpentDialog) {
            TimeSpentEditorView(task: task)
        }
        .sheet(isPresented: $showFileAttachments) {
            TaskAttachmentsManagementView(task: task)
        }
        .sheet(isPresented: $showSubtasksView) {
            SubtasksView(parentTask: task)
        }
        .sheet(isPresented: $showCustomSnooze) {
            NavigationStack {
                Form {
                    Stepper("\(customSnoozeMinutes) min", value: $customSnoozeMinutes, in: 1...240)
                    Section {
                        Button {
                            showCustomSnooze = false
                            if customIsExtend {
                                extend(by: customSnoozeMinutes)
                            } else {
                                snooze(by: customSnoozeMinutes)
                            }
                        } label: {
                            Label(customIsExtend ? "Extend by \(customSnoozeMinutes) min" : "Snooze by \(customSnoozeMinutes) min",
                                  systemImage: customIsExtend ? "goforward.plus" : "moon.zzz.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } footer: {
                        Text(customIsExtend ? extendMessage : snoozeMessage)
                    }
                }
                .navigationTitle(customIsExtend ? "Custom Extend" : "Custom Snooze")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCustomSnooze = false }
                    }
                }
            }
            .presentationDetents([.height(260)])
        }
        .sheet(isPresented: $navigateToHabits) {
            NavigationStack {
                HabitDashboardView(initialHabit: task.habitName)
            }
        }
    }
    
    private func navigateToHabitTracker() {
        navigateToHabits = true
    }
    
    /// Square icon button for the actions grid. `isOn` fills it with the
    /// color (used for Complete / Not Completed state).
    private func iconTile(_ systemImage: String, color: Color, label: String, isOn: Bool = false, badge: Int? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(isOn ? Color.white : color)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isOn ? AnyShapeStyle(color) : AnyShapeStyle(.ultraThinMaterial))
                )
                .overlay(alignment: .topTrailing) {
                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(color))
                            .offset(x: -4, y: 4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func toggleTaskCompletion() {
        let wasCompleted = task.completed
        task.completed.toggle()
        print("📋 Task '\(task.title)' completion toggled in TaskActionsView. Completed: \(task.completed), Weight: \(task.weight), EffectiveWeight: \(task.effectiveWeight)")
        
        if task.completed {
            if !task.reassign {
                createRepeatTask(from: task)
            }
            
        }

        try? modelContext.save()
        dismiss()
    }

    private func toggleTaskNonCompletion() {
        task.notCompleted.toggle()
        if task.notCompleted && !task.reassign {
           
            createRepeatTask(from: task)
        }
         if task.notCompleted,

!task.isDailyRepeat
    {
        createIncompleteTask(from: task)
       
    }
        try? modelContext.save()
        dismiss()
    }

    /// Unschedules the task back into the Backlog — clears its date/time so
    /// it drops out of every day-based query (see `Task.isBacklog`) without
    /// losing anything else about it (weight, priority, subtasks, etc.).
    private func sendToBacklog() {
        task.date = nil
        task.startTime = ""
        task.endTime = ""
        try? modelContext.save()
        onTaskDeleted()
        dismiss()
    }

    /// The reverse of `sendToBacklog` — used when this sheet was opened on a
    /// backlog task (from the Backlog view). Schedules it onto `selectedDate`
    /// as untimed; the user can drag it to a specific slot afterward if needed.
    private func scheduleFromBacklog() {
        task.date = selectedDate
        try? modelContext.save()
        onTaskDeleted()
        dismiss()
    }

    private func createRepeatTask(from task: Task) {
        TaskRepeater.createNextInstance(from: task, context: modelContext)
    }


        private func createIncompleteTask(from task: Task) {
        // Skipped impulses don't roll over — bringing one back should be a deliberate choice.
        guard task.impulseTypeID == nil else { return }
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
            elapsedTime: task.elapsedTime,
            copySubtasks: task.copySubtasks,
            whyStatement: task.whyStatement, // Copy why statement to new task
            whyStatementPinned: task.whyStatementPinned // Copy pin status
            // timeSpent is intentionally not copied for repeat tasks
        )
        task.copyRepeat(to: newTask)
        newTask.goal = task.goal
        ImpulseRules.inherit(from: task, to: newTask, context: modelContext)

        modelContext.insert(newTask)

        // Copy subtasks if the toggle is enabled
        if task.copySubtasks {
            SubtaskOrder.copyAll(from: task, to: newTask, context: modelContext)
        }

        try? modelContext.save()
    }

    private func deleteTask() {
        modelContext.delete(task)
        try? modelContext.save()
        onTaskDeleted()
    }
    
    private func calculatePointsForTask(_ task: Task) -> (earned: Double, allocated: Double) {
        guard task.repeatAgain != nil else {
            return (earned: 0, allocated: 0)
        }
        
        // Get all tasks with the same title (same habit)
        let habitTasks = allTasks.filter { $0.repeatAgain != nil && $0.isSameHabit(as: task) }
        
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
}

// MARK: - Helper Functions
func formatTimeToAMPM(_ timeString: String) -> String {
    let components = timeString.components(separatedBy: ":")
    guard components.count >= 2,
          let hour = Int(components[0]),
          let minute = Int(components[1]) else {
        return timeString
    }
    
    let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
    let period = hour >= 12 ? "PM" : "AM"
    return "\(displayHour):\(String(format: "%02d", minute)) \(period)"
}

func roundToNearestFiveMinutes(_ date: Date) -> Date {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    let minutes = components.minute ?? 0
    let roundedMinutes = (minutes / 5) * 5
    
    var newComponents = components
    newComponents.minute = roundedMinutes
    newComponents.second = 0
    
    return calendar.date(from: newComponents) ?? date
}

/// Shown while picking an impulse's time when it would count as unplanned.
struct UnplannedImpulseWarning: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
