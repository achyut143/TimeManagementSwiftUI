import SwiftUI
import SwiftData
import AVFoundation
import ActivityKit
import Combine

// MARK: - Speech Synthesizer Manager
class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isMuted: Bool = UserDefaults.standard.bool(forKey: "SpeechManager.isMuted") {
        didSet { UserDefaults.standard.set(isMuted, forKey: "SpeechManager.isMuted") }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        guard !isMuted else { return }

        // Stop any ongoing speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5 // Slightly slower for clarity
        utterance.volume = 1.0

        synthesizer.speak(utterance)
        print("🔊 Speaking: \(text)")
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            stopSpeaking()
        }
    }
}

struct TimeEntry {
    let startMinutes: Int
    let endMinutes: Int
    let description: String
    let isFixed: Bool
    let originalLine: String
    
    var duration: Int {
        return endMinutes - startMinutes
    }
    
    func toLine() -> String {
        let startTime = safeMinutesToTime(startMinutes)
        let endTime = safeMinutesToTime(endMinutes)
        
        // Extract numbering prefix from original line if present
        let trimmedOriginal = originalLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let numberingPattern = "^(\\d+\\)\\s*)"
        
        if let regex = try? NSRegularExpression(pattern: numberingPattern, options: []),
           let match = regex.firstMatch(in: trimmedOriginal, range: NSRange(location: 0, length: trimmedOriginal.utf16.count)),
           let numberingRange = Range(match.range(at: 1), in: trimmedOriginal) {
            let numbering = String(trimmedOriginal[numberingRange])
            return "\(numbering)\(startTime) - \(endTime) - \(description)"
        }
        
        return "\(startTime) - \(endTime) - \(description)"
    }
    
    private func safeMinutesToTime(_ minutes: Int) -> String {
        // Add bounds checking to prevent crashes
        guard minutes >= -1440 && minutes <= 2880 else {
            return "Invalid Time"
        }
        
        // Ensure we have valid values before any calculations
        let adjustedMinutes = minutes >= 0 ? minutes : (minutes % (24 * 60) + 24 * 60)
        
        // Additional safety check after adjustment
        guard adjustedMinutes >= 0 && adjustedMinutes < (48 * 60) else {
            return "Invalid Time"
        }
        
        let hours = (adjustedMinutes / 60) % 24
        let mins = adjustedMinutes % 60
        
        // Validate calculated values
        guard hours >= 0 && hours <= 23 && mins >= 0 && mins <= 59 else {
            return "Invalid Time"
        }
        
        let displayHour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
        let ampm = hours < 12 ? "AM" : "PM"
        return "\(displayHour):\(String(format: "%02d", mins)) \(ampm)"
    }
}

struct DailyNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var dailyNotes: [DailyNote]
    @StateObject private var settings = AlertSettings.shared
    @StateObject private var speechManager = SpeechManager.shared
    @StateObject private var distractionTracker = DistractionTracker.shared
    @State private var notesText: String = ""
    @State private var adjustmentMinutes: String = ""
    @State private var editorKey: UUID = UUID()
    @State private var useCycles: Bool = UserDefaults.standard.bool(forKey: "DailyNotesView.useCycles")
    @State private var countdownTimer: Timer?
    @State private var timeRemaining: TimeInterval = 0
    @State private var previousTimeRemaining: TimeInterval = 0
    @State private var currentTaskName: String = ""
    @State private var currentCycleDuration: Int = 0
    @State private var isTransitioning: Bool = false
    @State private var cycleEndObserver: AnyCancellable?
    @State private var pausedAt: Date?
    @State private var totalPausedDuration: TimeInterval = 0
    @State private var currentTime: Date = Date() // Add this to force UI updates
    @State private var scheduleFrom: String = ""
    @State private var scheduleTo: String = ""
    @State private var scheduleInterval: String = ""
    @State private var scheduleGap: String = ""
    @State private var scheduleTaskName: String = ""
    @State private var scheduleInsertAfter: String = ""
    @State private var scheduleStartNum: String = "1"
    @State private var scheduleNoRepeat: Bool = false
    @State private var showFormattedSchedule: Bool = true
    @AppStorage("schedule.hideFinishedTasks") private var hideFinishedTasks: Bool = false
    @State private var editingTask: EditTaskItem? = nil
    @State private var reminderInterval: String = UserDefaults.standard.string(forKey: "DailyNotesView.reminderInterval") ?? "0"
    @State private var reminderTimer: Timer?
    @State private var showBooksLibrary = false
    @State private var isFocusMode = false
    @State private var showSaveTemplate = false
    @State private var showTemplates = false
    @State private var showAutoGenSheet = false
    @State private var autoGenDuration: String = "10"
    @State private var showAISchedulerSheet = false
    @Query private var allTasksQuery: [Task]
    @Query(filter: #Predicate<ScheduledActivity> { $0.isActive })
    private var activeActivities: [ScheduledActivity]
    @State private var creditEarnedMessage: String = ""
    @State private var showInterceptSheet = false
    @State private var showSwapSheet = false
    @State private var swapSheetDefaults: (Int?, Int?) = (nil, nil)
    @State private var scheduleRenderID: UUID = UUID()
    @State private var showDeleteOptions = false
    @State private var pendingDeleteStart: Int = 0
    @State private var pendingDeleteEnd: Int = 0
    @State private var pendingDeleteDesc: String = ""
    @State private var showCancelOptions = false
    @State private var showAdjustOptions = false
    @State private var showGroupBySheet = false
    @State private var showDistractionPrompt = false
    @State private var pendingDistractionAbsenceSecs: Int = 0
    @AppStorage("manualMode.enabled") private var manualModeEnabled: Bool = false
    @State private var isWaitingForManualStart: Bool = false
    @State private var manualWaitStartDate: Date? = nil
    @State private var pendingNextTaskName: String = ""
    @State private var pendingPreviousTaskName: String = ""
    @State private var pendingTaskEndMinutes: Int = 0
    @State private var totalIdleSeconds: Int = 0
    let selectedDate: Date
    
    private var todayNote: DailyNote? {
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        return dailyNotes.first { Calendar.current.isDate($0.date, inSameDayAs: startOfDay) }
    }
    
    private var currentTimeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
    
    private func getNoteForDate(_ date: Date) -> DailyNote? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return dailyNotes.first { Calendar.current.isDate($0.date, inSameDayAs: startOfDay) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Time Adjustment") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Adjust times by (minutes):")
                            TextField("+10 or -5", text: $adjustmentMinutes)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 100)
                            Button("Apply") {
                                adjustTimesInNotes()
                                saveNotes()
                            }
                            .disabled(adjustmentMinutes.isEmpty)
                        }

                        // Quick adjustment buttons
                        HStack(spacing: 8) {
                            Text("Quick:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button("-5") {
                                adjustmentMinutes = "-5"
                                adjustTimesInNotes()
                                saveNotes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("+5") {
                                adjustmentMinutes = "5"
                                adjustTimesInNotes()
                                saveNotes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Text("Use positive numbers to push times forward (+30) or negative to pull back (-15). Fixed tasks marked with **text** remain unchanged.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Simple Cycles Section
                Section("Smart Cycles") {
                    VStack(spacing: 12) {
                        // Pending tasks — shown before the auto scheduler
                        PendingTasksDisplayView(selectedDate: selectedDate)

                        Divider()

                        HStack {
                            Toggle(isOn: $useCycles) {
                                Text("Auto-start cycles from schedule")
                                    .font(.headline)
                            }
                            .onChange(of: useCycles) { _, newValue in
                                // Save the toggle state to UserDefaults
                                UserDefaults.standard.set(newValue, forKey: "DailyNotesView.useCycles")
                                
                                if newValue {
                                    startSmartCycles()
                                } else {
                                    stopCycles()
                                }
                            }
                            
                            if useCycles {
                                Button(action: {
                                    startSmartCycles()
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.body)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        
                        if useCycles {
                            Text("Automatically detects your schedule from START/END sections and starts appropriate cycles based on current time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            
                            // Reminder Interval Setting
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Reminder interval:")
                                        .font(.subheadline)
                                    TextField("0", text: $reminderInterval)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(width: 60)
                                    Text("min")
                                        .foregroundColor(.secondary)
                                }
                                .onChange(of: reminderInterval) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "DailyNotesView.reminderInterval")
                                }
                                
                                Text("Set to 0 to disable. When set (e.g., 5), you'll get voice reminders every 5 minutes with time remaining.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)

                            Toggle(isOn: $manualModeEnabled) {
                                Label("Manual Mode", systemImage: "hand.raised.fill")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .padding(.top, 4)
                            if manualModeEnabled {
                                Text("Each task must be started manually. Idle waiting time is recorded in your schedule.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if settings.isPlaying || settings.isPaused || isTransitioning || currentCycleDuration > 0 || isWaitingForManualStart {
                                cycleStatusView
                            }

                            Button(action: { strikeOutPastTimeSlots() }) {
                                Label("Strike Past Slots", systemImage: "text.badge.checkmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        }

                        // Books quotes — always visible alongside the scheduler
                        Divider()

                        HStack {
                            Label("Books", systemImage: "books.vertical.fill")
                                .font(.caption)
                                .foregroundColor(.indigo)
                            Spacer()
                            Button(action: { showBooksLibrary = true }) {
                                Text("Manage")
                                    .font(.caption)
                                    .foregroundColor(.indigo)
                            }
                        }

                        BookQuoteDisplayView()
                    }
                }

                Section("Daily Notes") {
                    // Toolbar — icon buttons with short labels, always single row
                    HStack(spacing: 6) {
                        toolbarButton(icon: "doc.on.doc.fill",        label: "Templates",  color: .indigo)  { showTemplates       = true }
                        toolbarButton(icon: "wand.and.stars",          label: "Schedule",   color: .orange)  { showAutoGenSheet    = true }
                        toolbarButton(icon: "sparkles.rectangle.stack",label: "AI",         color: .purple)  { showAISchedulerSheet = true }
                        if hasSchedule, currentScheduleBlock != nil {
                            toolbarButton(icon: "square.and.arrow.down", label: "Save",     color: .green)   { showSaveTemplate    = true }
                        }
                        Spacer()
                    }

                    if hasSchedule {
                        HStack {
                            Label(
                                showFormattedSchedule ? "Schedule View" : "Raw Notes",
                                systemImage: showFormattedSchedule ? "list.bullet.rectangle.portrait.fill" : "pencil.line"
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            Spacer()
                            Toggle("", isOn: $showFormattedSchedule)
                                .labelsHidden()
                        }

                        if showFormattedSchedule {
                            HStack {
                                Label("Hide finished", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { showGroupBySheet = true }) {
                                    Label("Group By", systemImage: "chart.bar.fill")
                                        .font(.caption2)
                                        .foregroundColor(.indigo)
                                }
                                .buttonStyle(PlainButtonStyle())
                                Button(action: clearZeroDurationSchedule) {
                                    Label("Clear Zeros", systemImage: "scissors")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                .buttonStyle(PlainButtonStyle())
                                Toggle("", isOn: $hideFinishedTasks)
                                    .labelsHidden()
                            }
                        }
                    }

                    if showFormattedSchedule && hasSchedule {
                        scheduleFormattedView
                            .id(scheduleRenderID)
                    } else {
                        RichTextEditor(text: $notesText)
                            .frame(height: 300)
                            .id(editorKey)
                    }
                }

                Section("Schedule Generator") {
                    VStack(spacing: 12) {
                        Toggle(isOn: $scheduleNoRepeat) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Single pass (no repeat cycles)")
                                    .font(.subheadline)
                                Text("Generate each task once in order from start time. No end time needed.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tint(.indigo)

                        HStack {
                            Text("From:")
                                .frame(width: 60, alignment: .leading)
                            TextField("10:00 AM", text: $scheduleFrom)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numbersAndPunctuation)
                        }

                        if !scheduleNoRepeat {
                            HStack {
                                Text("To:")
                                    .frame(width: 60, alignment: .leading)
                                TextField("5:00 PM", text: $scheduleTo)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numbersAndPunctuation)
                            }
                        }

                        HStack {
                            Text("Interval:")
                                .frame(width: 60, alignment: .leading)
                            TextField("25,20,10", text: $scheduleInterval)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numbersAndPunctuation)
                            Text("min")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Gap:")
                                .frame(width: 60, alignment: .leading)
                            TextField("5,3,2", text: $scheduleGap)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numbersAndPunctuation)
                            Text("min")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Task:")
                                .frame(width: 60, alignment: .leading)
                            TextField("work,implement,walk", text: $scheduleTaskName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        HStack {
                            Text("Insert after #:")
                                .frame(width: 90, alignment: .leading)
                            TextField("optional", text: $scheduleInsertAfter)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .frame(width: 70)
                            Text("(empty = nearest interval)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Start #:")
                                .frame(width: 90, alignment: .leading)
                            TextField("1", text: $scheduleStartNum)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .frame(width: 70)
                            Text("first task number")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Button("Generate Schedule") {
                            generateSchedule()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(scheduleFrom.isEmpty ||
                                 (!scheduleNoRepeat && scheduleTo.isEmpty) ||
                                 scheduleInterval.isEmpty || scheduleGap.isEmpty ||
                                 scheduleTaskName.isEmpty)

                        Text(scheduleNoRepeat
                             ? "Generates each task once in sequence from the start time."
                             : "Generates repeating time blocks with specified intervals and gaps.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Button(action: { showInterceptSheet = true }) {
                            Label("Intercept Tasks", systemImage: "arrow.turn.down.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)

                        Text("Insert new timed tasks at a specific position in the schedule. Existing tasks are renumbered but keep their times.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Daily Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Button(action: {
                        hideKeyboard()
                        saveNotes()
                        // If cycles are enabled, restart them with updated notes
                        DispatchQueue.main.async {
                            if self.useCycles {
                                self.startSmartCycles()
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save")
                        }
                        .font(.headline)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        hideKeyboard()
                        saveNotes()
                        // If cycles are enabled, restart them with updated notes
                        DispatchQueue.main.async {
                            if self.useCycles {
                                self.startSmartCycles()
                            }
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button(action: { speechManager.toggleMute() }) {
                            Label(
                                speechManager.isMuted ? "Unmute" : "Mute",
                                systemImage: speechManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                            )
                            .foregroundColor(speechManager.isMuted ? .red : .primary)
                        }
                        Spacer()
                        Button(action: { isFocusMode = true }) {
                            Label("Focus", systemImage: "sparkles")
                                .foregroundColor(.indigo)
                        }
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        hideKeyboard()
                    }
                }
            }
            .onAppear {
                loadNotesForDate(selectedDate)
                handleReturn()
                startCountdownTimer()
                recalculateTotalIdleTime()

                // Load persistent pause state
                loadPauseState()

                if useCycles {
                    if pausedAt != nil {
                        // Restore smart-paused state: timer off, Smart Resume button active
                        settings.isPlaying = true
                        settings.isPaused = true
                    } else if !isWaitingForManualStart {
                        // Mirror the toggle: full reset then clean start so stale
                        // AlertSettings state (counter, isPlaying, isTransitioning) is cleared
                        stopCycles()
                        startSmartCycles()
                    }
                    // If isWaitingForManualStart, preserve the idle waiting state as-is
                }
            }
            .onDisappear {
                trackDistraction()
                stopCountdownTimer()
                cycleEndObserver?.cancel()
                speechManager.stopSpeaking()
                reminderTimer?.invalidate()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                trackDistraction()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                handleReturn()
            }
            .onChange(of: selectedDate) { _, _ in
                loadNotesForDate(selectedDate)
            }
            .onChange(of: notesText) { _, _ in
                scheduleRenderID = UUID()
                recalculateTotalIdleTime()
            }
            .onChange(of: currentTaskName) { _, newName in
                settings.activeTaskName = newName
            }
            .sheet(isPresented: $showBooksLibrary) {
                BooksView()
            }
            .sheet(isPresented: $showTemplates) {
                ScheduleTemplatesView { templates in
                    applyTemplates(templates)
                }
            }
            .sheet(isPresented: $showAutoGenSheet) {
                AutoScheduleSheet(
                    selectedDate: selectedDate,
                    allTasks: allTasksQuery,
                    duration: $autoGenDuration,
                    onGenerate: { tasks, duration, startTimeStr in
                        autoGenerateSchedule(tasks: tasks, minutesPerTask: duration, startTimeStr: startTimeStr)
                    }
                )
            }
            .sheet(isPresented: $showAISchedulerSheet) {
                AISchedulerSheet(
                    selectedDate: selectedDate,
                    allTasks: allTasksQuery,
                    startNumber: maxScheduleNumber() + 1,
                    onInsert: { scheduleBlock in
                        insertAISchedule(scheduleBlock)
                    }
                )
            }
            .sheet(isPresented: $showSaveTemplate) {
                if let block = currentScheduleBlock {
                    SaveTemplateSheet(scheduleContent: block)
                }
            }
            .sheet(item: $editingTask) { task in
                EditTaskSheet(
                    task: task,
                    onSave: { newDesc, newStart, newEnd in
                        updateTaskAndShiftInNotes(item: task, newDesc: newDesc, newStart: newStart, newEnd: newEnd)
                    }
                )
            }
            .sheet(isPresented: $showInterceptSheet) {
                InterceptSheet { lines, afterNum in
                    applyIntercept(lines: lines, afterNum: afterNum)
                }
            }
            .sheet(isPresented: $showSwapSheet) {
                SwapTasksSheet(defaultA: swapSheetDefaults.0, defaultB: swapSheetDefaults.1) { a, b in
                    swapScheduleTasks(numA: a, numB: b)
                }
            }
            .confirmationDialog("Delete Task", isPresented: $showDeleteOptions, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    deleteScheduleTask(startMin: pendingDeleteStart, endMin: pendingDeleteEnd, desc: pendingDeleteDesc)
                }
                Button("Delete & Adjust Times Below", role: .destructive) {
                    deleteScheduleTaskAndShift(startMin: pendingDeleteStart, endMin: pendingDeleteEnd,
                                              desc: pendingDeleteDesc, shiftBy: pendingDeleteEnd - pendingDeleteStart)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("How would you like to delete \"\(pendingDeleteDesc)\"?")
            }
            .confirmationDialog("Cancel Current Task", isPresented: $showCancelOptions, titleVisibility: .visible) {
                Button("Stop & Start Next") {
                    cancelCurrentTask()
                }
                Button("Remove & Adjust Times") {
                    removeCurrentTaskFromNotes(adjustTime: true)
                }
                Button("Just Remove") {
                    removeCurrentTaskFromNotes(adjustTime: false)
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showGroupBySheet) {
                GroupByView(notesText: $notesText, selectedDate: selectedDate)
            }
            .confirmationDialog(
                "You were away \(formatWaitCountUp(pendingDistractionAbsenceSecs)). Record as distraction?",
                isPresented: $showDistractionPrompt, titleVisibility: .visible
            ) {
                Button("Record as Distraction") { confirmDistraction() }
                Button("Not a Distraction", role: .cancel) { dismissDistraction() }
            }
            .confirmationDialog("Add Adjust (5 min) — start from?", isPresented: $showAdjustOptions, titleVisibility: .visible) {
                Button("Current Task") {
                    insertAdjustTask(fromStrikethrough: false)
                }
                Button("Last Completed Task") {
                    insertAdjustTask(fromStrikethrough: true)
                }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $isFocusMode) {
                FocusModeView(
                    isPresented: $isFocusMode,
                    currentTaskName: currentTaskName,
                    selectedDate: selectedDate,
                    timeRemaining: timeRemaining,
                    currentCycleDuration: $currentCycleDuration,
                    isTransitioning: isTransitioning,
                    isSmartPaused: pausedAt != nil,
                    pausedAt: pausedAt,
                    notesText: $notesText,
                    settings: settings,
                    onSmartPause:         { handleSmartPause() },
                    onStrikePast:         { strikeOutPastTimeSlots() },
                    onExtendTask:         { extendCurrentTask() },
                    onInterrupt:          { insertInterruptTask() },
                    onAdjust:             { fromStrikethrough in insertAdjustTask(fromStrikethrough: fromStrikethrough) },
                    isWaitingForManualStart: isWaitingForManualStart,
                    manualWaitStartDate:  manualWaitStartDate,
                    pendingNextTaskName:  pendingNextTaskName,
                    totalIdleSeconds:     totalIdleSeconds,
                    onStartManualNext:    { startManualNextTask() },
                    onExtendPrevious:     { extendPreviousTaskAndStart() },
                    onEndAndNew:          { endAndStartNewTask() },
                    onCancelTask:         { cancelCurrentTask() },
                    onRemoveCurrentAdjust: { removeCurrentTaskFromNotes(adjustTime: true) },
                    onRemoveCurrentOnly:   { removeCurrentTaskFromNotes(adjustTime: false) },
                    onSwapTasks:           { a, b in swapScheduleTasks(numA: a, numB: b) },
                    onNotesModified:       { saveNotes() },
                    computeSwapDefaults:   { currentAndNextTaskNums() },
                    onRecalculateDistractions: {
                        let entries = parsedDistractionEntries()
                        distractionTracker.recalculateFromNotes(date: selectedDate, entries: entries)
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private func toolbarButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(color)
            .frame(width: 58, height: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var cycleStatusView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: settings.isPaused ? "pause.circle.fill" : "play.circle.fill")
                    .foregroundStyle(settings.isPaused ? .orange : .blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    if isTransitioning {
                        Text("Transitioning to next task...")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Current: \(currentTaskName)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    if currentCycleDuration > 0 && !isTransitioning {
                        Text("Duration: \(currentCycleDuration) minutes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Show current time for debugging
                    Text("Current time: \(currentTimeString)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
            }
            
            // Task Progress Indicator
            let taskProgress = calculateTaskProgress()
            if taskProgress.total > 0 {
                VStack(spacing: 6) {
                    // First row: Main progress
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("\(taskProgress.completed)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text("\(taskProgress.running)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(taskProgress.remaining)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        
                        Spacer()
                    }
                    
                    // Second row: Labels
                    HStack(spacing: 6) {
                        Text("Done")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        
                        Text("Current")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        
                        Text("Upcoming")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        
                        Spacer()
                    }
                    
                    // Third row: Accountability metric
                    if taskProgress.unacknowledged > 0 {
                        Divider()
                        
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Pending Review:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                            Text("\(taskProgress.unacknowledged)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.orange)
                            Text("not marked")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Show conflicts if any
            let conflicts = findConflictsAtCurrentTime()
            if !conflicts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚠️ Schedule conflicts detected:")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fontWeight(.medium)
                    
                    ForEach(conflicts, id: \.originalLine) { conflict in
                        Text("• \(conflict.description) (\(safeMinutesToTime(conflict.startMinutes))-\(safeMinutesToTime(conflict.endMinutes)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            if settings.isPlaying {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "timer")
                            .font(.title2)
                            .foregroundStyle(timeRemaining <= 30 ? .red : (settings.isPaused ? .orange : .blue))
                        Text(settings.isPaused ? "Time paused:" : "Time remaining:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    
                    HStack {
                        Text(formatTimeRemaining(timeRemaining))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(timeRemaining <= 30 ? .red : (settings.isPaused ? .orange : .blue))
                            .monospacedDigit()
                        Spacer()
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: timeRemaining <= 30)
            }
            
            // Manual mode waiting state
            if isWaitingForManualStart {
                let waitElapsed = max(0, Int(currentTime.timeIntervalSince(manualWaitStartDate ?? currentTime)))
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.yellow)
                        Text("Waiting for: \(pendingNextTaskName)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.yellow)
                        Spacer()
                    }
                    HStack(alignment: .center, spacing: 12) {
                        Text(formatWaitCountUp(waitElapsed))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.yellow)
                            .monospacedDigit()
                        Spacer()
                        VStack(spacing: 4) {
                            Button(action: { startManualNextTask() }) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(.yellow)
                            }
                            Text("Idle").font(.caption2).foregroundStyle(.yellow)
                        }
                        VStack(spacing: 4) {
                            Button(action: { extendPreviousTaskAndStart() }) {
                                Image(systemName: "arrowshape.right.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(.green)
                            }
                            Text("Extend").font(.caption2).foregroundStyle(.green)
                        }
                    }
                    if totalIdleSeconds > 0 {
                        HStack {
                            Image(systemName: "hourglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Total idle: \(formatWaitCountUp(totalIdleSeconds))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(12)
                .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 16) {
                Button(isWaitingForManualStart ? "Stop" : (settings.isPlaying ? "Stop" : "Start")) {
                    DispatchQueue.main.async {
                        if self.settings.isPlaying || self.isWaitingForManualStart {
                            self.stopCycles()
                        } else {
                            self.startSmartCycles()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                if settings.isPlaying {
                    Button(settings.isPaused ? "Resume" : "Pause") {
                        DispatchQueue.main.async {
                            if self.settings.isPaused {
                                self.settings.isPaused = false
                            } else {
                                self.settings.isPaused = true
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }

            if totalIdleSeconds > 0 && !isWaitingForManualStart {
                HStack {
                    Image(systemName: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Total idle: \(formatWaitCountUp(totalIdleSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if settings.isPlaying && !isTransitioning && !currentTaskName.isEmpty {
                HStack(spacing: 10) {
                    // +5 min
                    Button(action: { extendCurrentTask() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .help("+5 min")

                    // Interrupt
                    Button(action: { insertInterruptTask() }) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .help("Interrupt")

                    // Adjust
                    Button(action: { showAdjustOptions = true }) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .help("Adjust (+5 min)")

                    // End & New
                    Button(action: { endAndStartNewTask() }) {
                        Image(systemName: "arrow.trianglehead.turn.up.right.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .help("End & New Task")

                    // Cancel options
                    Button(action: { showCancelOptions = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                    .help("Cancel Options")

                    // Swap tasks
                    Button(action: {
                        swapSheetDefaults = currentAndNextTaskNums()
                        showSwapSheet = true
                    }) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.indigo)
                    .help("Swap Tasks")
                }
            }

            // Smart Pause button (separate from regular pause) - ALWAYS VISIBLE FOR DEBUG
            Button(action: {
                print("🔘 Smart Pause button ACTION triggered")
                print("🔘 settings.isPlaying: \(settings.isPlaying)")
                print("🔘 pausedAt: \(pausedAt?.description ?? "nil")")
                if settings.isPlaying {
                    handleSmartPause()
                } else {
                    print("⚠️ Cannot use Smart Pause - no cycle is running")
                }
            }) {
                Text(pausedAt != nil ? "Smart Resume" : "Smart Pause")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(pausedAt != nil ? .green : (settings.isPlaying ? .orange : .gray))
            .disabled(!settings.isPlaying)
            
            // Show pause duration if smart paused
            if pausedAt != nil, let pausedAtTime = pausedAt {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.orange)
                        Text("Smart Paused for: \(formatPauseDuration(currentTime.timeIntervalSince(pausedAtTime)))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fontWeight(.medium)
                    }

                    Text("All following tasks will be adjusted when you resume")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
            }

        }
        .padding()
        .background(
            (currentTaskName == "Rest up" ? Color.mint : Color.blue).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func findConflictsAtCurrentTime() -> [TimeEntry] {
        let now = Date()
        let calendar = Calendar.current
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        
        let timeEntries = extractTimeEntriesFromNotes()
        let activeTasks = timeEntries.filter { entry in
            currentMinutes >= entry.startMinutes && currentMinutes < entry.endMinutes
        }
        
        return activeTasks.count > 1 ? activeTasks : []
    }
    
    private func calculateTaskProgress() -> (completed: Int, running: Int, remaining: Int, unacknowledged: Int, total: Int) {
        let now = Date()
        let calendar = Calendar.current
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        
        // Get all lines from notes between START and END
        let startTag = "START"
        let endTag = "END"
        let allLines = notesText.components(separatedBy: .newlines)
        
        // Find START and END indices
        var startLineIndex: Int?
        var endLineIndex: Int?
        
        for (index, line) in allLines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine == startTag && startLineIndex == nil {
                startLineIndex = index
            } else if trimmedLine == endTag && startLineIndex != nil && endLineIndex == nil {
                endLineIndex = index
                break
            }
        }
        
        guard let startIndex = startLineIndex,
              let endIndex = endLineIndex,
              startIndex < endIndex else {
            return (0, 0, 0, 0, 0)
        }
        
        let contentLines = Array(allLines[(startIndex + 1)..<endIndex])
        
        var completed = 0  // Only acknowledged (strikethrough) completed tasks
        var current = 0    // Active task + unacknowledged completed tasks
        var remaining = 0
        var unacknowledged = 0
        var previousEndMinutes: Int? = nil
        
        // Parse ALL lines including strikethrough
        for line in contentLines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            if trimmedLine.isEmpty {
                continue
            }
            
            // Check if line is strikethrough
            let isStrikethrough = trimmedLine.hasPrefix("~~") && trimmedLine.hasSuffix("~~")
            
            // Try to parse the line (remove strikethrough markers first if present)
            var lineToParse = isStrikethrough ? 
                String(trimmedLine.dropFirst(2).dropLast(2)) : trimmedLine
            
            // Remove numbering prefix if present (e.g., "1) ", "2) ", "123) ")
            lineToParse = lineToParse.replacingOccurrences(
                of: "^\\d+\\)\\s*",
                with: "",
                options: .regularExpression
            )
            
            if let entry = parseTimeEntrySequential(lineToParse, previousEndMinutes: previousEndMinutes) {
                previousEndMinutes = entry.endMinutes
                
                if currentMinutes >= entry.endMinutes {
                    // Task has ended
                    if isStrikethrough {
                        // Acknowledged - count as completed
                        completed += 1
                    } else {
                        // Not acknowledged - count as current (needs attention)
                        current += 1
                        unacknowledged += 1
                    }
                } else if currentMinutes >= entry.startMinutes && currentMinutes < entry.endMinutes {
                    // Task is currently active - count as current
                    current += 1
                } else if currentMinutes < entry.startMinutes {
                    // Task hasn't started yet - it's remaining
                    remaining += 1
                }
            }
        }
        
        let total = completed + current + remaining
        return (completed, current, remaining, unacknowledged, total)
    }
    
    // MARK: - Smart Cycles Logic
    
    private func startSmartCycles() {
        DispatchQueue.main.async {
            let timeEntries = self.extractTimeEntriesFromNotes()
            guard !timeEntries.isEmpty else {
                self.currentTaskName = "No schedule found"
                return
            }
            
            let now = Date()
            let calendar = Calendar.current
            let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            
            // Find what should be happening now - handle conflicts by priority
            if let currentEntry = self.findBestCurrentTask(at: currentMinutes, in: timeEntries) {
                // Currently in a scheduled task
                self.currentTaskName = currentEntry.description
                // For midnight-crossing tasks endMinutes >= 1440; normalise currentMinutes
                let adjustedCurrent = (currentEntry.endMinutes >= 1440 && currentMinutes < (currentEntry.endMinutes - 1440))
                    ? currentMinutes + 1440
                    : currentMinutes
                let remainingMinutes = currentEntry.endMinutes - adjustedCurrent
                // Store the ORIGINAL duration, not remaining time
                let originalDuration = currentEntry.endMinutes - currentEntry.startMinutes
                self.currentCycleDuration = originalDuration
                
                // Start cycle for remaining time
                self.startCycleWithDuration(remainingMinutes, taskName: currentEntry.description)
                
            } else if let nextEntry = self.findNextTask(after: currentMinutes, in: timeEntries) {
                // In a gap before next task - start preparation/rest/Drink Water cycle
                let gapMinutes = nextEntry.startMinutes - currentMinutes
                self.currentTaskName = "Rest up"
                self.currentCycleDuration = gapMinutes
                
                // Start preparation cycle
                self.startCycleWithDuration(gapMinutes, taskName: "Rest up")
                
            } else {
                // No more tasks today
                self.currentTaskName = "Free time"
                self.currentCycleDuration = 0
            }
        }
    }
    
    private func findBestCurrentTask(at currentMinutes: Int, in timeEntries: [TimeEntry]) -> TimeEntry? {
        // Find all tasks that are currently active
        let activeTasks = timeEntries.filter { entry in
            if entry.endMinutes >= 1440 {
                // Midnight-crossing task: active either before midnight (currentMinutes >= startMinutes)
                // or after midnight (currentMinutes < endMinutes wrapped back into 0-based minutes)
                return currentMinutes >= entry.startMinutes ||
                       currentMinutes < (entry.endMinutes - 1440)
            }
            return currentMinutes >= entry.startMinutes && currentMinutes < entry.endMinutes
        }
        
        guard !activeTasks.isEmpty else { return nil }
        
        // If only one task, return it
        if activeTasks.count == 1 {
            return activeTasks.first
        }
        
        // Multiple conflicting tasks - apply priority rules:
        // 1. Prefer tasks that started more recently (later start time)
        // 2. If same start time, prefer shorter duration (more specific)
        // 3. If same duration, prefer first in list (order matters)
        
        let sortedTasks = activeTasks.sorted { task1, task2 in
            // Rule 1: Later start time wins
            if task1.startMinutes != task2.startMinutes {
                return task1.startMinutes > task2.startMinutes
            }
            
            // Rule 2: Shorter duration wins (more specific)
            if task1.duration != task2.duration {
                return task1.duration < task2.duration
            }
            
            // Rule 3: Keep original order (first in notes wins)
            return false
        }
        
        let selectedTask = sortedTasks.first!
        
        // Log the conflict resolution for debugging
        if activeTasks.count > 1 {
            let conflictingTasks = activeTasks.map { 
                let startTime = safeMinutesToTime($0.startMinutes)
                let endTime = safeMinutesToTime($0.endMinutes)
                return "\($0.description) (\(startTime)-\(endTime))"
            }
            let currentTimeStr = safeMinutesToTime(currentMinutes)
            let selectedStartTime = safeMinutesToTime(selectedTask.startMinutes)
            print("⚠️ Conflict at \(currentTimeStr): \(conflictingTasks.joined(separator: ", "))")
            print("✅ Selected: \(selectedTask.description) (most recent start: \(selectedStartTime))")
        }
        
        return selectedTask
    }
    
    private func findNextTask(after currentMinutes: Int, in timeEntries: [TimeEntry]) -> TimeEntry? {
        return timeEntries.first { entry in
            entry.startMinutes > currentMinutes
        }
    }
    
    private func startCycleWithDuration(_ minutes: Int, taskName: String) {
        // Set up AlertSettings for this cycle
        settings.useCycles = false // Use simple mode
        settings.intervalMinutes = minutes
        settings.intervalSeconds = 0
        settings.targetIntervals = 1 // Just one interval
        settings.workIntervalText = taskName
        
        // Start the timer
        settings.nextAlertDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        settings.isPlaying = true
        settings.isPaused = false
        settings.scheduleIntervalTimer()
        
        // Announce task start
        let announcement = "Starting \(taskName) for \(minutes) minute\(minutes == 1 ? "" : "s")"
        speechManager.speak(announcement)
        
        // Set up observer for when this cycle ends
        setupCycleEndObserver()
        
        // Start reminder timer if interval is set
        startReminderTimer()
        
        print("🎯 Started cycle: \(taskName) for \(minutes) minutes")
    }
    
    private func setupCycleEndObserver() {
        cycleEndObserver?.cancel()

        cycleEndObserver = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak settings] _ in
                guard let settings = settings else { return }
                // Don't gate on settings.isPlaying — AlertSettings can reset it to false
                // before this 0.5 s tick fires, causing us to miss the completion entirely.
                // Instead gate on our own state that only stopCycles() clears.
                guard self.useCycles && !self.isTransitioning && self.pausedAt == nil && !self.isWaitingForManualStart else { return }
                guard self.currentCycleDuration > 0 else { return }

                let timeRemaining = settings.nextAlertDate.timeIntervalSinceNow
                // Lower bound removed: task may have expired while app was backgrounded,
                // in which case timeRemaining can be arbitrarily negative. The isTransitioning
                // guard above plus handleCycleCompletion's own guard prevent double-firing.
                if timeRemaining <= 1.0 {
                    self.handleCycleCompletion()
                }
            }
    }
    
    private func stopCycles() {
        DispatchQueue.main.async {
            self.settings.isPlaying = false
            self.settings.isPaused = false
            self.settings.stopTimer()
            self.currentTaskName = ""
            self.currentCycleDuration = 0
            self.isTransitioning = false
            self.cycleEndObserver?.cancel()
            self.speechManager.stopSpeaking()
            self.stopReminderTimer()
            self.pausedAt = nil
            self.totalPausedDuration = 0
            self.savePauseState()
            // Clean up manual mode waiting state
            self.isWaitingForManualStart = false
            self.manualWaitStartDate = nil
        }
    }
    
    // MARK: - Strike Past Slots

    private func strikeOutPastTimeSlots() {
        let now = Date()
        let calendar = Calendar.current
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        // Identify the currently active time entry so we know the cutoff
        let timeEntries = extractTimeEntriesFromNotes()
        let activeEntry = findBestCurrentTask(at: currentMinutes, in: timeEntries)

        // A slot is "past" if it ended before the active slot starts (or before now if no active slot)
        let cutoffMinutes = activeEntry?.startMinutes ?? currentMinutes

        // Build a set of original lines that should be struck out
        let pastOriginalLines = Set(
            timeEntries
                .filter { $0.endMinutes <= cutoffMinutes }
                .map { $0.originalLine.trimmingCharacters(in: .whitespacesAndNewlines) }
        )

        guard !pastOriginalLines.isEmpty else { return }

        // Walk through the notes and wrap matching lines with ~~
        var allLines = notesText.components(separatedBy: .newlines)

        var startLineIndex: Int?
        var endLineIndex: Int?
        for (index, line) in allLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "START" && startLineIndex == nil {
                startLineIndex = index
            } else if trimmed == "END" && startLineIndex != nil && endLineIndex == nil {
                endLineIndex = index
                break
            }
        }

        guard let startIdx = startLineIndex, let endIdx = endLineIndex, startIdx < endIdx else { return }

        for lineIdx in (startIdx + 1)..<endIdx {
            let line = allLines[lineIdx]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip already struck-through or empty lines
            guard !trimmed.isEmpty,
                  !(trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")) else { continue }

            if pastOriginalLines.contains(trimmed) {
                allLines[lineIdx] = "~~\(trimmed)~~"
            }
        }

        notesText = allLines.joined(separator: "\n")
        editorKey = UUID()
        saveNotes()
    }

    // MARK: - Smart Pause/Resume Logic
    
    private func handleSmartPause() {
        print("🔘 Smart Pause button clicked, pausedAt: \(pausedAt?.description ?? "nil")")
        
        if pausedAt != nil {
            // Resume - calculate pause duration and adjust schedule
            print("▶️ Resuming from smart pause")
            resumeWithScheduleAdjustment()
        } else {
            // Pause - record the pause time AND pause the timer
            print("⏸️ Starting smart pause")
            pausedAt = Date()
            savePauseState()

            // Cancel the AlertSettings internal timer so handleAlertFire() never fires
            // while paused (stopTimer does NOT touch isPlaying, UI stays in Stop state)
            settings.stopTimer()
            if #available(iOS 16.1, *) {
                LiveActivityManager.shared.pauseFocusActivity()
            }
            settings.isPaused = true
            
            let announcement = "Smart pause activated. Schedule will adjust on resume."
            speechManager.speak(announcement)
            
            print("⏸️ Smart Paused at \(currentTimeString), pausedAt now: \(pausedAt?.description ?? "nil")")
        }
    }
    
    private func resumeWithScheduleAdjustment() {
        guard let pauseStartTime = pausedAt else {
            print("⚠️ No pause time recorded")
            return
        }
        
        // Calculate how long we were paused
        let pauseDuration = Date().timeIntervalSince(pauseStartTime)
        let pauseMinutes = Int(ceil(pauseDuration / 60.0))
        
        print("▶️ Smart Resuming after \(pauseMinutes) minute pause")
        
        // Adjust the schedule by the pause duration (pass pause time before clearing it)
        adjustTimesInNotesByWithPauseTime(pauseMinutes, pauseTime: pauseStartTime)
        
        // Update total paused duration and reset pause time
        totalPausedDuration = totalPausedDuration + pauseDuration
        pausedAt = nil
        savePauseState()
        
        // Resume the timer (keep isPlaying true, just unpause)
        settings.isPaused = false
        
        let announcement = "Resuming after \(pauseMinutes) minute pause. Schedule adjusted."
        speechManager.speak(announcement)
        
        print("✅ Schedule adjusted by +\(pauseMinutes) minutes")
        
        // Restart smart cycles with the adjusted schedule
        startSmartCycles()
    }
    
    private func adjustTimesInNotesByWithPauseTime(_ minutes: Int, pauseTime: Date) {
        // Find START and END tags
        let startTag = "START"
        let endTag = "END"
        
        guard let startRange = notesText.range(of: startTag),
              let endRange = notesText.range(of: endTag) else {
            print("Could not find START and END tags")
            return
        }
        
        // Extract content between START and END
        let contentStart = startRange.upperBound
        let contentEnd = endRange.lowerBound
        let content = String(notesText[contentStart..<contentEnd])
        
        // Get the time when we PAUSED to determine which task was current
        let calendar = Calendar.current
        let pauseMinutes = calendar.component(.hour, from: pauseTime) * 60 + calendar.component(.minute, from: pauseTime)
        
        // Get current time NOW (when resuming) for the new start time
        let now = Date()
        let resumeMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        
        print("🔍 Pause time: \(safeMinutesToTime(pauseMinutes)), Resume time: \(safeMinutesToTime(resumeMinutes)), Pause duration: \(minutes) minutes")
        
        // Parse and adjust times using pause time to identify current task, resume time for new start
        let adjustedContent = adjustFutureTimeRanges(in: content, byMinutes: minutes, pauseMinutes: pauseMinutes, resumeMinutes: resumeMinutes)
        
        // Replace the content between START and END
        let beforeStart = String(notesText[..<startRange.lowerBound])
        let afterEnd = String(notesText[endRange.upperBound...])
        
        notesText = beforeStart + startTag + adjustedContent + endTag + afterEnd
        
        // Force the editor to refresh
        editorKey = UUID()
        
        // Save the adjusted notes
        saveNotes()
    }
    
    private func adjustFutureTimeRanges(in content: String, byMinutes minutes: Int, pauseMinutes: Int, resumeMinutes: Int) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result: [String] = []
        var foundCurrent = false
        var pausedTaskOriginalEnd: Int = 0
        var prevEnd: Int? = nil

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("~~") && trimmedLine.hasSuffix("~~") {
                result.append(line)
                continue
            }
            if trimmedLine.contains("~~") {
                result.append(line)
                continue
            }

            if let entry = parseTimeEntrySequential(line, previousEndMinutes: prevEnd) {
                if entry.isFixed {
                    result.append(line)
                    prevEnd = entry.endMinutes
                    continue
                }

                let wasCurrentTask = pauseMinutes >= entry.startMinutes && pauseMinutes < entry.endMinutes

                if wasCurrentTask {
                    foundCurrent = true
                    pausedTaskOriginalEnd = entry.endMinutes  // e.g. 780 (1:00 PM)

                    // Extract base number if present
                    var baseNum: Int? = nil
                    if let pIdx = trimmedLine.firstIndex(of: ")") {
                        baseNum = Int(String(trimmedLine[trimmedLine.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces))
                    }

                    let remaining = entry.endMinutes - pauseMinutes

                    // Part 1: elapsed portion (original start → pause time)
                    let p1Num = baseNum.map { "\($0)) " } ?? ""
                    result.append("\(p1Num)\(safeMinutesToTime(entry.startMinutes)) - \(safeMinutesToTime(pauseMinutes)) - \(entry.description)")

                    // Part 2: pause block (pause time → resume time)
                    let p2Num = baseNum.map { "\($0 + 1)) " } ?? ""
                    result.append("\(p2Num)\(safeMinutesToTime(pauseMinutes)) - \(safeMinutesToTime(resumeMinutes)) - pause")

                    // Part 3: resume remaining (resume time → resume + remaining)
                    let p3Num = baseNum.map { "\($0 + 2)) " } ?? ""
                    result.append("\(p3Num)\(safeMinutesToTime(resumeMinutes)) - \(safeMinutesToTime(resumeMinutes + remaining)) - \(entry.description)")

                    prevEnd = resumeMinutes + remaining

                } else if foundCurrent && entry.startMinutes >= pausedTaskOriginalEnd && !entry.isFixed {
                    // Future task: starts at or after the original end of the paused task
                    // Shift by pause duration + bump number by +2
                    var shiftedNum: Int? = nil
                    if let pIdx = trimmedLine.firstIndex(of: ")") {
                        shiftedNum = Int(String(trimmedLine[trimmedLine.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)).map { $0 + 2 }
                    }
                    let numStr = shiftedNum.map { "\($0)) " } ?? ""
                    let newStart = safeMinutesToTime(entry.startMinutes + minutes)
                    let newEnd   = safeMinutesToTime(entry.endMinutes + minutes)
                    result.append("\(numStr)\(newStart) - \(newEnd) - \(entry.description)")
                    prevEnd = entry.endMinutes + minutes

                } else {
                    // Past task — keep as is
                    result.append(line)
                    prevEnd = entry.endMinutes
                }
            } else {
                result.append(line)
            }
        }

        return result.joined(separator: "\n")
    }
    
    private func formatPauseDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    // MARK: - Persistence Helpers
    
    private func loadPauseState() {
        pausedAt = UserDefaults.standard.object(forKey: "DailyNotesView.pausedAt") as? Date
        totalPausedDuration = UserDefaults.standard.double(forKey: "DailyNotesView.totalPausedDuration")
    }
    
    private func savePauseState() {
        if let date = pausedAt {
            UserDefaults.standard.set(date, forKey: "DailyNotesView.pausedAt")
        } else {
            UserDefaults.standard.removeObject(forKey: "DailyNotesView.pausedAt")
        }
        UserDefaults.standard.set(totalPausedDuration, forKey: "DailyNotesView.totalPausedDuration")
    }
    
    private func handleCycleCompletion() {
        guard !isTransitioning else {
            print("⚠️ Already transitioning, skipping duplicate call")
            return
        }
        isTransitioning = true
        print("🔔 Cycle completed! Transitioning to next task...")
        speechManager.speak("\(currentTaskName) completed")
        cycleEndObserver?.cancel()

        // Capture scheduled end time before state changes
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        let entries = extractTimeEntriesFromNotes()
        if let curr = entries.first(where: { $0.description == currentTaskName && abs($0.endMinutes - nowMin) <= 3 }) {
            pendingTaskEndMinutes = curr.endMinutes
        } else {
            pendingTaskEndMinutes = nowMin
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.manualModeEnabled {
                let reentries = self.extractTimeEntriesFromNotes()
                let nowMin2 = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
                if let next = reentries.first(where: { $0.startMinutes >= self.pendingTaskEndMinutes }) {
                    self.pendingNextTaskName = next.description
                    self.pendingPreviousTaskName = self.currentTaskName
                    self.isTransitioning = false
                    self.settings.isPlaying = false
                    self.isWaitingForManualStart = true
                    // Anchor to the scheduled end time so backgrounded idle counts correctly
                    self.manualWaitStartDate = self.settings.nextAlertDate
                    self.speechManager.speak("Tap play when ready for \(next.description)")
                } else {
                    self.isTransitioning = false
                    self.stopCycles()
                }
            } else {
                self.startNextCycle()
            }
        }
    }
    
    // MARK: - Manual Mode Helpers

    private func startManualWaitCountUp() {
        // Count-up is derived from manualWaitStartDate; no tick timer needed
    }

    private func stopManualWaitCountUp() {
        // No-op — count-up is wall-clock based
    }

    private func startManualNextTask() {
        let waited = max(0, Int(Date().timeIntervalSince(manualWaitStartDate ?? Date())))
        totalIdleSeconds += waited

        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())

        if nowMin > pendingTaskEndMinutes {
            insertIdleBlock(fromMinutes: pendingTaskEndMinutes, toMinutes: nowMin)
        }

        isWaitingForManualStart = false
        manualWaitStartDate = nil
        startNextCycle()
    }

    private func extendPreviousTaskAndStart() {
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        let extendBy = nowMin - pendingTaskEndMinutes
        let prevName = pendingPreviousTaskName

        if extendBy > 0,
           let startTagRange = notesText.range(of: "START"),
           let endTagRange   = notesText.range(of: "END") {

            let content = String(notesText[startTagRange.upperBound..<endTagRange.lowerBound])
            let lines   = content.components(separatedBy: .newlines)
            var result: [String] = []
            var prevEnd: Int? = nil
            var didExtend = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")) || trimmed.contains("~~") {
                    result.append(line)
                    continue
                }
                if let entry = parseTimeEntrySequential(line, previousEndMinutes: prevEnd) {
                    if !didExtend && entry.endMinutes == pendingTaskEndMinutes && entry.description == prevName {
                        didExtend = true
                        var numStr = ""
                        if let pIdx = trimmed.firstIndex(of: ")"),
                           let n = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)) {
                            numStr = "\(n)) "
                        }
                        result.append("\(numStr)\(safeMinutesToTime(entry.startMinutes)) - \(safeMinutesToTime(nowMin)) - \(entry.description)")
                        prevEnd = nowMin
                    } else if didExtend && !entry.isFixed {
                        var shiftedNum: Int? = nil
                        if let pIdx = trimmed.firstIndex(of: ")") {
                            shiftedNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces))
                        }
                        let numStr   = shiftedNum.map { "\($0)) " } ?? ""
                        let newStart = safeMinutesToTime(entry.startMinutes + extendBy)
                        let newEnd   = safeMinutesToTime(entry.endMinutes   + extendBy)
                        result.append("\(numStr)\(newStart) - \(newEnd) - \(entry.description)")
                        prevEnd = entry.endMinutes + extendBy
                    } else {
                        result.append(line)
                        prevEnd = entry.endMinutes
                    }
                } else {
                    result.append(line)
                }
            }

            let beforeStart = String(notesText[..<startTagRange.lowerBound])
            let afterEnd    = String(notesText[endTagRange.upperBound...])
            notesText = beforeStart + "START" + result.joined(separator: "\n") + "END" + afterEnd
            editorKey = UUID()
            saveNotes()
            if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
        }

        isWaitingForManualStart = false
        manualWaitStartDate = nil
        startNextCycle()
    }

    private func insertIdleBlock(fromMinutes: Int, toMinutes: Int) {
        guard toMinutes > fromMinutes else { return }
        let idleMinutes = toMinutes - fromMinutes

        guard let startTagRange = notesText.range(of: "START"),
              let endTagRange   = notesText.range(of: "END") else { return }

        let content = String(notesText[startTagRange.upperBound..<endTagRange.lowerBound])
        let lines   = content.components(separatedBy: .newlines)
        var result: [String] = []
        var prevEnd: Int? = nil
        var insertedIdle = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")) || trimmed.contains("~~") {
                result.append(line)
                continue
            }

            if let entry = parseTimeEntrySequential(line, previousEndMinutes: prevEnd) {
                if !insertedIdle && entry.startMinutes >= fromMinutes {
                    insertedIdle = true
                    var baseNum: Int? = nil
                    if let pIdx = trimmed.firstIndex(of: ")") {
                        baseNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces))
                    }
                    let idleNum  = baseNum.map { "\($0)) " } ?? ""
                    result.append("\(idleNum)\(safeMinutesToTime(fromMinutes)) - \(safeMinutesToTime(toMinutes)) - idle")

                    if !entry.isFixed {
                        let taskNum  = baseNum.map { "\($0 + 1)) " } ?? ""
                        let duration = entry.endMinutes - entry.startMinutes
                        result.append("\(taskNum)\(safeMinutesToTime(toMinutes)) - \(safeMinutesToTime(toMinutes + duration)) - \(entry.description)")
                        prevEnd = toMinutes + duration
                    } else {
                        result.append(line)
                        prevEnd = entry.endMinutes
                    }
                } else if insertedIdle && !entry.isFixed {
                    var shiftedNum: Int? = nil
                    if let pIdx = trimmed.firstIndex(of: ")") {
                        shiftedNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)).map { $0 + 1 }
                    }
                    let numStr   = shiftedNum.map { "\($0)) " } ?? ""
                    let newStart = safeMinutesToTime(entry.startMinutes + idleMinutes)
                    let newEnd   = safeMinutesToTime(entry.endMinutes   + idleMinutes)
                    result.append("\(numStr)\(newStart) - \(newEnd) - \(entry.description)")
                    prevEnd = entry.endMinutes + idleMinutes
                } else {
                    result.append(line)
                    prevEnd = entry.endMinutes
                }
            } else {
                result.append(line)
            }
        }

        let beforeStart = String(notesText[..<startTagRange.lowerBound])
        let afterEnd    = String(notesText[endTagRange.upperBound...])
        notesText = beforeStart + "START" + result.joined(separator: "\n") + "END" + afterEnd
        editorKey = UUID()
        saveNotes()
        if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
    }

    // MARK: - Insert Named Block During Gap (Rest up)

    @discardableResult
    private func insertNamedBlockAtGap(blockName: String, blockDuration: Int, nowMin: Int) -> Bool {
        let timeEntries = extractTimeEntriesFromNotes()
        let blockEnd = nowMin + blockDuration

        guard let nextTask = timeEntries.first(where: { $0.startMinutes >= nowMin }) else {
            guard let startTagRange = notesText.range(of: "START"),
                  let endTagRange   = notesText.range(of: "END") else { return false }
            let newLine     = "\(safeMinutesToTime(nowMin)) - \(safeMinutesToTime(blockEnd)) - \(blockName)"
            let content     = String(notesText[startTagRange.upperBound..<endTagRange.lowerBound])
            let beforeStart = String(notesText[..<startTagRange.lowerBound])
            let afterEnd    = String(notesText[endTagRange.upperBound...])
            notesText = beforeStart + "START" + content + "\n" + newLine + "\nEND" + afterEnd
            editorKey = UUID(); saveNotes(); return true
        }

        let shiftAmount = max(0, blockEnd - nextTask.startMinutes)
        guard let startTagRange = notesText.range(of: "START"),
              let endTagRange   = notesText.range(of: "END") else { return false }

        let lines = String(notesText[startTagRange.upperBound..<endTagRange.lowerBound])
                        .components(separatedBy: .newlines)
        var result: [String] = []
        var prevEnd: Int? = nil
        var insertedBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")) || trimmed.contains("~~") {
                result.append(line); continue
            }
            if let entry = parseTimeEntrySequential(line, previousEndMinutes: prevEnd) {
                if !insertedBlock && entry.startMinutes == nextTask.startMinutes
                                  && entry.description  == nextTask.description {
                    insertedBlock = true
                    var baseNum: Int? = nil
                    if let pIdx = trimmed.firstIndex(of: ")") {
                        baseNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces))
                    }
                    let blockNum = baseNum.map { "\($0)) " } ?? ""
                    result.append("\(blockNum)\(safeMinutesToTime(nowMin)) - \(safeMinutesToTime(blockEnd)) - \(blockName)")
                    let taskNum  = baseNum.map { "\($0 + 1)) " } ?? ""
                    let dur      = entry.endMinutes - entry.startMinutes
                    let newStart = entry.startMinutes + shiftAmount
                    result.append("\(taskNum)\(safeMinutesToTime(newStart)) - \(safeMinutesToTime(newStart + dur)) - \(entry.description)")
                    prevEnd = newStart + dur
                } else if insertedBlock && !entry.isFixed {
                    var shiftedNum: Int? = nil
                    if let pIdx = trimmed.firstIndex(of: ")") {
                        shiftedNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)).map { $0 + 1 }
                    }
                    let numStr = shiftedNum.map { "\($0)) " } ?? ""
                    result.append("\(numStr)\(safeMinutesToTime(entry.startMinutes + shiftAmount)) - \(safeMinutesToTime(entry.endMinutes + shiftAmount)) - \(entry.description)")
                    prevEnd = entry.endMinutes + shiftAmount
                } else {
                    result.append(line); prevEnd = entry.endMinutes
                }
            } else { result.append(line) }
        }

        let beforeStart = String(notesText[..<startTagRange.lowerBound])
        let afterEnd    = String(notesText[endTagRange.upperBound...])
        notesText = beforeStart + "START" + result.joined(separator: "\n") + "END" + afterEnd
        editorKey = UUID(); saveNotes()
        if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
        return true
    }

    private func formatWaitCountUp(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func recalculateTotalIdleTime() {
        let entries = extractTimeEntriesFromNotes()
        let idleSeconds = entries
            .filter { $0.description.trimmingCharacters(in: .whitespaces).lowercased() == "idle" }
            .reduce(0) { $0 + ($1.endMinutes - $1.startMinutes) * 60 }
        totalIdleSeconds = idleSeconds
    }

    private func extractTimeEntriesFromNotes() -> [TimeEntry] {
        // Find START and END tags - ensure they are on their own lines
        let startTag = "START"
        let endTag = "END"
        
        // Split notes into lines first to find exact tag matches
        let allLines = notesText.components(separatedBy: .newlines)
        
        // Find the line indices for START and END tags
        var startLineIndex: Int?
        var endLineIndex: Int?
        
        for (index, line) in allLines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine == startTag && startLineIndex == nil {
                startLineIndex = index
            } else if trimmedLine == endTag && startLineIndex != nil && endLineIndex == nil {
                endLineIndex = index
                break // Take the first END after START
            }
        }
        
        guard let startIndex = startLineIndex,
              let endIndex = endLineIndex,
              startIndex < endIndex else {
            print("❌ No valid START/END tags found in notes (START must come before END)")
            return []
        }
        
        // Extract only the lines between START and END (exclusive)
        let contentLines = Array(allLines[(startIndex + 1)..<endIndex])
        
        var timeEntries: [TimeEntry] = []
        var previousEndMinutes: Int? = nil
        
        print("📝 Parsing schedule from notes (lines \(startIndex + 1) to \(endIndex - 1)):")
        print("📝 Content to parse: \(contentLines.count) lines")
        
        for (lineIndex, line) in contentLines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            if trimmedLine.isEmpty {
                continue
            }
            
            if let entry = parseTimeEntrySequential(line, previousEndMinutes: previousEndMinutes) {
                timeEntries.append(entry)
                previousEndMinutes = entry.endMinutes
                
                // Add safety checks to prevent EXC_BAD_ACCESS
                let startTimeStr = safeMinutesToTime(entry.startMinutes)
                let endTimeStr = safeMinutesToTime(entry.endMinutes)
                let description = entry.description.isEmpty ? "No description" : entry.description
                print("✅ Parsed line \(lineIndex + 1): \(startTimeStr) - \(endTimeStr) - \(description)")
            } else {
                print("⚠️ Could not parse line \(lineIndex + 1): '\(trimmedLine)'")
            }
        }
        
        print("📅 Final schedule (\(timeEntries.count) entries):")
        for entry in timeEntries {
            let startTimeStr = safeMinutesToTime(entry.startMinutes)
            let endTimeStr = safeMinutesToTime(entry.endMinutes)
            let description = entry.description.isEmpty ? "No description" : entry.description
            print("   \(startTimeStr) - \(endTimeStr) - \(description)")
        }
        
        return timeEntries
    }
    
    // MARK: - Existing Methods (unchanged)
    
    private func loadNotesForDate(_ date: Date) {
        if let existingNote = getNoteForDate(date) {
            notesText = existingNote.content
        } else {
            // No note exists for this date — clear any stale distraction data too
            notesText = ""
            distractionTracker.clearDay(date: date)
        }
        editorKey = UUID()
        showFormattedSchedule = hasSchedule
    }
    
    private func saveNotes() {
        if let existingNote = getNoteForDate(selectedDate) {
            existingNote.updateContent(notesText)
        } else if !notesText.isEmpty {
            let newNote = DailyNote(date: selectedDate, content: notesText)
            modelContext.insert(newNote)
        }

        try? modelContext.save()
        scheduleRenderID = UUID()
    }

    // MARK: - Template Helpers

    /// Extracts the START…END block (inclusive) from the current notes, nil if absent.
    private var currentScheduleBlock: String? {
        let lines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil
        var eIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return nil }
        return lines[s...e].joined(separator: "\n")
    }

    /// Applies templates. The first template replaces the block only if no non-empty block exists;
    /// otherwise it is intercept-merged like all subsequent templates.
    private func applyTemplates(_ templates: [ScheduleTemplate]) {
        guard !templates.isEmpty else { return }

        func taskLines(from template: ScheduleTemplate) -> [String] {
            var result: [String] = []
            var inBlock = false
            for line in template.content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "START" { inBlock = true; continue }
                if trimmed == "END"   { inBlock = false; continue }
                if inBlock {
                    // If this is a reward template, stamp each non-empty task line with [🎁]
                    if template.isReward && !trimmed.isEmpty && !trimmed.contains("[🎁]") {
                        result.append(line.replacingOccurrences(of: trimmed, with: trimmed + " [🎁]"))
                    } else {
                        result.append(line)
                    }
                }
            }
            return result
        }

        // Check whether a non-empty START…END block already exists in the notes.
        func existingBlockIsEmpty() -> Bool {
            let lines = notesText.components(separatedBy: .newlines)
            var inside = false
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t == "START" { inside = true; continue }
                if t == "END"   { return true }
                if inside && !t.isEmpty { return false }
            }
            return true
        }

        let timePattern = #"(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)"#
        let timeRegex = try? NSRegularExpression(pattern: timePattern)

        func interceptTemplate(_ template: ScheduleTemplate) {
            let lines = taskLines(from: template).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard !lines.isEmpty else { return }

            var firstStartMin: Int? = nil
            if let re = timeRegex {
                for line in lines {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                       let sr = Range(m.range(at: 1), in: t),
                       let startMin = interceptParseMinutes(String(t[sr])) {
                        firstStartMin = startMin
                        break
                    }
                }
            }

            let allLines = notesText.components(separatedBy: .newlines)
            var s2: Int? = nil, e2: Int? = nil
            for (i, line) in allLines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t == "START" && s2 == nil { s2 = i }
                else if t == "END" && s2 != nil && e2 == nil { e2 = i; break }
            }

            let afterNum: Int
            if let s = s2, let e = e2, let targetMin = firstStartMin {
                afterNum = taskNumBefore(minutes: targetMin, in: allLines, startIdx: s, endIdx: e)
            } else {
                afterNum = 0
            }
            processGroupedIntercept(lines: lines, firstGroupAfterNum: afterNum)
        }

        // Decide whether template[0] replaces the block or is intercept-merged.
        if existingBlockIsEmpty() {
            // No existing content — replace with template[0] as the base.
            let baseLines = renumberedLines(taskLines(from: templates[0]), from: 1)
            let combinedBase = ["START"] + baseLines + ["END"]
            var currentLines = notesText.components(separatedBy: .newlines)
            var sIdx: Int? = nil, eIdx: Int? = nil
            for (i, line) in currentLines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t == "START" && sIdx == nil { sIdx = i }
                else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
            }
            if let s = sIdx, let e = eIdx {
                currentLines.replaceSubrange(s...e, with: combinedBase)
            } else {
                if currentLines.last?.isEmpty == false { currentLines.append("") }
                currentLines.append(contentsOf: combinedBase)
            }
            notesText = currentLines.joined(separator: "\n")

            // Intercept remaining templates.
            for template in templates.dropFirst() {
                interceptTemplate(template)
            }
        } else {
            // Existing block has content — intercept-merge all templates.
            for template in templates {
                interceptTemplate(template)
            }
        }

        editorKey = UUID()
        saveNotes()
    }

    /// Returns the task number of the last task whose start time is strictly less than `targetMinutes`.
    /// Returns 0 when all tasks start at or after `targetMinutes` (caller should insert at beginning).
    private func taskNumBefore(minutes targetMin: Int, in allLines: [String], startIdx: Int, endIdx: Int) -> Int {
        let timePattern = #"(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)"#
        guard let timeRegex = try? NSRegularExpression(pattern: timePattern) else { return 0 }
        var result = 0
        for i in (startIdx + 1)..<endIdx {
            let t = allLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            guard let pIdx = t.firstIndex(of: ")"),
                  let num = Int(String(t[t.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)),
                  !t[t.startIndex..<pIdx].contains(" "), num > 0, num < 1000 else { continue }
            guard let m = timeRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let sr = Range(m.range(at: 1), in: t),
                  let startMin = interceptParseMinutes(String(t[sr])) else { continue }
            if startMin < targetMin { result = num }
        }
        return result
    }

    /// Returns the task number of the currently-running task and the next task.
    private func currentAndNextTaskNums() -> (current: Int?, next: Int?) {
        let cal = Calendar.current
        let now = Date()
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil, eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return (nil, nil) }

        struct NumberedEntry { let num: Int?; let startMin: Int; let endMin: Int }
        var entries: [NumberedEntry] = []
        var prevEnd: Int? = nil

        for i in (s + 1)..<e {
            let raw = allLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }
            let isStruck = raw.hasPrefix("~~") && raw.hasSuffix("~~")
            if isStruck { continue }
            guard let entry = parseTimeEntrySequential(raw, previousEndMinutes: prevEnd) else { continue }
            var num: Int? = nil
            if let pIdx = raw.firstIndex(of: ")"),
               let n = Int(String(raw[raw.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)),
               n > 0 && n < 1000, !raw[raw.startIndex..<pIdx].contains(" ") {
                num = n
            }
            entries.append(NumberedEntry(num: num, startMin: entry.startMinutes, endMin: entry.endMinutes))
            prevEnd = entry.endMinutes
        }

        if let idx = entries.firstIndex(where: { $0.startMin <= nowMin && $0.endMin > nowMin }) {
            let next = idx + 1 < entries.count ? entries[idx + 1].num : nil
            return (entries[idx].num, next)
        }
        // If between tasks or before first, return first not-yet-started task + following
        if let idx = entries.firstIndex(where: { $0.startMin > nowMin }) {
            let next = idx + 1 < entries.count ? entries[idx + 1].num : nil
            return (entries[idx].num, next)
        }
        return (nil, nil)
    }

    // MARK: - Distraction Tracking

    /// Returns (startMin, desc) of the schedule task that is active right now, or nil.
    private func currentActiveTaskInfo() -> (startMin: Int, desc: String)? {
        let nowMin = Calendar.current.component(.hour, from: Date()) * 60
                   + Calendar.current.component(.minute, from: Date())
        let tasks = parseFormattedTaskItems()
        guard let task = tasks.first(where: { !$0.struck && nowMin >= $0.start && nowMin < $0.end })
        else { return nil }
        return (task.start, task.desc)
    }

    /// Increment the distraction count for whatever task is current right now and record the exit time.
    private func trackDistraction() {
        guard let info = currentActiveTaskInfo() else { return }
        let schedule = parseFormattedTaskItems()
            .filter { !$0.struck }
            .map { (startMin: $0.start, endMin: $0.end, desc: $0.desc) }
        // Only record the exit timestamp — count is recorded only if user confirms on return
        distractionTracker.recordExit(date: selectedDate, startMin: info.startMin, desc: info.desc,
                                      schedule: schedule)
    }

    /// Called when the user returns to DailyNotes (onAppear or didBecomeActive).
    /// Shows a prompt to confirm whether the absence was a distraction before recording it.
    private func handleReturn() {
        guard distractionTracker.hasPendingExit else { return }
        let secs = Int(distractionTracker.pendingAbsenceSeconds)
        guard secs >= 5 else {
            // Too short to bother — settle silently without incrementing
            let affected = distractionTracker.settleReturn(selectedDate: selectedDate)
            for result in affected {
                guard Calendar.current.isDate(result.date, inSameDayAs: selectedDate) else { continue }
                writeMetricsToNotesText(startMin: result.startMin, desc: result.desc)
            }
            return
        }
        pendingDistractionAbsenceSecs = secs
        showDistractionPrompt = true
    }

    private func confirmDistraction() {
        // Settle duration + increment count
        let affected = distractionTracker.settleReturn(selectedDate: selectedDate)
        for result in affected {
            guard Calendar.current.isDate(result.date, inSameDayAs: selectedDate) else { continue }
            distractionTracker.increment(date: result.date, startMin: result.startMin, desc: result.desc)
            writeMetricsToNotesText(startMin: result.startMin, desc: result.desc)
        }
    }

    private func dismissDistraction() {
        distractionTracker.cancelPendingExit()
    }

    /// Writes (or updates) the metrics suffix " /N ~Xm" on the matching task line in notes text.
    private func writeMetricsToNotesText(startMin: Int, desc: String) {
        var lines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil, eIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return }
        var prevEnd: Int? = nil
        for i in (s + 1)..<e {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            if let entry = parseTimeEntrySequential(parseLine, previousEndMinutes: prevEnd) {
                if entry.startMinutes == startMin && entry.description == desc {
                    var rawLine = lines[i]
                    // Strip existing metrics suffix
                    if let r = rawLine.range(of: DistractionTracker.metricsSuffixPattern, options: .regularExpression) {
                        rawLine.removeSubrange(r)
                    }
                    let count = distractionTracker.count(date: selectedDate, startMin: startMin, desc: desc)
                    let secs  = distractionTracker.duration(date: selectedDate, startMin: startMin, desc: desc)
                    rawLine += distractionTracker.metricsSuffix(count: count, seconds: secs)
                    lines[i] = rawLine
                    break
                }
                prevEnd = entry.endMinutes
            }
        }
        notesText = lines.joined(separator: "\n")
        saveNotes()
    }

    /// Parses all task lines in the notes and extracts distraction metrics from "/N ~Xm" suffixes.
    func parsedDistractionEntries() -> [(startMin: Int, desc: String, count: Int, seconds: TimeInterval)] {
        var results: [(startMin: Int, desc: String, count: Int, seconds: TimeInterval)] = []
        let allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil, eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return [] }
        var prevEnd: Int? = nil
        for i in (s + 1)..<e {
            let trimmed = allLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            // Extract the raw suffix before stripping it via parseTimeEntrySequential
            var count = 0
            var seconds: TimeInterval = 0
            if let suffixRange = parseLine.range(of: DistractionTracker.metricsSuffixPattern, options: .regularExpression) {
                let suffix = String(parseLine[suffixRange])
                // Parse count: /N
                if let countRange = suffix.range(of: #"/(\d+)"#, options: .regularExpression),
                   let n = Int(suffix[countRange].dropFirst()) { count = n }
                // Parse ~Xh Ym, ~Xh, ~Xm Ys, ~Xm, ~Xs
                if let hmRange = suffix.range(of: #"~(\d+)h\s*(\d+)m"#, options: .regularExpression) {
                    let parts = suffix[hmRange].replacingOccurrences(of: "~", with: "")
                        .components(separatedBy: CharacterSet.letters).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    if parts.count >= 2 { seconds = TimeInterval(parts[0] * 3600 + parts[1] * 60) }
                } else if let hRange = suffix.range(of: #"~(\d+)h"#, options: .regularExpression) {
                    let digits = suffix[hRange].filter { $0.isNumber }
                    if let h = Int(digits) { seconds = TimeInterval(h * 3600) }
                } else if let msRange = suffix.range(of: #"~(\d+)m\s*(\d+)s"#, options: .regularExpression) {
                    let parts = suffix[msRange].replacingOccurrences(of: "~", with: "")
                        .components(separatedBy: CharacterSet.letters).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    if parts.count >= 2 { seconds = TimeInterval(parts[0] * 60 + parts[1]) }
                } else if let mRange = suffix.range(of: #"~(\d+)m"#, options: .regularExpression) {
                    let digits = suffix[mRange].filter { $0.isNumber }
                    if let m = Int(digits) { seconds = TimeInterval(m * 60) }
                } else if let sRange = suffix.range(of: #"~(\d+)s"#, options: .regularExpression) {
                    let digits = suffix[sRange].filter { $0.isNumber }
                    if let s = Int(digits) { seconds = TimeInterval(s) }
                }
            }
            // parseTimeEntrySequential skips struck lines, so pass the unwrapped parseLine directly
            if let entry = parseTimeEntrySequential(parseLine, previousEndMinutes: prevEnd) {
                if count > 0 {
                    results.append((startMin: entry.startMinutes, desc: entry.description, count: count, seconds: seconds))
                }
                prevEnd = entry.endMinutes
            }
        }
        return results
    }

    /// Returns the highest task number currently in notesText (pattern "N) ").
    private func maxScheduleNumber() -> Int {
        var maxNum = 0
        for line in notesText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.components(separatedBy: ")")
            if parts.count >= 2, let num = Int(parts[0].trimmingCharacters(in: .whitespaces)), !parts[0].contains(" ") {
                maxNum = max(maxNum, num)
            }
        }
        return maxNum
    }

    /// Re-numbers lines that match the "N) ..." pattern, starting from `startNum`.
    private func renumberedLines(_ lines: [String], from startNum: Int) -> [String] {
        var counter = startNum
        return lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.components(separatedBy: ")")
            if parts.count >= 2,
               let _ = Int(parts[0].trimmingCharacters(in: .whitespaces)),
               !parts[0].contains(" ") {
                let rest = parts.dropFirst().joined(separator: ")")
                let result = "\(counter))\(rest)"
                counter += 1
                return result
            }
            return line
        }
    }

    /// Generates a schedule block from the given tasks, `minutesPerTask` each, starting at
    /// `startTimeStr` (e.g. "12:30 PM"). Falls back to current time if empty or unparseable.
    /// Inserts at the correct position via `taskNumBefore` and uses wave-based shifting.
    private func autoGenerateSchedule(tasks: [Task], minutesPerTask: Int, startTimeStr: String = "") {
        guard !tasks.isEmpty else { return }
        let cal = Calendar.current
        let now = Date()

        let trimmed = startTimeStr.trimmingCharacters(in: .whitespaces)
        let startMin: Int
        if !trimmed.isEmpty, let parsed = interceptParseMinutes(trimmed) {
            startMin = parsed
        } else {
            startMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        }

        let startNum = maxScheduleNumber() + 1
        var newLines: [String] = []
        for (i, task) in tasks.enumerated() {
            let taskStart = startMin + i * minutesPerTask
            let taskEnd   = taskStart + minutesPerTask
            newLines.append("\(startNum + i)) \(safeMinutesToTime(taskStart)) - \(safeMinutesToTime(taskEnd)) - \(task.title)")
        }

        let allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil, eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }

        if let s = sIdx, let e = eIdx {
            // Find insertion point and let coreIntercept compute the exact shift + wave
            let afterNum = taskNumBefore(minutes: startMin, in: allLines, startIdx: s, endIdx: e)
            processGroupedIntercept(lines: newLines, firstGroupAfterNum: afterNum)
        } else {
            // No START/END block yet — create one
            var lines = notesText.components(separatedBy: .newlines)
            if lines.last?.isEmpty == false { lines.append("") }
            lines.append("START")
            lines.append(contentsOf: newLines)
            lines.append("END")
            notesText = lines.joined(separator: "\n")
            editorKey = UUID()
            saveNotes()
        }
    }
    
    /// Inserts an AI-generated START…END schedule block into the notes.
    /// If a block already exists the new lines are merged at the end; otherwise a new block is created.
    private func insertAISchedule(_ block: String) {
        let blockLines = block.components(separatedBy: .newlines)
        // Strip the START / END wrapper — just the numbered task lines
        let newLines = blockLines.filter { l in
            let t = l.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && t != "START" && t != "END"
        }
        guard !newLines.isEmpty else { return }

        var lines = notesText.components(separatedBy: .newlines)
        if let eIdx = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "END" }) {
            // Insert before END
            lines.insert(contentsOf: newLines, at: eIdx)
        } else if let sIdx = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "START" }) {
            lines.insert(contentsOf: newLines + ["END"], at: sIdx + 1)
        } else {
            // No block yet — create one
            if lines.last?.isEmpty == false { lines.append("") }
            lines.append("START")
            lines.append(contentsOf: newLines)
            lines.append("END")
        }
        notesText = lines.joined(separator: "\n")
        editorKey = UUID()
        saveNotes()
    }

    private func adjustTimesInNotes() {
        guard let minutes = Int(adjustmentMinutes) else { 
            print("Invalid minutes input: \(adjustmentMinutes)")
            return 
        }
        
        // Find START and END tags
        let startTag = "START"
        let endTag = "END"
        
        guard let startRange = notesText.range(of: startTag),
              let endRange = notesText.range(of: endTag) else {
            print("Could not find START and END tags")
            return
        }
        
        // Extract content between START and END
        let contentStart = startRange.upperBound
        let contentEnd = endRange.lowerBound
        let content = String(notesText[contentStart..<contentEnd])
        
        print("Content to process: '\(content)'")
        
        // Parse and adjust times
        let adjustedContent = adjustTimeRanges(in: content, byMinutes: minutes)
        
        print("Adjusted content: '\(adjustedContent)'")
        
        // Replace the content between START and END
        let beforeStart = String(notesText[..<startRange.lowerBound])
        let afterEnd = String(notesText[endRange.upperBound...])
        
        notesText = beforeStart + startTag + adjustedContent + endTag + afterEnd
        
        // Force the editor to refresh by changing its key
        editorKey = UUID()
    }
    
    private func adjustTimeRanges(in content: String, byMinutes minutes: Int) -> String {
        let lines = content.components(separatedBy: .newlines)
        
        // Process each line individually while maintaining order
        var result: [String] = []
        var timeEntries: [TimeEntry] = []
        
        // First pass: collect all time entries and identify their positions
        for line in lines {
            if let entry = parseTimeEntry(line) {
                timeEntries.append(entry)
            }
        }
        
        // Apply smart time adjustment
        let adjustedEntries = smartAdjustTimeEntries(timeEntries, byMinutes: minutes)
        
        // Create a mapping of original entries to adjusted entries
        var adjustedMap: [String: [TimeEntry]] = [:]
        var adjustedIndex = 0
        
        for originalEntry in timeEntries {
            var entriesForOriginal: [TimeEntry] = []
            
            // Find all adjusted entries that came from this original entry
            while adjustedIndex < adjustedEntries.count {
                let adjustedEntry = adjustedEntries[adjustedIndex]
                if adjustedEntry.originalLine == originalEntry.originalLine {
                    entriesForOriginal.append(adjustedEntry)
                    adjustedIndex += 1
                } else {
                    break
                }
            }
            
            adjustedMap[originalEntry.originalLine] = entriesForOriginal
        }
        
        // Second pass: reconstruct with proper replacements
        for line in lines {
            if let originalEntry = parseTimeEntry(line) {
                // Replace with adjusted entries
                if let adjustedEntries = adjustedMap[originalEntry.originalLine] {
                    for adjustedEntry in adjustedEntries {
                        result.append(adjustedEntry.toLine())
                    }
                }
            } else {
                // Keep non-time lines as-is (including strikethrough)
                result.append(line)
            }
        }
        
        return result.joined(separator: "\n")
    }
    
    private func smartAdjustTimeEntries(_ entries: [TimeEntry], byMinutes minutes: Int) -> [TimeEntry] {
        guard !entries.isEmpty else { return entries }
        
        var result: [TimeEntry] = []
        
        for entry in entries {
            if entry.isFixed {
                // Fixed entries remain unchanged
                result.append(entry)
            } else {
                // Variable entries get adjusted
                let adjustedStartMinutes = entry.startMinutes + minutes
                let adjustedEndMinutes = entry.endMinutes + minutes
                
                // Check if this conflicts with any fixed task
                var conflictsWithFixed = false
                var conflictingFixedEntry: TimeEntry?
                
                for otherEntry in entries {
                    if otherEntry.isFixed && 
                       adjustedStartMinutes < otherEntry.endMinutes && 
                       adjustedEndMinutes > otherEntry.startMinutes {
                        conflictsWithFixed = true
                        conflictingFixedEntry = otherEntry
                        break
                    }
                }
                
                if conflictsWithFixed, let fixedEntry = conflictingFixedEntry {
                    // Handle conflict by adjusting the variable task to not overlap
                    
                    if adjustedStartMinutes < fixedEntry.startMinutes {
                        // Variable task starts before fixed task
                        // Truncate it to end when fixed task starts
                        let truncatedEntry = TimeEntry(
                            startMinutes: adjustedStartMinutes,
                            endMinutes: fixedEntry.startMinutes,
                            description: entry.description,
                            isFixed: false,
                            originalLine: entry.originalLine
                        )
                        result.append(truncatedEntry)
                        
                        // Calculate remaining duration and add it after the fixed task
                        let usedDuration = fixedEntry.startMinutes - adjustedStartMinutes
                        let remainingDuration = entry.duration - usedDuration
                        
                        if remainingDuration > 0 {
                            let continuedEntry = TimeEntry(
                                startMinutes: fixedEntry.endMinutes,
                                endMinutes: fixedEntry.endMinutes + remainingDuration,
                                description: "\(entry.description) (continued)",
                                isFixed: false,
                                originalLine: entry.originalLine
                            )
                            result.append(continuedEntry)
                        }
                    } else {
                        // Variable task starts during or after fixed task
                        // Move it to start after the fixed task
                        let movedEntry = TimeEntry(
                            startMinutes: fixedEntry.endMinutes,
                            endMinutes: fixedEntry.endMinutes + entry.duration,
                            description: entry.description,
                            isFixed: false,
                            originalLine: entry.originalLine
                        )
                        result.append(movedEntry)
                    }
                } else {
                    // No conflict, normal adjustment
                    let adjustedEntry = TimeEntry(
                        startMinutes: adjustedStartMinutes,
                        endMinutes: adjustedEndMinutes,
                        description: entry.description,
                        isFixed: false,
                        originalLine: entry.originalLine
                    )
                    result.append(adjustedEntry)
                }
            }
        }
        
        return result
    }
    
    private func parseTimeEntrySequential(_ line: String, previousEndMinutes: Int?) -> TimeEntry? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip strikethrough lines - check the entire line, not just if it contains ~~
        if trimmedLine.hasPrefix("~~") && trimmedLine.hasSuffix("~~") {
            return nil
        }
        
        // Also skip if the line contains ~~ anywhere (partial strikethrough)
        if trimmedLine.contains("~~") {
            return nil
        }
        
        // Remove numbering prefix if present (e.g., "1) ", "2) ", "123) ")
        let lineWithoutNumbering = trimmedLine.replacingOccurrences(
            of: "^\\d+\\)\\s*",
            with: "",
            options: .regularExpression
        )
        
        // Pattern to match time ranges - support both 12-hour and 24-hour formats
        let pattern = #"(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-?\s*(.+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: lineWithoutNumbering, range: NSRange(location: 0, length: lineWithoutNumbering.utf16.count)),
              let startTimeRange = Range(match.range(at: 1), in: lineWithoutNumbering),
              let endTimeRange = Range(match.range(at: 2), in: lineWithoutNumbering),
              let descriptionRange = Range(match.range(at: 3), in: lineWithoutNumbering) else {
            return nil
        }
        
        let startTimeStr = String(lineWithoutNumbering[startTimeRange])
        let endTimeStr = String(lineWithoutNumbering[endTimeRange])
        let rawDescription = String(lineWithoutNumbering[descriptionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip metrics suffix (e.g. " /3 ~8m") so task operations use the clean name
        let description: String
        var stripped = rawDescription.replacingOccurrences(of: " [✗]", with: "")
        if let range = stripped.range(of: DistractionTracker.metricsSuffixPattern, options: .regularExpression) {
            description = String(stripped[..<range.lowerBound])
        } else {
            description = stripped
        }

        // Parse times sequentially (respecting chronological order)
        guard let startMinutes = timeToMinutesSequential(startTimeStr, previousEndMinutes: previousEndMinutes),
              let rawEndMinutes = timeToMinutesSequential(endTimeStr, previousEndMinutes: startMinutes) else {
            return nil
        }

        // Midnight crossing: end time parsed to an earlier minute-value than start
        // (e.g. 11:40 PM = 1420 min, 12:00 AM = 0 min → add 1440 to end)
        let endMinutes = rawEndMinutes < startMinutes ? rawEndMinutes + 1440 : rawEndMinutes

        // Check if it's a fixed task (marked with **text**)
        let isFixed = description.contains("**")

        return TimeEntry(
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            description: description,
            isFixed: isFixed,
            originalLine: line
        )
    }
    
    private func parseTimeEntry(_ line: String) -> TimeEntry? {
        // Fallback to non-sequential parsing for backward compatibility
        return parseTimeEntrySequential(line, previousEndMinutes: nil)
    }
    
    private func timeToMinutesSequential(_ timeString: String, previousEndMinutes: Int?) -> Int? {
        let cleanTime = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it contains AM/PM
        let hasAMPM = cleanTime.lowercased().contains("am") || cleanTime.lowercased().contains("pm")
        let isPM = cleanTime.lowercased().contains("pm")
        
        // Extract just the time part (remove AM/PM)
        let timeOnly = cleanTime.replacingOccurrences(of: "\\s*[AaPp][Mm]", with: "", options: .regularExpression)
        
        let components = timeOnly.components(separatedBy: ":")
        guard components.count == 2,
              let hours = Int(components[0]),
              let mins = Int(components[1]) else {
            return nil
        }
        
        var finalHours = hours
        
        if hasAMPM {
            // Handle 12-hour format with explicit AM/PM
            if isPM && hours != 12 {
                finalHours = hours + 12  // Convert PM to 24-hour (except 12 PM)
            } else if !isPM && hours == 12 {
                finalHours = 0  // Convert 12 AM to 0 (midnight)
            }
        } else {
            // No AM/PM specified - use sequential logic
            
            if let prevEnd = previousEndMinutes {
                // We have a previous time to reference
                let prevEndHour = (prevEnd / 60) % 24
                
                // Calculate the raw minutes for this time
                let rawMinutes = hours * 60 + mins
                
                // Try different interpretations and pick the one that makes sense chronologically
                var candidates: [Int] = []
                
                // Option 1: Same period as previous (AM stays AM, PM stays PM)
                if hours == 12 {
                    // 12:XX could be noon (12 PM) or midnight (12 AM)
                    candidates.append(12 * 60 + mins)  // 12 PM (noon)
                    candidates.append(0 * 60 + mins)   // 12 AM (midnight)
                } else if hours < 12 {
                    // Could be AM or PM
                    candidates.append(hours * 60 + mins)        // AM interpretation
                    candidates.append((hours + 12) * 60 + mins) // PM interpretation
                } else {
                    // Already in 24-hour format (13-23)
                    candidates.append(rawMinutes)
                }
                
                // Pick the first candidate that's >= previous end time
                for candidate in candidates.sorted() {
                    if candidate >= prevEnd {
                        finalHours = candidate / 60
                        return candidate
                    }
                }
                
                // If no candidate works, the time might be on the next day
                // For now, pick the smallest candidate that makes sense
                if let bestCandidate = candidates.sorted().first(where: { $0 >= prevEnd }) {
                    return bestCandidate
                }
                
                // Last resort: assume PM if hour is small and previous was in PM
                if hours < 12 && prevEndHour >= 12 {
                    finalHours = hours + 12
                } else {
                    finalHours = hours
                }
            } else {
                // No previous time - use current time context
                let now = Date()
                let calendar = Calendar.current
                let currentHour = calendar.component(.hour, from: now)
                
                if hours == 12 {
                    // 12:XX - determine if noon or midnight based on current time
                    if currentHour >= 11 && currentHour <= 13 {
                        finalHours = 12  // Noon
                    } else if currentHour < 11 {
                        finalHours = 12  // Assume noon (upcoming)
                    } else {
                        finalHours = 0   // Midnight (next day)
                    }
                } else if hours < 12 {
                    // Could be AM or PM - use current time as hint
                    if currentHour >= 12 {
                        // Currently PM - assume PM for small hours
                        finalHours = hours + 12
                    } else {
                        // Currently AM - assume AM
                        finalHours = hours
                    }
                } else {
                    // Already 24-hour format
                    finalHours = hours
                }
            }
        }
        
        return finalHours * 60 + mins
    }
    
    private func timeToMinutesWithContext(_ timeString: String, endTimeStr: String? = nil, startTimeStr: String? = nil) -> Int? {
        let cleanTime = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it contains AM/PM
        let hasAMPM = cleanTime.lowercased().contains("am") || cleanTime.lowercased().contains("pm")
        let isPM = cleanTime.lowercased().contains("pm")
        
        // Extract just the time part (remove AM/PM)
        let timeOnly = cleanTime.replacingOccurrences(of: "\\s*[AaPp][Mm]", with: "", options: .regularExpression)
        
        let components = timeOnly.components(separatedBy: ":")
        guard components.count == 2,
              let hours = Int(components[0]),
              let mins = Int(components[1]) else {
            return nil
        }
        
        var finalHours = hours
        
        if hasAMPM {
            // Handle 12-hour format with explicit AM/PM
            if isPM && hours != 12 {
                finalHours = hours + 12  // Convert PM to 24-hour (except 12 PM)
            } else if !isPM && hours == 12 {
                finalHours = 0  // Convert 12 AM to 0 (midnight)
            }
        } else {
            // No AM/PM specified - use context to determine
            
            // Check if we're dealing with a time range that crosses noon
            var isNoonCrossing = false
            var isStartTime = false
            
            if let startTime = startTimeStr, let endTime = endTimeStr {
                let startComponents = startTime.replacingOccurrences(of: "\\s*[AaPp][Mm]", with: "", options: .regularExpression).components(separatedBy: ":")
                let endComponents = endTime.replacingOccurrences(of: "\\s*[AaPp][Mm]", with: "", options: .regularExpression).components(separatedBy: ":")
                
                if let startHour = Int(startComponents[0]), let endHour = Int(endComponents[0]) {
                    // Detect if this is a noon-crossing range (e.g., 11:XX - 12:XX)
                    isNoonCrossing = (startHour == 11 && endHour == 12)
                    isStartTime = (cleanTime == startTime.replacingOccurrences(of: "\\s*[AaPp][Mm]", with: "", options: .regularExpression))
                }
            }
            
            if isNoonCrossing {
                // Handle the noon crossing case: 11:XX - 12:XX
                if hours == 11 {
                    finalHours = 11 // 11:XX is 11 AM
                } else if hours == 12 {
                    finalHours = 12 // 12:XX is 12 PM (noon)
                } else {
                    // For other hours, use current time context
                    let now = Date()
                    let calendar = Calendar.current
                    let currentHour = calendar.component(.hour, from: now)
                    let isCurrentlyPM = currentHour >= 12
                    
                    if isCurrentlyPM && hours < 12 {
                        finalHours = hours + 12
                    } else if hours == 12 && !isCurrentlyPM {
                        finalHours = 0
                    }
                }
            } else {
                // Normal context-based interpretation
                let now = Date()
                let calendar = Calendar.current
                let currentHour = calendar.component(.hour, from: now)
                let isCurrentlyPM = currentHour >= 12
                
                if isCurrentlyPM {
                    if hours == 12 {
                        finalHours = 12 // 12 PM (noon)
                    } else if hours < 12 {
                        finalHours = hours + 12 // Convert to PM
                    }
                } else {
                    // Current time is AM
                    if hours == 12 {
                        finalHours = 0 // 12 AM (midnight)
                    } else {
                        finalHours = hours // Keep as AM
                    }
                }
            }
        }
        
        return finalHours * 60 + mins
    }
    
    private func minutesToTime(_ minutes: Int) -> String {
        // Use the safe version to prevent crashes
        return safeMinutesToTime(minutes)
    }
    
    private func safeMinutesToTime(_ minutes: Int) -> String {
        // Add bounds checking to prevent crashes
        guard minutes >= -1440 && minutes <= 2880 else {
            print("⚠️ Minutes out of bounds: \(minutes)")
            return "Invalid Time"
        }
        
        // Ensure we have valid values before any calculations
        let adjustedMinutes = minutes >= 0 ? minutes : (minutes % (24 * 60) + 24 * 60)
        
        // Additional safety check after adjustment
        guard adjustedMinutes >= 0 && adjustedMinutes < (48 * 60) else {
            print("⚠️ Adjusted minutes out of bounds: \(adjustedMinutes)")
            return "Invalid Time"
        }
        
        let hours = (adjustedMinutes / 60) % 24
        let mins = adjustedMinutes % 60
        
        // Validate calculated values
        guard hours >= 0 && hours <= 23 && mins >= 0 && mins <= 59 else {
            print("⚠️ Invalid hours/mins: hours=\(hours), mins=\(mins)")
            return "Invalid Time"
        }
        
        // Convert to 12-hour format with AM/PM for display
        let displayHour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
        let ampm = hours < 12 ? "AM" : "PM"
        
        // Validate display hour
        guard displayHour >= 1 && displayHour <= 12 else {
            print("⚠️ Invalid display hour: \(displayHour)")
            return "Invalid Time"
        }
        
        // Use completely safe string construction
        do {
            let minuteStr = mins < 10 ? "0\(mins)" : "\(mins)"
            let result = "\(displayHour):\(minuteStr) \(ampm)"
            return result
        } catch {
            print("⚠️ String construction failed: \(error)")
            return "Invalid Time"
        }
    }
    
    private func adjustTime(_ timeString: String, byMinutes minutes: Int) -> String? {
        guard let timeMinutes = timeToMinutesWithContext(timeString) else {
            return nil
        }
        
        let adjustedMinutes = timeMinutes + minutes
        return safeMinutesToTime(adjustedMinutes)
    }
    
    // MARK: - Countdown Timer Methods
    
    private func startCountdownTimer() {
        stopCountdownTimer()
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateTimeRemaining()
        }
    }
    
    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    private func updateTimeRemaining() {
        // Update current time to force UI refresh
        currentTime = Date()

        if settings.isPlaying && !settings.isPaused {
            let remaining = settings.nextAlertDate.timeIntervalSinceNow
            previousTimeRemaining = timeRemaining
            timeRemaining = max(0, remaining)
            // Timer expired while app was backgrounded (isPlaying stayed true, Timer never fired).
            // Trigger completion now so manual-mode waiting state is entered correctly.
            if remaining < -1.0 && useCycles && currentCycleDuration > 0 && !isTransitioning && pausedAt == nil && !isWaitingForManualStart {
                handleCycleCompletion()
            }
        } else if settings.isPlaying && settings.isPaused {
            // When paused, keep the timeRemaining value frozen
            previousTimeRemaining = timeRemaining
        } else {
            // isPlaying and isPaused are both false.
            // If useCycles is on and a cycle was active, AlertSettings dropped isPlaying
            // (line 194 or line 334 in AlertSettings_OrderFixed.swift).
            if useCycles && currentCycleDuration > 0 && !isTransitioning && pausedAt == nil && !isWaitingForManualStart {
                let remaining = settings.nextAlertDate.timeIntervalSinceNow
                if remaining > 2.0 {
                    // Significant time left — AlertSettings dropped isPlaying prematurely
                    // (e.g. zero-duration guard). Re-arm the timer without restarting the cycle.
                    settings.isPlaying = true
                    settings.scheduleIntervalTimer()
                } else if remaining <= 1.0 {
                    // Timer has actually expired — advance to the next cycle.
                    handleCycleCompletion()
                }
                // 1.0–2.0 s window: let the 0.5 s observer handle it cleanly.
            }
            previousTimeRemaining = timeRemaining
            timeRemaining = 0
        }
    }
    
    private func formatTimeRemaining(_ timeInterval: TimeInterval) -> String {
        if timeInterval <= 0 {
            return "00:00"
        }
        
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Automatic Cycle Transition
    
    private func generateSchedule() {
        print("🔧 Generate button clicked")
        print("   From: \(scheduleFrom), To: \(scheduleTo)")
        print("   Interval: \(scheduleInterval), Gap: \(scheduleGap)")
        print("   Task: \(scheduleTaskName)")

        // Parse comma-separated lists
        let intervals: [Int] = scheduleInterval.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let gaps: [Int] = scheduleGap.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let tasks: [String] = scheduleTaskName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard !intervals.isEmpty, !gaps.isEmpty, !tasks.isEmpty,
              let fromMinutes = parseTimeToMinutes(scheduleFrom) else {
            print("❌ Invalid input values")
            return
        }

        var scheduleLines: [String] = []
        var currentStart = fromMinutes
        var taskNumber = Int(scheduleStartNum.trimmingCharacters(in: .whitespaces)) ?? 1

        if scheduleNoRepeat {
            // Single pass: generate each task exactly once in order
            for i in 0..<tasks.count {
                let intervalMinutes = i < intervals.count ? intervals[i] : intervals.last!
                let gapMinutes = i < gaps.count ? gaps[i] : gaps.last!
                let taskName = tasks[i]

                let currentEnd = currentStart + intervalMinutes
                let line = "\(taskNumber)) \(formatMinutesToTime(currentStart)) - \(formatMinutesToTime(currentEnd)) - \(taskName)"
                scheduleLines.append(line)
                print("   Generated: \(line)")

                currentStart = currentEnd + gapMinutes
                taskNumber += 1
            }
        } else {
            guard let scheduledTo = parseTimeToMinutes(scheduleTo) else {
                print("❌ Invalid end time")
                return
            }
            var toMinutes = adjustEndTimeIfNeeded(startMinutes: fromMinutes, endMinutes: scheduledTo)
            print("✅ Inputs parsed — From: \(fromMinutes), To: \(toMinutes)")
            var cycleIndex = 0
            while currentStart < toMinutes {
                let intervalMinutes = intervals[cycleIndex % intervals.count]
                let gapMinutes = gaps[cycleIndex % gaps.count]
                let taskName = tasks[cycleIndex % tasks.count]
                let currentEnd = min(currentStart + intervalMinutes, toMinutes)
                let line = "\(taskNumber)) \(formatMinutesToTime(currentStart)) - \(formatMinutesToTime(currentEnd)) - \(taskName)"
                scheduleLines.append(line)
                print("   Generated: \(line)")
                currentStart = currentEnd + gapMinutes
                taskNumber += 1
                cycleIndex += 1
            }
        }
        
        print("📝 Generated \(scheduleLines.count) schedule blocks")

        let generatedSchedule = scheduleLines.joined(separator: "\n")
        print("📋 Current notes length: \(notesText.count)")

        // Insert inside the START/END block if it exists; otherwise create one
        let allLines = notesText.components(separatedBy: .newlines)
        var startLineIndex: Int?
        var endLineIndex: Int?

        for (index, line) in allLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "START" && startLineIndex == nil {
                startLineIndex = index
            } else if trimmed == "END" && startLineIndex != nil && endLineIndex == nil {
                endLineIndex = index
                break
            }
        }

        // shiftMinutes = total span of generated blocks (currentStart has advanced past the last block)
        let shiftMinutes = currentStart - fromMinutes

        let insertAfterTrimmed = scheduleInsertAfter.trimmingCharacters(in: .whitespaces)
        if let insertNum = Int(insertAfterTrimmed), !insertAfterTrimmed.isEmpty {
            // Insert after task #insertNum and shift subsequent tasks
            insertGeneratedTasksAfter(taskNum: insertNum, scheduleLines: scheduleLines, shiftMinutes: shiftMinutes)
        } else if let sIdx = startLineIndex, let endIdx = endLineIndex {
            // No explicit insert-after: find nearest interval and insert there
            let nearestNum = nearestTaskNum(in: allLines, startIdx: sIdx, endIdx: endIdx)
            if nearestNum > 0 {
                insertGeneratedTasksAfter(taskNum: nearestNum, scheduleLines: scheduleLines, shiftMinutes: shiftMinutes)
            } else {
                var newLines = allLines
                newLines.insert(contentsOf: scheduleLines, at: endIdx)
                notesText = newLines.joined(separator: "\n")
            }
        } else if let endIdx = endLineIndex {
            // No numbered tasks found — append before END
            var newLines = allLines
            newLines.insert(contentsOf: scheduleLines, at: endIdx)
            notesText = newLines.joined(separator: "\n")
        } else {
            // No START/END block found — wrap the generated schedule in one and append
            let block = "\nSTART\n\(generatedSchedule)\nEND"
            if notesText.isEmpty {
                notesText = "START\n\(generatedSchedule)\nEND"
            } else {
                notesText += block
            }
        }

        print("📋 New notes length: \(notesText.count)")
        print("📋 First 100 chars: \(String(notesText.prefix(100)))")

        // Force refresh editor
        DispatchQueue.main.async {
            self.editorKey = UUID()
        }
    }
    
    private func parseTimeToMinutes(_ timeString: String) -> Int? {
        let cleanTime = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it contains AM/PM
        let hasAMPM = cleanTime.lowercased().contains("am") || cleanTime.lowercased().contains("pm")
        let isPM = cleanTime.lowercased().contains("pm")
        
        // Extract just the time part (remove AM/PM)
        let timeOnly = cleanTime.replacingOccurrences(of: "\\s*[AaPp][Mm]", with: "", options: .regularExpression)
        
        let components = timeOnly.components(separatedBy: ":")
        guard components.count == 2,
              let hours = Int(components[0]),
              let mins = Int(components[1]) else {
            return nil
        }
        
        var finalHours = hours
        
        if hasAMPM {
            // Handle 12-hour format with explicit AM/PM
            if isPM && hours != 12 {
                finalHours = hours + 12  // Convert PM to 24-hour (except 12 PM)
            } else if !isPM && hours == 12 {
                finalHours = 0  // Convert 12 AM to 0 (midnight)
            }
        } else {
            // No AM/PM typed — treat as 24-hour (use explicit AM/PM for ambiguous times)
            finalHours = hours
        }

        return finalHours * 60 + mins
    }
    
    private func adjustEndTimeIfNeeded(startMinutes: Int, endMinutes: Int) -> Int {
        // Handle noon crossing: if start is 11:XX and end is 12:XX, treat 12:XX as PM (noon)
        let startHour = startMinutes / 60
        let endHour = endMinutes / 60
        
        if startHour == 11 && endHour == 12 {
            // This is a noon crossing (11:XX AM - 12:XX PM)
            // 12:XX should be treated as 12 PM (noon), which is already correct
            return endMinutes
        }
        
        // If end time is before start time, assume it's meant to be PM (add 12 hours)
        if endMinutes < startMinutes && endMinutes < 720 { // 720 = 12:00
            return endMinutes + (12 * 60)
        }
        return endMinutes
    }
    
    private func formatMinutesToTime(_ minutes: Int) -> String {
        let h = (minutes / 60) % 24
        let m = minutes % 60
        let suffix = h >= 12 ? "PM" : "AM"
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", displayH, m, suffix)
    }
    
    private func startNextCycle() {
        print("🔄 Starting next cycle...")
        
        // Show transitioning state
        isTransitioning = true
        
        // Stop the timer to ensure clean transition
        settings.stopTimer()
        
        // Stop reminder timer during transition
        stopReminderTimer()
        
        // Re-evaluate what should be happening now
        let timeEntries = extractTimeEntriesFromNotes()
        guard !timeEntries.isEmpty else {
            print("❌ No schedule found for next cycle")
            currentTaskName = "No schedule found"
            isTransitioning = false
            return
        }
        
        let now = Date()
        let calendar = Calendar.current
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let currentTimeStr = safeMinutesToTime(currentMinutes)
        
        print("⏰ Current time: \(currentTimeStr) (\(currentMinutes) minutes)")
        print("📋 Evaluating \(timeEntries.count) schedule entries")
        
        // Find what should be happening now
        if let currentEntry = findBestCurrentTask(at: currentMinutes, in: timeEntries) {
            // Currently in a scheduled task
            currentTaskName = currentEntry.description
            // For midnight-crossing tasks, currentMinutes may be small (e.g. 10 for 12:10 AM)
            // while endMinutes is >1440. Normalise so subtraction gives the real remaining time.
            let adjustedCurrent = (currentEntry.endMinutes >= 1440 && currentMinutes < (currentEntry.endMinutes - 1440))
                ? currentMinutes + 1440
                : currentMinutes
            let remainingMinutes = currentEntry.endMinutes - adjustedCurrent
            // Store the ORIGINAL duration, not remaining time
            let originalDuration = currentEntry.endMinutes - currentEntry.startMinutes
            currentCycleDuration = originalDuration
            
            if remainingMinutes > 0 {
                print("🎯 Starting task cycle: \(currentEntry.description) for \(remainingMinutes) minutes (original: \(originalDuration) min)")
                print("   Task window: \(safeMinutesToTime(currentEntry.startMinutes)) - \(safeMinutesToTime(currentEntry.endMinutes))")
                // Small delay to ensure clean state transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startCycleWithDuration(remainingMinutes, taskName: currentEntry.description)
                    self.isTransitioning = false
                }
            } else {
                // Task just ended, look for next task
                print("⚠️ Current task has 0 remaining minutes, looking for next task")
                if let nextEntry = findNextTask(after: currentMinutes, in: timeEntries) {
                    let gapMinutes = nextEntry.startMinutes - currentMinutes
                    print("📍 Found next task: \(nextEntry.description) starting at \(safeMinutesToTime(nextEntry.startMinutes))")
                    print("   Gap duration: \(gapMinutes) minutes")
                    
                    currentTaskName = "Rest up"
                    currentCycleDuration = gapMinutes
                    
                    if gapMinutes > 0 {
                        print("🎯 Starting preparation cycle for \(gapMinutes) minutes")
                        // Small delay to ensure clean state transition
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.startCycleWithDuration(gapMinutes, taskName: "Rest up")
                            self.isTransitioning = false
                        }
                    } else {
                        // Next task starts immediately
                        print("⚡ Next task starts immediately, recursing...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.startNextCycle()
                        }
                    }
                } else {
                    // No more tasks today
                    print("✅ No more tasks scheduled for today")
                    currentTaskName = "Free time"
                    currentCycleDuration = 0
                    isTransitioning = false
                    stopCycles()
                }
            }
            
        } else if let nextEntry = findNextTask(after: currentMinutes, in: timeEntries) {
            // In a gap before next task - start preparation/rest/Drink Water cycle
            let gapMinutes = nextEntry.startMinutes - currentMinutes
            print("📍 Currently in gap. Next task: \(nextEntry.description) at \(safeMinutesToTime(nextEntry.startMinutes))")
            print("   Gap duration: \(gapMinutes) minutes")
            
            currentTaskName = "Rest up"
            currentCycleDuration = gapMinutes
            
            if gapMinutes > 0 {
                print("🎯 Starting preparation cycle for \(gapMinutes) minutes")
                // Small delay to ensure clean state transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startCycleWithDuration(gapMinutes, taskName: "Rest up")
                    self.isTransitioning = false
                }
            } else {
                // Next task starts immediately
                print("⚡ Next task starts immediately (gap = 0), recursing...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startNextCycle()
                }
            }
            
        } else {
            // No more tasks today
            print("✅ No more tasks scheduled for today")
            currentTaskName = "Free time"
            currentCycleDuration = 0
            isTransitioning = false
            stopCycles()
        }
    }
    
    // MARK: - Reminder Timer Functions
    
    private func startReminderTimer() {
        // Stop any existing reminder timer
        stopReminderTimer()
        
        // Check if reminder interval is set and valid
        guard let intervalMinutes = Int(reminderInterval), intervalMinutes > 0 else {
            return
        }
        
        // Track the last minute we gave a reminder for (to avoid duplicates)
        var lastReminderMinute: Int? = nil
        
        // Create a timer that checks every second
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            
            // Only remind if playing and not paused
            guard self.settings.isPlaying && !self.settings.isPaused else {
                return
            }
            
            // Calculate remaining time
            let remaining = self.settings.nextAlertDate.timeIntervalSinceNow
            guard remaining > 0 else {
                return
            }
            
            let remainingMinutes = Int(ceil(remaining / 60.0))
            
            // Check if this is an aligned reminder time (multiple of interval)
            let isAlignedReminder = remainingMinutes % intervalMinutes == 0
            
            // Only give reminder if:
            // 1. It's an aligned time (e.g., 25, 20, 15, 10, 5 for 5-min interval)
            // 2. We haven't already given a reminder for this minute
            if isAlignedReminder && lastReminderMinute != remainingMinutes {
                self.giveTimeReminder()
                lastReminderMinute = remainingMinutes
            }
        }
        
        print("⏰ Reminder timer started with \(intervalMinutes) minute interval")
    }
    
    private func stopReminderTimer() {
        reminderTimer?.invalidate()
        reminderTimer = nil
    }
    
    private func giveTimeReminder() {
        // Calculate time remaining
        let remaining = settings.nextAlertDate.timeIntervalSinceNow
        
        guard remaining > 0 else {
            return
        }
        
        let remainingMinutes = Int(ceil(remaining / 60.0))
        
        // Check if reminder interval is set
        guard let intervalMinutes = Int(reminderInterval), intervalMinutes > 0 else {
            return
        }
        
        // Only give reminder if remaining time is a multiple of the interval
        // This ensures reminders happen at 25, 20, 15, 10, 5, 0 for a 5-minute interval
        let isAlignedReminder = remainingMinutes % intervalMinutes == 0
        
        guard isAlignedReminder else {
            // Not an aligned reminder time, skip
            return
        }
        
        // Create reminder message
        let message: String
        if remainingMinutes == 1 {
            message = "1 minute left"
        } else {
            message = "\(remainingMinutes) minutes left"
        }
        
        // Speak the reminder
        speechManager.speak(message)
        
        print("🔔 Reminder: \(message) for task: \(currentTaskName)")
    }
    
    // MARK: - Edit Task in Schedule

    struct EditTaskItem: Identifiable {
        let id = UUID()
        let num: Int?
        let originalStart: Int
        let originalEnd: Int
        let originalDesc: String
        let struck: Bool
        let fixed: Bool
    }

    /// Updates a task and shifts all downstream non-fixed tasks by the change in end time.
    private func updateTaskAndShiftInNotes(item: EditTaskItem, newDesc: String, newStart: Int, newEnd: Int) {
        let delta = newEnd - item.originalEnd   // +ve = extended, -ve = shortened
        let allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil
        var eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return }

        var newLines = allLines
        var prevEnd: Int? = nil
        var foundTarget = false

        for i in (s + 1)..<e {
            let line = allLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed

            guard let entry = parseTimeEntrySequential(parseLine, previousEndMinutes: prevEnd) else { continue }

            if !foundTarget {
                // Match by num + start + end + desc
                let numMatch = item.num.map { n -> Bool in
                    if let pIdx = parseLine.firstIndex(of: ")"),
                       let lineNum = Int(String(parseLine[parseLine.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)) {
                        return lineNum == n
                    }
                    return false
                } ?? true

                if numMatch && entry.startMinutes == item.originalStart &&
                   entry.endMinutes == item.originalEnd && entry.description == item.originalDesc {
                    foundTarget = true
                    let numStr = item.num.map { "\($0)) " } ?? ""
                    let fixedMark = item.fixed ? "**" : ""
                    let updated = "\(numStr)\(safeMinutesToTime(newStart)) - \(safeMinutesToTime(newEnd)) - \(fixedMark)\(newDesc)\(fixedMark)"
                    newLines[i] = isStruck ? "~~\(updated)~~" : updated
                    prevEnd = newEnd
                    continue
                }
            } else if delta != 0 && !entry.isFixed && entry.startMinutes >= item.originalEnd {
                // Shift downstream non-fixed tasks
                let numStr: String
                if let pIdx = parseLine.firstIndex(of: ")"),
                   let n = Int(String(parseLine[parseLine.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)) {
                    numStr = "\(n)) "
                } else { numStr = "" }
                let shiftedStart = max(0, entry.startMinutes + delta)
                let shiftedEnd   = max(shiftedStart + 1, entry.endMinutes + delta)
                let fixedMark = entry.isFixed ? "**" : ""
                let shifted = "\(numStr)\(safeMinutesToTime(shiftedStart)) - \(safeMinutesToTime(shiftedEnd)) - \(fixedMark)\(entry.description)\(fixedMark)"
                newLines[i] = isStruck ? "~~\(shifted)~~" : shifted
                prevEnd = shiftedEnd
                continue
            }
            prevEnd = entry.endMinutes
        }

        notesText = newLines.joined(separator: "\n")
        editorKey = UUID()
        saveNotes()
    }

    /// Inserts `lines` after task number `afterNum`, shifts subsequent tasks' times forward
    /// so they start after the intercept block ends, then renumbers everything sequentially.
    /// UI entry point: resolves afterNum == 0 to the nearest time interval, then delegates.
    private func applyIntercept(lines: [String], afterNum: Int) {
        guard !lines.isEmpty else { return }
        let resolved: Int
        if afterNum == 0 {
            let allLines = notesText.components(separatedBy: .newlines)
            var s: Int? = nil, e: Int? = nil
            for (i, line) in allLines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t == "START" && s == nil { s = i }
                else if t == "END" && s != nil && e == nil { e = i; break }
            }
            resolved = (s != nil && e != nil) ? nearestTaskNum(in: allLines, startIdx: s!, endIdx: e!) : 0
        } else {
            resolved = afterNum
        }
        processGroupedIntercept(lines: lines, firstGroupAfterNum: resolved)
    }

    /// Splits `lines` into contiguous time-groups and processes each independently via
    /// `coreIntercept`, so non-adjacent tasks only shift the entries they actually overlap.
    /// The first group is inserted after `firstGroupAfterNum`; subsequent groups find their
    /// own position via `taskNumBefore` on the freshly-updated schedule.
    private func processGroupedIntercept(lines: [String], firstGroupAfterNum: Int) {
        guard !lines.isEmpty else { return }
        let timePattern = #"(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)"#
        guard let timeRegex = try? NSRegularExpression(pattern: timePattern) else { return }

        // Build contiguous groups: a new group begins whenever there is a time gap.
        var groups: [[String]] = []
        var currentGroup: [String] = []
        var prevEnd: Int? = nil
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            var lineStart: Int? = nil, lineEnd: Int? = nil
            if let m = timeRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
               let sr = Range(m.range(at: 1), in: t),
               let er = Range(m.range(at: 2), in: t) {
                lineStart = interceptParseMinutes(String(t[sr]))
                lineEnd   = interceptParseMinutes(String(t[er]))
            }
            if let start = lineStart, let prev = prevEnd, start > prev {
                if !currentGroup.isEmpty { groups.append(currentGroup) }
                currentGroup = [line]
            } else {
                currentGroup.append(line)
            }
            prevEnd = lineEnd ?? prevEnd
        }
        if !currentGroup.isEmpty { groups.append(currentGroup) }

        coreIntercept(lines: groups[0], resolvedAfterNum: firstGroupAfterNum)

        for group in groups.dropFirst() {
            var firstStartMin: Int? = nil
            for line in group {
                let t = line.trimmingCharacters(in: .whitespaces)
                if let m = timeRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                   let sr = Range(m.range(at: 1), in: t),
                   let startMin = interceptParseMinutes(String(t[sr])) {
                    firstStartMin = startMin; break
                }
            }
            let allLines = notesText.components(separatedBy: .newlines)
            var s2: Int? = nil, e2: Int? = nil
            for (i, line) in allLines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t == "START" && s2 == nil { s2 = i }
                else if t == "END" && s2 != nil && e2 == nil { e2 = i; break }
            }
            let groupAfterNum: Int
            if let s = s2, let e = e2, let targetMin = firstStartMin {
                groupAfterNum = taskNumBefore(minutes: targetMin, in: allLines, startIdx: s, endIdx: e)
            } else {
                groupAfterNum = 0
            }
            coreIntercept(lines: group, resolvedAfterNum: groupAfterNum)
        }
    }

    /// Inserts `lines` after task `resolvedAfterNum`, shifting subsequent tasks forward.
    /// resolvedAfterNum == 0 inserts at the very start of the block (after START tag).
    private func coreIntercept(lines: [String], resolvedAfterNum: Int) {
        guard !lines.isEmpty else { return }

        let timePattern = #"(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)"#
        guard let timeRegex = try? NSRegularExpression(pattern: timePattern) else { return }

        // Strip any leading "N)" numbering from the intercept lines
        let strippedLines = lines.map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            if let pIdx = t.firstIndex(of: ")"),
               let _ = Int(String(t[t.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)),
               !t[t.startIndex..<pIdx].contains(" ") {
                return String(t[t.index(after: pIdx)...]).trimmingCharacters(in: .whitespaces)
            }
            return t
        }

        // Parse end time of last intercept task (to know how far to shift subsequent tasks)
        var interceptEndMin: Int? = nil
        for line in strippedLines.reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let m = timeRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
               let er = Range(m.range(at: 2), in: t),
               let end = interceptParseMinutes(String(t[er])) {
                interceptEndMin = end
                break
            }
        }

        var allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil, eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }

        if let s = sIdx, let e = eIdx {
            // Find line index for the target task number
            var insertAfterLineIdx: Int? = nil
            if resolvedAfterNum > 0 {
                for i in (s + 1)..<e {
                    let t = allLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.isEmpty { continue }
                    if let pIdx = t.firstIndex(of: ")"),
                       let n = Int(String(t[t.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)),
                       !t[t.startIndex..<pIdx].contains(" "), n > 0, n < 1000,
                       n == resolvedAfterNum {
                        insertAfterLineIdx = i
                        break
                    }
                }
            }
            // 0 → insert at start of block (right after START); >0 → after that task line
            let insertAt: Int = resolvedAfterNum == 0 ? (s + 1) : ((insertAfterLineIdx ?? (e - 1)) + 1)

            // If the intercept's start time falls inside the "after" task, push it forward
            // so it starts exactly when that task ends — no truncation, no overlap.
            var adjustedLines = strippedLines
            if let afterIdx = insertAfterLineIdx {
                let afterRaw = allLines[afterIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                let afterInner = (afterRaw.hasPrefix("~~") && afterRaw.hasSuffix("~~"))
                    ? String(afterRaw.dropFirst(2).dropLast(2)) : afterRaw
                if let am = timeRegex.firstMatch(in: afterInner, range: NSRange(afterInner.startIndex..., in: afterInner)),
                   let er = Range(am.range(at: 2), in: afterInner),
                   let afterEnd = interceptParseMinutes(String(afterInner[er])) {
                    // Find first start time in the intercept lines
                    var firstInterceptStart: Int? = nil
                    for line in adjustedLines {
                        let t = line.trimmingCharacters(in: .whitespaces)
                        if let im = timeRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                           let sr = Range(im.range(at: 1), in: t),
                           let start = interceptParseMinutes(String(t[sr])) {
                            firstInterceptStart = start; break
                        }
                    }
                    if let firstStart = firstInterceptStart, firstStart < afterEnd {
                        let delta = afterEnd - firstStart
                        adjustedLines = adjustedLines.map { interceptShiftTimeLine($0, by: delta, regex: timeRegex) }
                        interceptEndMin = interceptEndMin.map { $0 + delta }
                    }
                }
            }

            // Calculate how much to shift tasks that follow the intercept.
            // Scan forward from insertAt to find the first non-empty line with a parseable time.
            var shiftAmount = 0
            if let interceptEnd = interceptEndMin {
                var idx = insertAt
                while idx < e {
                    let cl = allLines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cl.isEmpty {
                        let isStruck = cl.hasPrefix("~~") && cl.hasSuffix("~~")
                        let inner = isStruck ? String(cl.dropFirst(2).dropLast(2)) : cl
                        if let m = timeRegex.firstMatch(in: inner, range: NSRange(inner.startIndex..., in: inner)),
                           let sr = Range(m.range(at: 1), in: inner),
                           let firstStart = interceptParseMinutes(String(inner[sr])) {
                            shiftAmount = max(0, interceptEnd - firstStart)
                        }
                        break
                    }
                    idx += 1
                }
            }

            // Insert intercept lines
            allLines.insert(contentsOf: adjustedLines, at: insertAt)

            // Shift downstream tasks that are contiguous with the intercept block.
            // Stop as soon as a task's original start time is beyond the current wave end —
            // that gap means the intercept does not displace it.
            if shiftAmount > 0, let waveStart = interceptEndMin {
                let newE = e + adjustedLines.count
                let shiftFrom = insertAt + adjustedLines.count
                var waveEnd = waveStart
                for i in shiftFrom..<newE {
                    let raw = allLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if raw.isEmpty { continue }
                    let isStruck = raw.hasPrefix("~~") && raw.hasSuffix("~~")
                    let inner = isStruck ? String(raw.dropFirst(2).dropLast(2)) : raw
                    if let m = timeRegex.firstMatch(in: inner, range: NSRange(inner.startIndex..., in: inner)),
                       let sr = Range(m.range(at: 1), in: inner),
                       let er = Range(m.range(at: 2), in: inner),
                       let taskStart = interceptParseMinutes(String(inner[sr])),
                       let taskEnd   = interceptParseMinutes(String(inner[er])) {
                        if taskStart > waveEnd { break }
                        waveEnd = max(waveEnd, taskEnd)
                    }
                    let shifted = interceptShiftTimeLine(inner, by: shiftAmount, regex: timeRegex)
                    allLines[i] = isStruck ? "~~\(shifted)~~" : shifted
                }
            }
        } else {
            // No block yet — create one
            if allLines.last?.isEmpty == false { allLines.append("") }
            allLines.append("START")
            allLines.append(contentsOf: strippedLines)
            allLines.append("END")
        }

        // Renumber all task lines inside START...END sequentially
        var sIdx2: Int? = nil, eIdx2: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx2 == nil { sIdx2 = i }
            else if t == "END" && sIdx2 != nil && eIdx2 == nil { eIdx2 = i; break }
        }
        if let s = sIdx2, let e = eIdx2 {
            var counter = 1
            for i in (s + 1)..<e {
                let t = allLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                let isStruck = t.hasPrefix("~~") && t.hasSuffix("~~")
                let inner = isStruck ? String(t.dropFirst(2).dropLast(2)) : t
                let body: String
                if let pIdx = inner.firstIndex(of: ")"),
                   let _ = Int(String(inner[inner.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)),
                   !inner[inner.startIndex..<pIdx].contains(" ") {
                    body = String(inner[inner.index(after: pIdx)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    body = inner
                }
                let rebuilt = "\(counter)) \(body)"
                allLines[i] = isStruck ? "~~\(rebuilt)~~" : rebuilt
                counter += 1
            }
        }

        notesText = allLines.joined(separator: "\n")
        editorKey = UUID()
        saveNotes()
    }

    /// Returns the task number of the scheduled task nearest to the current time.
    /// Prefers the currently-active task; falls back to the last task whose start has passed;
    /// falls back to the first numbered task in the block.  Returns 0 if no numbered tasks exist.
    private func nearestTaskNum(in allLines: [String], startIdx: Int, endIdx: Int) -> Int {
        let timePattern = #"(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)"#
        guard let timeRegex = try? NSRegularExpression(pattern: timePattern) else { return 0 }

        let calendar = Calendar.current
        let now = calendar.dateComponents([.hour, .minute], from: Date())
        let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)

        struct Slot { let num: Int; let start: Int; let end: Int }
        var slots: [Slot] = []
        for i in (startIdx + 1)..<endIdx {
            let t = allLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            guard let pIdx = t.firstIndex(of: ")"),
                  let num = Int(String(t[t.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)),
                  !t[t.startIndex..<pIdx].contains(" "), num > 0, num < 1000 else { continue }
            guard let m = timeRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let sr = Range(m.range(at: 1), in: t),
                  let er = Range(m.range(at: 2), in: t),
                  let startMin = interceptParseMinutes(String(t[sr])),
                  let endMin   = interceptParseMinutes(String(t[er])) else { continue }
            slots.append(Slot(num: num, start: startMin, end: endMin))
        }
        guard !slots.isEmpty else { return 0 }

        // Active task: currentMinutes falls within [start, end)
        if let active = slots.last(where: { currentMinutes >= $0.start && currentMinutes < $0.end }) {
            return active.num
        }
        // Last past task: latest start that has already passed
        if let past = slots.last(where: { $0.start <= currentMinutes }) {
            return past.num
        }
        // All tasks are in the future — insert before the first one (i.e. after task 0 means before END,
        // but here we return the first task so new tasks land right before it; use task before first)
        return slots[0].num > 1 ? slots[0].num - 1 : 0
    }

    /// Parses a time string like "1:30 PM" or "13:30" into minutes since midnight.
    private func interceptParseMinutes(_ s: String) -> Int? {
        let clean = s.trimmingCharacters(in: .whitespaces).lowercased()
        let isPM = clean.contains("pm")
        let isAM = clean.contains("am")
        let digits = clean
            .replacingOccurrences(of: "pm", with: "")
            .replacingOccurrences(of: "am", with: "")
            .trimmingCharacters(in: .whitespaces)
        let parts = digits.components(separatedBy: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 2 else { return nil }
        var h = parts[0], m = parts[1]
        if isPM && h != 12 { h += 12 }
        if isAM && h == 12 { h = 0 }
        guard h >= 0 && h < 48 && m >= 0 && m < 60 else { return nil }
        return h * 60 + m
    }

    /// Shifts the start and end times in a task line by `minutes`, preserving everything else.
    private func interceptShiftTimeLine(_ line: String, by minutes: Int, regex: NSRegularExpression) -> String {
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let sr = Range(match.range(at: 1), in: line),
              let er = Range(match.range(at: 2), in: line),
              let startMin = interceptParseMinutes(String(line[sr])),
              let endMin   = interceptParseMinutes(String(line[er])) else {
            return line
        }
        let before = String(line[line.startIndex..<sr.lowerBound])
        let after  = String(line[er.upperBound...])
        return "\(before)\(safeMinutesToTime(startMin + minutes)) - \(safeMinutesToTime(endMin + minutes))\(after)"
    }

    /// Returns true if both tasks were found and swapped, false otherwise.
    @discardableResult
    private func swapScheduleTasks(numA: Int, numB: Int) -> Bool {
        let allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil, eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return false }

        struct ParsedTask {
            let lineIndex: Int
            let num: Int?
            let startMinutes: Int
            let endMinutes: Int
            let description: String
            let isFixed: Bool
            let isStruck: Bool
        }

        var parsedTasks: [ParsedTask] = []
        var prevEnd: Int? = nil

        for i in (s + 1)..<e {
            let line = allLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            guard let entry = parseTimeEntrySequential(parseLine, previousEndMinutes: prevEnd) else { continue }

            var num: Int? = nil
            if let pIdx = parseLine.firstIndex(of: ")"),
               let n = Int(String(parseLine[parseLine.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)),
               n > 0 && n < 1000 {
                num = n
            }

            parsedTasks.append(ParsedTask(
                lineIndex: i,
                num: num,
                startMinutes: entry.startMinutes,
                endMinutes: entry.endMinutes,
                description: entry.description,
                isFixed: entry.isFixed,
                isStruck: isStruck
            ))
            prevEnd = entry.endMinutes
        }

        guard let idxA = parsedTasks.firstIndex(where: { $0.num == numA }),
              let idxB = parsedTasks.firstIndex(where: { $0.num == numB }) else { return false }

        let firstIdx = min(idxA, idxB)
        let lastIdx  = max(idxA, idxB)
        guard firstIdx != lastIdx else { return false }

        let firstTask = parsedTasks[firstIdx]
        let lastTask  = parsedTasks[lastIdx]

        var newLines = allLines
        var currentStart = firstTask.startMinutes

        for offset in 0...(lastIdx - firstIdx) {
            let taskIdx = firstIdx + offset
            let task = parsedTasks[taskIdx]

            let desc: String
            let isFixed: Bool
            let isStruck: Bool
            let num: Int?
            let dur: Int

            if taskIdx == firstIdx {
                desc    = lastTask.description
                isFixed = lastTask.isFixed
                isStruck = lastTask.isStruck
                num     = firstTask.num
                dur     = lastTask.endMinutes - lastTask.startMinutes
            } else if taskIdx == lastIdx {
                desc    = firstTask.description
                isFixed = firstTask.isFixed
                isStruck = firstTask.isStruck
                num     = lastTask.num
                dur     = firstTask.endMinutes - firstTask.startMinutes
            } else {
                desc    = task.description
                isFixed = task.isFixed
                isStruck = task.isStruck
                num     = task.num
                dur     = task.endMinutes - task.startMinutes
            }

            let newStart = currentStart
            let newEnd   = newStart + max(1, dur)
            currentStart = newEnd

            let numStr    = num.map { "\($0)) " } ?? ""
            let fixedMark = isFixed ? "**" : ""
            let rebuilt   = "\(numStr)\(safeMinutesToTime(newStart)) - \(safeMinutesToTime(newEnd)) - \(fixedMark)\(desc)\(fixedMark)"
            newLines[task.lineIndex] = isStruck ? "~~\(rebuilt)~~" : rebuilt
        }

        notesText = newLines.joined(separator: "\n")
        editorKey = UUID()
        saveNotes()
        return true
    }

    private func updateTaskInNotes(item: EditTaskItem, newDesc: String, newStart: Int, newEnd: Int) {
        let allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil
        var eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return }

        var newLines = allLines
        var prevEnd: Int? = nil

        for i in (s + 1)..<e {
            let line = allLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed

            if let entry = parseTimeEntrySequential(parseLine, previousEndMinutes: prevEnd) {
                prevEnd = entry.endMinutes

                let numMatch = item.num.map { n -> Bool in
                    if let pIdx = parseLine.firstIndex(of: ")"),
                       let lineNum = Int(String(parseLine[parseLine.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)) {
                        return lineNum == n
                    }
                    return false
                } ?? true

                if numMatch &&
                   entry.startMinutes == item.originalStart &&
                   entry.endMinutes == item.originalEnd &&
                   entry.description == item.originalDesc {
                    let numStr = item.num.map { "\($0)) " } ?? ""
                    let fixedMark = item.fixed ? "**" : ""
                    let updated = "\(numStr)\(safeMinutesToTime(newStart)) - \(safeMinutesToTime(newEnd)) - \(fixedMark)\(newDesc)\(fixedMark)"
                    newLines[i] = isStruck ? "~~\(updated)~~" : updated
                    break
                }
            }
        }

        notesText = newLines.joined(separator: "\n")
        editorKey = UUID()
        saveNotes()
    }

    // MARK: - Formatted Schedule View

    private var hasSchedule: Bool {
        let lines = notesText.components(separatedBy: .newlines)
        var foundStart = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" { foundStart = true }
            else if t == "END" && foundStart { return true }
        }
        return false
    }

    private func parseFormattedTaskItems() -> [(num: Int?, start: Int, end: Int, desc: String, struck: Bool, fixed: Bool, isReward: Bool, isNotCompleted: Bool)] {
        let allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil
        var eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return [] }

        var result: [(num: Int?, start: Int, end: Int, desc: String, struck: Bool, fixed: Bool, isReward: Bool, isNotCompleted: Bool)] = []
        var prevEnd: Int? = nil

        for line in allLines[(s + 1)..<e] {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed

            let isReward        = parseLine.contains(" [🎁]")
            let isNotCompleted  = parseLine.contains(" [✗]")
            let parseLineClean  = parseLine
                .replacingOccurrences(of: " [🎁]", with: "")
                .replacingOccurrences(of: " [✗]",  with: "")

            var num: Int? = nil
            if let parenIdx = parseLineClean.firstIndex(of: ")") {
                let prefix = String(parseLineClean[parseLineClean.startIndex..<parenIdx])
                num = Int(prefix.trimmingCharacters(in: .whitespaces))
            }

            if let entry = parseTimeEntrySequential(parseLineClean, previousEndMinutes: prevEnd) {
                result.append((num: num, start: entry.startMinutes, end: entry.endMinutes,
                               desc: entry.description, struck: isStruck, fixed: entry.isFixed,
                               isReward: isReward, isNotCompleted: isNotCompleted))
                prevEnd = entry.endMinutes
            }
        }
        return result
    }

    private func toggleStrikeTask(startMin: Int, endMin: Int, desc: String) {
        var lines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil
        var eIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return }
        var prevEnd: Int? = nil
        var wasStruck = false
        for i in (s + 1)..<e {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            if let entry = parseTimeEntrySequential(parseLine, previousEndMinutes: prevEnd) {
                if entry.startMinutes == startMin && entry.endMinutes == endMin && entry.description == desc {
                    wasStruck = isStruck
                    lines[i] = isStruck ? parseLine : "~~\(trimmed)~~"
                    break
                }
                prevEnd = entry.endMinutes
            }
        }
        notesText = lines.joined(separator: "\n")
        saveNotes()

        // Award credits when marking as done (not when un-striking)
        if !wasStruck {
            let durationMinutes = endMin - startMin
            awardDailyNoteCredits(blockDescription: desc, durationMinutes: durationMinutes)
        }
    }

    private func awardDailyNoteCredits(blockDescription: String, durationMinutes: Int) {
        guard durationMinutes > 0 else { return }
        let matches = activeActivities.filter { $0.matchesDailyNoteBlock(blockDescription) }
        guard !matches.isEmpty else { return }
        var totalCredits = 0
        var names: [String] = []
        for activity in matches {
            let earned = activity.earnFromDailyNote(durationMinutes: durationMinutes, context: modelContext)
            if earned > 0 {
                totalCredits += earned
                names.append(activity.name)
            }
        }
        try? modelContext.save()
        if totalCredits > 0 {
            let nameList = names.joined(separator: ", ")
            creditEarnedMessage = "+\(totalCredits) credit\(totalCredits == 1 ? "" : "s") → \(nameList)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                creditEarnedMessage = ""
            }
        }
    }

    private func toggleNotCompletedTask(startMin: Int, endMin: Int, desc: String) {
        var lines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil, eIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return }
        var prevEnd: Int? = nil
        for i in (s + 1)..<e {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let isStruck  = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            let clean     = parseLine.replacingOccurrences(of: " [🎁]", with: "")
                                     .replacingOccurrences(of: " [✗]",  with: "")
            if let entry = parseTimeEntrySequential(clean, previousEndMinutes: prevEnd) {
                if entry.startMinutes == startMin && entry.endMinutes == endMin && entry.description == desc {
                    let toggled: String
                    if parseLine.contains(" [✗]") {
                        toggled = parseLine.replacingOccurrences(of: " [✗]", with: "")
                    } else {
                        // Remove completed mark, add not-completed
                        let noStrike = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
                        let withTag  = noStrike + " [✗]"
                        lines[i] = withTag
                        notesText = lines.joined(separator: "\n")
                        saveNotes()
                        return
                    }
                    lines[i] = isStruck ? String(trimmed.dropFirst(2).dropLast(2)).replacingOccurrences(of: " [✗]", with: "") : toggled
                    notesText = lines.joined(separator: "\n")
                    saveNotes()
                    return
                }
                prevEnd = entry.endMinutes
            }
        }
    }

    private func toggleRewardTask(startMin: Int, endMin: Int, desc: String) {
        var lines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil
        var eIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return }
        var prevEnd: Int? = nil
        for i in (s + 1)..<e {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            let parseLineClean = parseLine.replacingOccurrences(of: " [🎁]", with: "")
            if let entry = parseTimeEntrySequential(parseLineClean, previousEndMinutes: prevEnd) {
                if entry.startMinutes == startMin && entry.endMinutes == endMin && entry.description == desc {
                    let toggled: String
                    if parseLine.contains(" [🎁]") {
                        toggled = parseLine.replacingOccurrences(of: " [🎁]", with: "")
                    } else {
                        toggled = parseLine + " [🎁]"
                    }
                    lines[i] = isStruck ? "~~\(toggled)~~" : toggled
                    break
                }
                prevEnd = entry.endMinutes
            }
        }
        notesText = lines.joined(separator: "\n")
        saveNotes()
    }

    private func deleteScheduleTask(startMin: Int, endMin: Int, desc: String) {
        var lines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil
        var eIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return }
        var prevEnd: Int? = nil
        var removeIdx: Int? = nil
        for i in (s + 1)..<e {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let parseLine = (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~"))
                ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            if let entry = parseTimeEntrySequential(parseLine, previousEndMinutes: prevEnd) {
                if entry.startMinutes == startMin && entry.endMinutes == endMin && entry.description == desc {
                    removeIdx = i
                    break
                }
                prevEnd = entry.endMinutes
            }
        }
        if let idx = removeIdx {
            lines.remove(at: idx)
            notesText = lines.joined(separator: "\n")
            saveNotes()
        }
    }

    /// Deletes a task and shifts all downstream non-fixed tasks earlier by `shiftBy` minutes.
    private func deleteScheduleTaskAndShift(startMin: Int, endMin: Int, desc: String, shiftBy: Int) {
        guard shiftBy > 0 else { deleteScheduleTask(startMin: startMin, endMin: endMin, desc: desc); return }
        let allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil, eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return }

        struct ParsedRow { let lineIdx: Int; let startMin: Int; let endMin: Int; let desc: String; let isFixed: Bool; let isStruck: Bool; let num: Int? }
        var rows: [ParsedRow] = []
        var prevEnd: Int? = nil
        for i in (s + 1)..<e {
            let line = allLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            guard let entry = parseTimeEntrySequential(parseLine, previousEndMinutes: prevEnd) else { continue }
            var num: Int? = nil
            if let pIdx = parseLine.firstIndex(of: ")"),
               let n = Int(String(parseLine[parseLine.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)), n > 0, n < 1000 { num = n }
            rows.append(ParsedRow(lineIdx: i, startMin: entry.startMinutes, endMin: entry.endMinutes, desc: entry.description, isFixed: entry.isFixed, isStruck: isStruck, num: num))
            prevEnd = entry.endMinutes
        }

        guard let ti = rows.firstIndex(where: { $0.startMin == startMin && $0.endMin == endMin && $0.desc == desc }) else { return }

        var newLines = allLines
        // Shift downstream non-fixed tasks first (indices still valid)
        for idx in (ti + 1)..<rows.count {
            let row = rows[idx]
            if !row.isFixed {
                let ns = max(0, row.startMin - shiftBy)
                let ne = max(ns + 1, row.endMin - shiftBy)
                let numStr    = row.num.map { "\($0)) " } ?? ""
                let fixedMark = row.isFixed ? "**" : ""
                let rebuilt   = "\(numStr)\(safeMinutesToTime(ns)) - \(safeMinutesToTime(ne)) - \(fixedMark)\(row.desc)\(fixedMark)"
                newLines[row.lineIdx] = row.isStruck ? "~~\(rebuilt)~~" : rebuilt
            }
        }
        // Remove the target line
        newLines.remove(at: rows[ti].lineIdx)
        notesText = newLines.joined(separator: "\n")
        editorKey = UUID()
        saveNotes()
    }

    /// Removes the currently-running task from the schedule (used by the cancel menu).
    /// If `adjustTime` is true, shifts all downstream non-fixed tasks earlier by the task's remaining time.
    private func removeCurrentTaskFromNotes(adjustTime: Bool) {
        let now = Date()
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let timeEntries = extractTimeEntriesFromNotes()
        guard let cur = findBestCurrentTask(at: nowMin, in: timeEntries) else {
            guard currentTaskName == "Rest up" || currentTaskName == "Free time" else { return }
            if adjustTime,
               let nextTask = timeEntries.first(where: { $0.startMinutes >= nowMin }) {
                let pullForward = nextTask.startMinutes - nowMin
                guard pullForward > 0,
                      let startTagRange = notesText.range(of: "START"),
                      let endTagRange   = notesText.range(of: "END") else { return }
                let lines = String(notesText[startTagRange.upperBound..<endTagRange.lowerBound])
                                .components(separatedBy: .newlines)
                var result: [String] = []
                var prevEnd: Int? = nil
                var reachedNext = false
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")) || trimmed.contains("~~") {
                        result.append(line); continue
                    }
                    if let entry = parseTimeEntrySequential(line, previousEndMinutes: prevEnd) {
                        if !reachedNext && entry.startMinutes >= nextTask.startMinutes { reachedNext = true }
                        if reachedNext && !entry.isFixed {
                            var numStr = ""
                            if let pIdx = trimmed.firstIndex(of: ")"),
                               let n = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)) { numStr = "\(n)) " }
                            result.append("\(numStr)\(safeMinutesToTime(entry.startMinutes - pullForward)) - \(safeMinutesToTime(entry.endMinutes - pullForward)) - \(entry.description)")
                            prevEnd = entry.endMinutes - pullForward
                        } else { result.append(line); prevEnd = entry.endMinutes }
                    } else { result.append(line) }
                }
                notesText = String(notesText[..<startTagRange.lowerBound]) + "START"
                          + result.joined(separator: "\n") + "END"
                          + String(notesText[endTagRange.upperBound...])
                editorKey = UUID(); saveNotes()
                let updated = extractTimeEntriesFromNotes()
                if let next = updated.first(where: { $0.startMinutes >= nowMin }) {
                    let secs = (next.endMinutes - nowMin) * 60
                    if secs > 0 { settings.nextAlertDate = now.addingTimeInterval(TimeInterval(secs)); currentTaskName = next.description }
                }
            }
            speechManager.speak(adjustTime ? "Gap collapsed" : "Nothing to remove during rest")
            if settings.isPlaying { settings.scheduleIntervalTimer() }
            else if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
            return
        }

        let remainingMin = max(0, cur.endMinutes - nowMin)
        if adjustTime && remainingMin > 0 {
            deleteScheduleTaskAndShift(startMin: cur.startMinutes, endMin: cur.endMinutes, desc: cur.description, shiftBy: remainingMin)
        } else {
            deleteScheduleTask(startMin: cur.startMinutes, endMin: cur.endMinutes, desc: cur.description)
        }

        // Advance the timer to the next task
        let updated = extractTimeEntriesFromNotes()
        if let next = updated.first(where: { $0.startMinutes >= nowMin && !$0.description.isEmpty }) {
            let secs = (next.endMinutes - nowMin) * 60
            if secs > 0 {
                settings.nextAlertDate = now.addingTimeInterval(TimeInterval(secs))
                currentTaskName = next.description
            }
        }
        if settings.isPlaying { settings.scheduleIntervalTimer() }
        else if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
    }

    private func clearZeroDurationSchedule() {
        var lines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil
        var eIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return }
        var prevEnd: Int? = nil
        var removeIndices: [Int] = []
        for i in (s + 1)..<e {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let parseLine = (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~"))
                ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            if let entry = parseTimeEntrySequential(parseLine, previousEndMinutes: prevEnd) {
                if entry.startMinutes == entry.endMinutes {
                    removeIndices.append(i)
                } else {
                    prevEnd = entry.endMinutes
                }
            }
        }
        for idx in removeIndices.reversed() { lines.remove(at: idx) }
        if !removeIndices.isEmpty {
            notesText = lines.joined(separator: "\n")
            saveNotes()
        }
    }

    private var scheduleFormattedView: some View {
        let nowMin = Calendar.current.component(.hour, from: currentTime) * 60
                   + Calendar.current.component(.minute, from: currentTime)
        let tasks = parseFormattedTaskItems()

        let allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil
        var eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }

        return VStack(alignment: .leading, spacing: 6) {
            // Credit earned feedback banner
            if !creditEarnedMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(creditEarnedMessage)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Pre-schedule content
            if let s = sIdx, s > 0 {
                let preText = allLines[0..<s]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")
                if !preText.isEmpty {
                    Text(preText)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }
            }

            // Task rows
            ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                if !hideFinishedTasks || !task.struck {
                    taskDisplayRow(num: task.num, startMin: task.start, endMin: task.end,
                                   desc: task.desc, struck: task.struck, fixed: task.fixed,
                                   isReward: task.isReward, isNotCompleted: task.isNotCompleted, nowMin: nowMin,
                                   onToggleStrike: { toggleStrikeTask(startMin: task.start, endMin: task.end, desc: task.desc) },
                                   onToggleReward: { toggleRewardTask(startMin: task.start, endMin: task.end, desc: task.desc) },
                                   onToggleNotCompleted: { toggleNotCompletedTask(startMin: task.start, endMin: task.end, desc: task.desc) },
                                   onDelete: {
                                       pendingDeleteStart = task.start
                                       pendingDeleteEnd   = task.end
                                       pendingDeleteDesc  = task.desc
                                       showDeleteOptions  = true
                                   })
                    .onTapGesture {
                        editingTask = EditTaskItem(
                            num: task.num,
                            originalStart: task.start,
                            originalEnd: task.end,
                            originalDesc: task.desc,
                            struck: task.struck,
                            fixed: task.fixed
                        )
                    }
                }
            }

            // Post-schedule content
            if let e = eIdx, e + 1 < allLines.count {
                let postText = allLines[(e + 1)...]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")
                if !postText.isEmpty {
                    Text(postText)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func taskDisplayRow(num: Int?, startMin: Int, endMin: Int, desc: String,
                                struck: Bool, fixed: Bool, isReward: Bool = false,
                                isNotCompleted: Bool = false, nowMin: Int,
                                onToggleStrike: (() -> Void)? = nil,
                                onToggleReward: (() -> Void)? = nil,
                                onToggleNotCompleted: (() -> Void)? = nil,
                                onDelete: (() -> Void)? = nil) -> some View {
        let isCurrent = !struck && nowMin >= startMin && nowMin < endMin
        let isPastUnack = !struck && nowMin >= endMin
        let isFutureReward = isReward && !struck && nowMin < startMin
        let gold = Color(hue: 0.12, saturation: 0.9, brightness: 0.95)
        let accentColor: Color = struck ? .green : (isReward && !isPastUnack ? gold : (isCurrent ? .blue : (isPastUnack ? .orange : .primary)))
        let duration = endMin - startMin

        // Countdown text for future reward tasks
        let countdownLabel: String? = {
            guard isFutureReward else { return nil }
            let mins = startMin - nowMin
            let h = mins / 60, m = mins % 60
            return h > 0 ? "in \(h)h \(m)m" : "in \(m)m"
        }()

        HStack(spacing: 12) {
            // Number/status badge
            ZStack {
                Circle()
                    .fill(accentColor.opacity(struck ? 0.2 : (isCurrent ? 0.18 : (isReward ? 0.22 : 0.1))))
                    .frame(width: 34, height: 34)
                if isReward && !struck {
                    Text("🎁")
                        .font(.system(size: 14))
                } else if let n = num {
                    Text("\(n)")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundColor(accentColor)
                } else {
                    Image(systemName: struck ? "checkmark" : (isCurrent ? "play.fill" : "circle.fill"))
                        .font(.system(size: 10))
                        .foregroundColor(accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if fixed {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                    Text(desc)
                        .font(.subheadline)
                        .fontWeight((isCurrent || isReward) ? .semibold : .regular)
                        .foregroundColor(struck ? .secondary : .primary)
                        .strikethrough(struck, color: .secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text("\(safeMinutesToTime(startMin)) – \(safeMinutesToTime(endMin))")
                        .font(.caption)
                        .foregroundColor(accentColor.opacity(0.85))
                        .monospacedDigit()
                    if isCurrent && isReward {
                        Text("🎁 NOW")
                            .font(.caption2.bold())
                            .foregroundColor(gold)
                    } else if let label = countdownLabel {
                        Text(label)
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundColor(gold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(gold.opacity(0.15), in: Capsule())
                    }
                }
            }

            Spacer()

            Text("\(duration)m")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.1), in: Capsule())

            if let badge = distractionTracker.badgeText(date: selectedDate, startMin: startMin, desc: desc) {
                Text(badge)
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }

            if let onToggleReward {
                Button(action: onToggleReward) {
                    Image(systemName: isReward ? "gift.fill" : "gift")
                        .font(.caption)
                        .foregroundColor(isReward ? gold : .secondary.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
            }

            if let onToggleStrike {
                Button(action: onToggleStrike) {
                    Image(systemName: struck ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundColor(struck ? .green : .secondary.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
            }

            if let onToggleNotCompleted {
                Button(action: onToggleNotCompleted) {
                    Image(systemName: isNotCompleted ? "xmark.circle.fill" : "xmark.circle")
                        .font(.caption)
                        .foregroundColor(isNotCompleted ? .red : .secondary.opacity(0.4))
                }
                .buttonStyle(PlainButtonStyle())
            }

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isReward && !struck ? gold.opacity(0.08) : (isCurrent ? Color.blue.opacity(0.07) : Color.secondary.opacity(0.05)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(isCurrent || (isReward && !struck) ? 0.45 : 0.15), lineWidth: isReward && !struck ? 1.5 : 1)
        )
    }

    // MARK: - Interrupt Current Task

    private func insertInterruptTask() {
        let now = Date()
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        let timeEntries = extractTimeEntriesFromNotes()
        guard let currentEntry = findBestCurrentTask(at: nowMin, in: timeEntries) else {
            if currentTaskName == "Rest up" || currentTaskName == "Free time" {
                let interruptDuration = 5
                settings.nextAlertDate = now.addingTimeInterval(TimeInterval(interruptDuration * 60))
                insertNamedBlockAtGap(blockName: "interrupt", blockDuration: interruptDuration, nowMin: nowMin)
                currentTaskName = "interrupt"
                speechManager.speak("Interrupt added")
                if settings.isPlaying { settings.scheduleIntervalTimer() }
                else if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
            }
            return
        }

        let remainingMin = currentEntry.endMinutes - nowMin
        guard remainingMin > 0 else { return }

        let interruptDuration = 5  // fixed 5-minute interrupt

        // Live timer counts down the interrupt duration
        settings.nextAlertDate = now.addingTimeInterval(TimeInterval(interruptDuration * 60))

        guard let startTagRange = notesText.range(of: "START"),
              let endTagRange   = notesText.range(of: "END") else { return }

        let content = String(notesText[startTagRange.upperBound..<endTagRange.lowerBound])
        let lines   = content.components(separatedBy: .newlines)
        var result: [String] = []
        var prevEnd: Int? = nil
        var foundCurrent = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")) || trimmed.contains("~~") {
                result.append(line)
                continue
            }

            if let entry = parseTimeEntrySequential(line, previousEndMinutes: prevEnd) {
                let isCurrentTask = entry.startMinutes == currentEntry.startMinutes &&
                                    entry.endMinutes   == currentEntry.endMinutes &&
                                    entry.description  == currentEntry.description

                if isCurrentTask {
                    foundCurrent = true

                    // Extract existing number prefix
                    var baseNum: Int? = nil
                    if let pIdx = trimmed.firstIndex(of: ")") {
                        baseNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces))
                    }

                    // Part 1 – already-elapsed portion of original task
                    let part1Num = baseNum.map { "\($0)) " } ?? ""
                    result.append("\(part1Num)\(safeMinutesToTime(entry.startMinutes)) - \(safeMinutesToTime(nowMin)) - \(entry.description)")

                    // Part 2 – 5-minute interrupt
                    let part2Num = baseNum.map { "\($0 + 1)) " } ?? ""
                    result.append("\(part2Num)\(safeMinutesToTime(nowMin)) - \(safeMinutesToTime(nowMin + interruptDuration)) - interrupt")

                    // Part 3 – resume original task for its full remaining duration
                    let part3Num = baseNum.map { "\($0 + 2)) " } ?? ""
                    result.append("\(part3Num)\(safeMinutesToTime(nowMin + interruptDuration)) - \(safeMinutesToTime(nowMin + interruptDuration + remainingMin)) - \(entry.description)")

                    prevEnd = nowMin + interruptDuration + remainingMin

                } else if foundCurrent && entry.startMinutes >= currentEntry.endMinutes && !entry.isFixed {
                    // Shift time forward by interruptDuration AND bump number by +2
                    var shiftedNum: Int? = nil
                    if let pIdx = trimmed.firstIndex(of: ")") {
                        shiftedNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)).map { $0 + 2 }
                    }
                    let numStr   = shiftedNum.map { "\($0)) " } ?? ""
                    let newStart = safeMinutesToTime(entry.startMinutes + interruptDuration)
                    let newEnd   = safeMinutesToTime(entry.endMinutes   + interruptDuration)
                    result.append("\(numStr)\(newStart) - \(newEnd) - \(entry.description)")
                    prevEnd = entry.endMinutes + interruptDuration

                } else {
                    result.append(line)
                    prevEnd = entry.endMinutes
                }
            } else {
                result.append(line)
            }
        }

        let beforeStart = String(notesText[..<startTagRange.lowerBound])
        let afterEnd    = String(notesText[endTagRange.upperBound...])
        notesText = beforeStart + "START" + result.joined(separator: "\n") + "END" + afterEnd
        editorKey = UUID()
        saveNotes()

        // Update running task name immediately
        currentTaskName = "interrupt"
        speechManager.speak("Interrupt added")
        // Reschedule timer to new nextAlertDate and refresh Live Activity
        if settings.isPlaying { settings.scheduleIntervalTimer() }
        else if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
    }

    // MARK: - Adjust Schedule (+5 min adjust block)

    private func insertAdjustTask(fromStrikethrough: Bool) {
        let now = Date()
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let adjustDuration = 5

        guard let startTagRange = notesText.range(of: "START"),
              let endTagRange   = notesText.range(of: "END") else { return }

        let content = String(notesText[startTagRange.upperBound..<endTagRange.lowerBound])
        let lines   = content.components(separatedBy: .newlines)
        var result: [String] = []
        var prevEnd: Int? = nil

        if fromStrikethrough {
            // Shift all non-struck tasks so the first one starts at now
            var firstNonStruckStart: Int? = nil
            var scanPrev: Int? = nil
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~") {
                    let inner = String(trimmed.dropFirst(2).dropLast(2))
                    if let e = parseTimeEntrySequential(inner, previousEndMinutes: scanPrev) { scanPrev = e.endMinutes }
                    continue
                }
                if trimmed.contains("~~") { continue }
                if let e = parseTimeEntrySequential(line, previousEndMinutes: scanPrev) {
                    firstNonStruckStart = e.startMinutes
                    break
                }
            }

            guard let firstStart = firstNonStruckStart else { return }
            let shiftAmount = nowMin - firstStart
            guard shiftAmount > 0 else { return }

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~") {
                    result.append(line)
                    let inner = String(trimmed.dropFirst(2).dropLast(2))
                    if let e = parseTimeEntrySequential(inner, previousEndMinutes: prevEnd) { prevEnd = e.endMinutes }
                    continue
                }
                if trimmed.contains("~~") { result.append(line); continue }
                if let entry = parseTimeEntrySequential(line, previousEndMinutes: prevEnd) {
                    if !entry.isFixed {
                        var numStr = ""
                        if let pIdx = trimmed.firstIndex(of: ")"),
                           let n = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)) {
                            numStr = "\(n)) "
                        }
                        let newStart = safeMinutesToTime(entry.startMinutes + shiftAmount)
                        let newEnd   = safeMinutesToTime(entry.endMinutes + shiftAmount)
                        result.append("\(numStr)\(newStart) - \(newEnd) - \(entry.description)")
                        prevEnd = entry.endMinutes + shiftAmount
                    } else {
                        result.append(line)
                        prevEnd = entry.endMinutes
                    }
                } else {
                    result.append(line)
                }
            }

            speechManager.speak("Schedule adjusted from last completed task")

        } else {
            // Insert 5-min adjust block before the current task; shift current + future tasks
            let timeEntries = extractTimeEntriesFromNotes()
            guard let currentEntry = findBestCurrentTask(at: nowMin, in: timeEntries) else {
                if currentTaskName == "Rest up" || currentTaskName == "Free time" {
                    settings.nextAlertDate = now.addingTimeInterval(TimeInterval(adjustDuration * 60))
                    insertNamedBlockAtGap(blockName: "adjust", blockDuration: adjustDuration, nowMin: nowMin)
                    currentTaskName = "adjust"
                    speechManager.speak("Adjust added")
                    if settings.isPlaying { settings.scheduleIntervalTimer() }
                    else if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
                }
                return
            }

            var foundCurrent = false
            let shiftAmount = (nowMin + adjustDuration) - currentEntry.startMinutes

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

                if (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")) || trimmed.contains("~~") {
                    result.append(line)
                    continue
                }

                if let entry = parseTimeEntrySequential(line, previousEndMinutes: prevEnd) {
                    let isCurrentTask = entry.startMinutes == currentEntry.startMinutes &&
                                        entry.endMinutes   == currentEntry.endMinutes &&
                                        entry.description  == currentEntry.description

                    if isCurrentTask {
                        foundCurrent = true
                        var baseNum: Int? = nil
                        if let pIdx = trimmed.firstIndex(of: ")") {
                            baseNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces))
                        }
                        let adjustNum = baseNum.map { "\($0)) " } ?? ""
                        result.append("\(adjustNum)\(safeMinutesToTime(nowMin)) - \(safeMinutesToTime(nowMin + adjustDuration)) - adjust")

                        let taskNum = baseNum.map { "\($0 + 1)) " } ?? ""
                        let taskDuration = entry.endMinutes - entry.startMinutes
                        result.append("\(taskNum)\(safeMinutesToTime(nowMin + adjustDuration)) - \(safeMinutesToTime(nowMin + adjustDuration + taskDuration)) - \(entry.description)")
                        prevEnd = nowMin + adjustDuration + taskDuration

                    } else if foundCurrent && entry.startMinutes >= currentEntry.endMinutes && !entry.isFixed {
                        var shiftedNum: Int? = nil
                        if let pIdx = trimmed.firstIndex(of: ")") {
                            shiftedNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)).map { $0 + 1 }
                        }
                        let numStr   = shiftedNum.map { "\($0)) " } ?? ""
                        let newStart = safeMinutesToTime(entry.startMinutes + shiftAmount)
                        let newEnd   = safeMinutesToTime(entry.endMinutes   + shiftAmount)
                        result.append("\(numStr)\(newStart) - \(newEnd) - \(entry.description)")
                        prevEnd = entry.endMinutes + shiftAmount

                    } else {
                        result.append(line)
                        prevEnd = entry.endMinutes
                    }
                } else {
                    result.append(line)
                }
            }

            currentTaskName = "adjust"
            settings.nextAlertDate = now.addingTimeInterval(TimeInterval(adjustDuration * 60))
            speechManager.speak("Adjust added")
            if settings.isPlaying { settings.scheduleIntervalTimer() }
        }

        let beforeStart = String(notesText[..<startTagRange.lowerBound])
        let afterEnd    = String(notesText[endTagRange.upperBound...])
        notesText = beforeStart + "START" + result.joined(separator: "\n") + "END" + afterEnd
        editorKey = UUID()
        saveNotes()
        if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
    }

    // MARK: - End Current Task and Start New

    private func endAndStartNewTask() {
        let now = Date()
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        let timeEntries = extractTimeEntriesFromNotes()
        guard let currentEntry = findBestCurrentTask(at: nowMin, in: timeEntries) else {
            if currentTaskName == "Rest up" || currentTaskName == "Free time" {
                let newTaskDuration = 5
                settings.nextAlertDate = now.addingTimeInterval(TimeInterval(newTaskDuration * 60))
                insertNamedBlockAtGap(blockName: "new task", blockDuration: newTaskDuration, nowMin: nowMin)
                currentTaskName = "new task"
                speechManager.speak("New task started")
                if settings.isPlaying { settings.scheduleIntervalTimer() }
                else if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
            }
            return
        }

        let newTaskDuration = 5
        let shiftAmount = (nowMin + newTaskDuration) - currentEntry.endMinutes

        settings.nextAlertDate = now.addingTimeInterval(TimeInterval(newTaskDuration * 60))

        guard let startTagRange = notesText.range(of: "START"),
              let endTagRange   = notesText.range(of: "END") else { return }

        let content = String(notesText[startTagRange.upperBound..<endTagRange.lowerBound])
        let lines   = content.components(separatedBy: .newlines)
        var result: [String] = []
        var prevEnd: Int? = nil
        var foundCurrent = false
        var waveEnd = currentEntry.endMinutes
        var doneShifting = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")) || trimmed.contains("~~") {
                result.append(line)
                continue
            }

            if let entry = parseTimeEntrySequential(line, previousEndMinutes: prevEnd) {
                let isCurrentTask = entry.startMinutes == currentEntry.startMinutes &&
                                    entry.endMinutes   == currentEntry.endMinutes &&
                                    entry.description  == currentEntry.description

                if isCurrentTask {
                    foundCurrent = true

                    var baseNum: Int? = nil
                    if let pIdx = trimmed.firstIndex(of: ")") {
                        baseNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces))
                    }

                    let part1Num = baseNum.map { "\($0)) " } ?? ""
                    result.append("\(part1Num)\(safeMinutesToTime(entry.startMinutes)) - \(safeMinutesToTime(nowMin)) - \(entry.description)")

                    let part2Num = baseNum.map { "\($0 + 1)) " } ?? ""
                    result.append("\(part2Num)\(safeMinutesToTime(nowMin)) - \(safeMinutesToTime(nowMin + newTaskDuration)) - new task")

                    prevEnd = nowMin + newTaskDuration

                } else if foundCurrent && !entry.isFixed && !doneShifting {
                    if entry.startMinutes > waveEnd {
                        // Gap — stop the shift wave; append this and all remaining unchanged
                        doneShifting = true
                        result.append(line)
                        prevEnd = entry.endMinutes
                    } else {
                        waveEnd = max(waveEnd, entry.endMinutes)
                        var shiftedNum: Int? = nil
                        if let pIdx = trimmed.firstIndex(of: ")") {
                            shiftedNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)).map { $0 + 1 }
                        }
                        let numStr   = shiftedNum.map { "\($0)) " } ?? ""
                        let newStart = safeMinutesToTime(max(0, entry.startMinutes + shiftAmount))
                        let newEnd   = safeMinutesToTime(max(0, entry.endMinutes   + shiftAmount))
                        result.append("\(numStr)\(newStart) - \(newEnd) - \(entry.description)")
                        prevEnd = entry.endMinutes + shiftAmount
                    }
                } else {
                    result.append(line)
                    prevEnd = entry.endMinutes
                }
            } else {
                result.append(line)
            }
        }

        let beforeStart = String(notesText[..<startTagRange.lowerBound])
        let afterEnd    = String(notesText[endTagRange.upperBound...])
        notesText = beforeStart + "START" + result.joined(separator: "\n") + "END" + afterEnd
        editorKey = UUID()
        saveNotes()

        currentTaskName = "new task"
        speechManager.speak("New task started")
        if settings.isPlaying { settings.scheduleIntervalTimer() }
        else if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
    }

    // MARK: - Stop Current Task at Now & Skip to Next

    private func cancelCurrentTask() {
        let now = Date()
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        let timeEntries = extractTimeEntriesFromNotes()
        guard let currentEntry = findBestCurrentTask(at: nowMin, in: timeEntries) else {
            // During rest up / free time — skip to the next scheduled task immediately
            if currentTaskName == "Rest up" || currentTaskName == "Free time" {
                if let next = timeEntries.first(where: { $0.startMinutes >= nowMin && !$0.description.isEmpty }) {
                    let secs = (next.endMinutes - nowMin) * 60
                    if secs > 0 {
                        settings.nextAlertDate = now.addingTimeInterval(TimeInterval(secs))
                        currentTaskName = next.description
                    }
                }
                speechManager.speak("Skipping rest, moving to next task")
                if settings.isPlaying { settings.scheduleIntervalTimer() }
                else if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
            }
            return
        }

        // Shift = how much earlier following tasks move (usually negative)
        let shiftAmount = nowMin - currentEntry.endMinutes

        guard let startTagRange = notesText.range(of: "START"),
              let endTagRange   = notesText.range(of: "END") else { return }

        let content = String(notesText[startTagRange.upperBound..<endTagRange.lowerBound])
        let lines   = content.components(separatedBy: .newlines)
        var result: [String] = []
        var prevEnd: Int? = nil
        var foundCurrent = false
        var waveEnd = currentEntry.endMinutes
        var doneShifting = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")) || trimmed.contains("~~") {
                result.append(line)
                continue
            }

            if let entry = parseTimeEntrySequential(line, previousEndMinutes: prevEnd) {
                let isCurrentTask = entry.startMinutes == currentEntry.startMinutes &&
                                    entry.endMinutes   == currentEntry.endMinutes &&
                                    entry.description  == currentEntry.description

                if isCurrentTask {
                    foundCurrent = true
                    let numStr: String
                    if let pIdx = trimmed.firstIndex(of: ")"),
                       let num = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)) {
                        numStr = "\(num)) "
                    } else {
                        numStr = ""
                    }
                    result.append("\(numStr)\(safeMinutesToTime(entry.startMinutes)) - \(safeMinutesToTime(nowMin)) - \(entry.description)")
                    prevEnd = nowMin

                } else if foundCurrent && !entry.isFixed && !doneShifting {
                    if entry.startMinutes > waveEnd {
                        // Gap — stop the shift wave
                        doneShifting = true
                        result.append(line)
                        prevEnd = entry.endMinutes
                    } else {
                        waveEnd = max(waveEnd, entry.endMinutes)
                        let numStr: String
                        if let pIdx = trimmed.firstIndex(of: ")"),
                           let num = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)) {
                            numStr = "\(num)) "
                        } else {
                            numStr = ""
                        }
                        let newStart = safeMinutesToTime(max(0, entry.startMinutes + shiftAmount))
                        let newEnd   = safeMinutesToTime(max(0, entry.endMinutes   + shiftAmount))
                        result.append("\(numStr)\(newStart) - \(newEnd) - \(entry.description)")
                        prevEnd = entry.endMinutes + shiftAmount
                    }
                } else {
                    result.append(line)
                    prevEnd = entry.endMinutes
                }
            } else {
                result.append(line)
            }
        }

        let beforeStart = String(notesText[..<startTagRange.lowerBound])
        let afterEnd    = String(notesText[endTagRange.upperBound...])
        notesText = beforeStart + "START" + result.joined(separator: "\n") + "END" + afterEnd
        editorKey = UUID()
        saveNotes()

        // Jump the timer to start counting the next task from now
        let updatedEntries = extractTimeEntriesFromNotes()
        if let nextEntry = updatedEntries.first(where: { $0.startMinutes >= nowMin && !$0.description.isEmpty }) {
            let remainingSecs = (nextEntry.endMinutes - nowMin) * 60
            if remainingSecs > 0 {
                settings.nextAlertDate = now.addingTimeInterval(TimeInterval(remainingSecs))
                currentTaskName = nextEntry.description
            }
        }
        speechManager.speak("Stopping task now, moving to next")
        if settings.isPlaying { settings.scheduleIntervalTimer() }
        else if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
    }

    // MARK: - Extend Current Task

    private func extendCurrentTask(byMinutes minutes: Int = 5) {
        let now = Date()
        let calendar = Calendar.current
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        let timeEntries = extractTimeEntriesFromNotes()
        guard let currentEntry = findBestCurrentTask(at: currentMinutes, in: timeEntries) else {
            // During rest up / free time there's no note entry — just push the timer forward
            if currentTaskName == "Rest up" || currentTaskName == "Free time" {
                settings.nextAlertDate = settings.nextAlertDate.addingTimeInterval(TimeInterval(minutes * 60))
                currentCycleDuration += minutes
                if settings.isPlaying { settings.scheduleIntervalTimer() }
                else if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
            }
            return
        }

        // Push the live timer forward and update displayed block duration
        settings.nextAlertDate = settings.nextAlertDate.addingTimeInterval(TimeInterval(minutes * 60))
        currentCycleDuration += minutes

        // Update notes: extend current task end + shift subsequent tasks
        guard let startTagRange = notesText.range(of: "START"),
              let endTagRange = notesText.range(of: "END") else { return }

        let content = String(notesText[startTagRange.upperBound..<endTagRange.lowerBound])
        let lines = content.components(separatedBy: .newlines)
        var result: [String] = []
        var prevEnd: Int? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")) || trimmed.contains("~~") {
                result.append(line)
                continue
            }
            if let entry = parseTimeEntrySequential(line, previousEndMinutes: prevEnd) {
                let isCurrentTask = entry.startMinutes == currentEntry.startMinutes &&
                                    entry.endMinutes == currentEntry.endMinutes &&
                                    entry.description == currentEntry.description
                if isCurrentTask {
                    let extended = TimeEntry(startMinutes: entry.startMinutes,
                                            endMinutes: entry.endMinutes + minutes,
                                            description: entry.description,
                                            isFixed: entry.isFixed,
                                            originalLine: entry.originalLine)
                    result.append(extended.toLine())
                    prevEnd = extended.endMinutes
                } else if entry.startMinutes >= currentEntry.endMinutes && !entry.isFixed {
                    let shifted = TimeEntry(startMinutes: entry.startMinutes + minutes,
                                           endMinutes: entry.endMinutes + minutes,
                                           description: entry.description,
                                           isFixed: entry.isFixed,
                                           originalLine: entry.originalLine)
                    result.append(shifted.toLine())
                    prevEnd = shifted.endMinutes
                } else {
                    result.append(line)
                    prevEnd = entry.endMinutes
                }
            } else {
                result.append(line)
            }
        }

        let beforeStart = String(notesText[..<startTagRange.lowerBound])
        let afterEnd = String(notesText[endTagRange.upperBound...])
        notesText = beforeStart + "START" + result.joined(separator: "\n") + "END" + afterEnd
        editorKey = UUID()
        saveNotes()
        speechManager.speak("Extended by \(minutes) minutes")
        if settings.isPlaying { settings.scheduleIntervalTimer() }
        else if #available(iOS 16.1, *) { settings.refreshLiveActivity() }
    }

    // MARK: - Insert Generated Tasks at Position

    private func insertGeneratedTasksAfter(taskNum: Int, scheduleLines: [String], shiftMinutes: Int) {
        var allLines = notesText.components(separatedBy: .newlines)
        var startIdx: Int?
        var endIdx: Int?

        for (i, line) in allLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "START" && startIdx == nil { startIdx = i }
            else if trimmed == "END" && startIdx != nil && endIdx == nil { endIdx = i; break }
        }

        // If no START/END block, wrap and append
        guard let sIdx = startIdx, let eIdx = endIdx else {
            let block = notesText.isEmpty
                ? "START\n\(scheduleLines.joined(separator: "\n"))\nEND"
                : notesText + "\nSTART\n\(scheduleLines.joined(separator: "\n"))\nEND"
            notesText = block
            editorKey = UUID()
            return
        }

        // Find the line for task #taskNum.
        // Default to eIdx - 1 so that insert(at: insertAfterLine + 1) = insert(at: eIdx),
        // placing new tasks just before the END tag when taskNum is 0 or not found.
        var insertAfterLine: Int = eIdx - 1
        for lineIdx in (sIdx + 1)..<eIdx {
            let line = allLines[lineIdx]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let clean = (trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~"))
                ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            if clean.range(of: "^\(taskNum)\\)\\s", options: .regularExpression) != nil {
                insertAfterLine = lineIdx
                break
            }
        }

        // If generated tasks start inside the "after" task, push them to start at its end.
        var adjustedLines = scheduleLines
        let afterRaw = allLines[insertAfterLine].trimmingCharacters(in: .whitespacesAndNewlines)
        let afterInner = (afterRaw.hasPrefix("~~") && afterRaw.hasSuffix("~~"))
            ? String(afterRaw.dropFirst(2).dropLast(2)) : afterRaw
        if let afterEntry = parseTimeEntry(afterInner) {
            if let firstEntry = scheduleLines.compactMap({ parseTimeEntry($0.trimmingCharacters(in: .whitespacesAndNewlines)) }).first,
               firstEntry.startMinutes < afterEntry.endMinutes {
                let delta = afterEntry.endMinutes - firstEntry.startMinutes
                let timePattern = #"(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)"#
                if let regex = try? NSRegularExpression(pattern: timePattern) {
                    adjustedLines = adjustedLines.map { interceptShiftTimeLine($0, by: delta, regex: regex) }
                }
            }
        }

        let newCount = adjustedLines.count
        let renumbered: [String] = adjustedLines.enumerated().map { (i, line) in
            line.replacingOccurrences(of: #"^\d+\)\s*"#, with: "\(taskNum + 1 + i)) ", options: .regularExpression)
        }

        allLines.insert(contentsOf: renumbered, at: insertAfterLine + 1)

        let shiftFrom = insertAfterLine + 1 + newCount
        let newEndIdx = eIdx + newCount

        // Wave end = end time of the last generated task (use adjusted times)
        var waveEnd: Int = 0
        for line in adjustedLines.reversed() {
            if let entry = parseTimeEntry(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                waveEnd = entry.endMinutes; break
            }
        }

        // Actual shift = overlap between generated block end and the first downstream task's start
        // (mirrors coreIntercept's shiftAmount = max(0, interceptEnd - firstStart))
        var actualShift = 0
        for lineIdx in shiftFrom..<newEndIdx {
            let t = allLines[lineIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            let w = (t.hasPrefix("~~") && t.hasSuffix("~~")) ? String(t.dropFirst(2).dropLast(2)) : t
            if let entry = parseTimeEntry(w) {
                actualShift = max(0, waveEnd - entry.startMinutes)
            }
            break
        }

        for lineIdx in shiftFrom..<newEndIdx {
            let line = allLines[lineIdx]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let workLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed

            // Wave check: stop if this task has a gap from the wave front
            if let entry = parseTimeEntry(workLine) {
                if entry.startMinutes > waveEnd { break }
                if !entry.isFixed { waveEnd = max(waveEnd, entry.endMinutes) }
            }

            // Extract old number prefix
            if let numRange = workLine.range(of: #"^\d+\)"#, options: .regularExpression) {
                let numStr = String(workLine[numRange].dropLast())
                if let oldNum = Int(numStr) {
                    let newNum = oldNum + newCount
                    var updated = workLine.replacingOccurrences(
                        of: #"^\d+\)\s*"#, with: "\(newNum)) ", options: .regularExpression)
                    if let entry = parseTimeEntry(updated), !entry.isFixed {
                        let newStart = formatMinutesToTime(entry.startMinutes + actualShift)
                        let newEnd = formatMinutesToTime(entry.endMinutes + actualShift)
                        updated = "\(newNum)) \(newStart) - \(newEnd) - \(entry.description)"
                    }
                    allLines[lineIdx] = isStruck ? "~~\(updated)~~" : updated
                }
            } else if let entry = parseTimeEntry(workLine), !entry.isFixed {
                let newStart = formatMinutesToTime(entry.startMinutes + actualShift)
                let newEnd = formatMinutesToTime(entry.endMinutes + actualShift)
                let updated = "\(newStart) - \(newEnd) - \(entry.description)"
                allLines[lineIdx] = isStruck ? "~~\(updated)~~" : updated
            }
        }

        notesText = allLines.joined(separator: "\n")
        editorKey = UUID()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Focus Mode View

struct ScheduleEntry: Identifiable {
    let id = UUID()
    let raw: String
    let startMinutes: Int?
    let endMinutes: Int?
    let task: String?
    let isStruck: Bool
}

struct FocusModeView: View {
    @Binding var isPresented: Bool
    let currentTaskName: String
    let selectedDate: Date
    let timeRemaining: TimeInterval
    @Binding var currentCycleDuration: Int
    let isTransitioning: Bool
    let isSmartPaused: Bool
    let pausedAt: Date?
    @Binding var notesText: String
    @ObservedObject var settings: AlertSettings
    let onSmartPause: () -> Void
    let onStrikePast: () -> Void
    let onExtendTask: () -> Void
    let onInterrupt: () -> Void
    let onAdjust: (Bool) -> Void
    let isWaitingForManualStart: Bool
    let manualWaitStartDate: Date?
    let pendingNextTaskName: String
    let totalIdleSeconds: Int
    let onStartManualNext: () -> Void
    let onExtendPrevious: () -> Void
    let onEndAndNew: () -> Void
    let onCancelTask: () -> Void
    let onRemoveCurrentAdjust: () -> Void
    let onRemoveCurrentOnly: () -> Void
    let onSwapTasks: (Int, Int) -> Bool
    let onNotesModified: () -> Void
    let computeSwapDefaults: () -> (Int?, Int?)
    let onRecalculateDistractions: () -> Void

    @Query(filter: #Predicate<Book> { $0.isActive }) private var activeBooks: [Book]
    @AppStorage("display.quotesInterval") private var intervalSeconds: Int = 10
    @AppStorage("display.quotesVisible") private var quotesVisible: Bool = true

    @State private var quotePool: [(text: String, bookTitle: String, author: String, chapterNumber: Int?, chapterName: String?)] = []
    @State private var currentIndex: Int = 0
    @State private var showQuote: Bool = true
    @State private var cycleTimer: Timer?
    @State private var currentTime: Date = Date()
    @State private var clockTimer: Timer?
    @State private var showSidebar = false
    @State private var showSwapSheetFocus = false
    @State private var focusSwapDefaults: (Int?, Int?) = (nil, nil)
    @State private var showCancelMenuFocus = false
    @State private var showAdjustOptionsFocus = false
    @State private var showClearDistractionsConfirm = false
    @AppStorage("focusSidebar.showActiveOnly") private var showActiveOnly: Bool = false

    private var timeRemainingFormatted: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatWaitCountUpFocus(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private var currentTaskTimeSlot: String? {
        guard let entry = activeScheduleEntry,
              let sm = entry.startMinutes, let em = entry.endMinutes else { return nil }
        return "\(fmtSlotMin(sm)) – \(fmtSlotMin(em))"
    }

    private func fmtSlotMin(_ m: Int) -> String {
        let h = (m / 60) % 24, mn = m % 60
        let suffix = h >= 12 ? "PM" : "AM"
        let dh = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", dh, mn, suffix)
    }

    private var activeScheduleEntry: ScheduleEntry? {
        let nowMin = nowMinutes
        return scheduleEntries.first { e in
            guard !e.isStruck,
                  let sm = e.startMinutes, let em = e.endMinutes else { return false }
            var taskClean = e.task ?? ""
            taskClean = taskClean.replacingOccurrences(of: " [🎁]", with: "")
            if let r = taskClean.range(of: DistractionTracker.metricsSuffixPattern, options: .regularExpression) {
                taskClean.removeSubrange(r)
            }
            return nowMin >= sm && nowMin < em && taskClean == currentTaskName
        }
    }

    private var currentTaskScheduleNumber: Int? {
        guard let raw = activeScheduleEntry?.raw,
              let pIdx = raw.firstIndex(of: ")"),
              let n = Int(String(raw[raw.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces))
        else { return nil }
        return n
    }

    private var focusBadge: String? {
        guard let sm = activeScheduleEntry?.startMinutes else { return nil }
        return DistractionTracker.shared.badgeText(date: selectedDate, startMin: sm, desc: currentTaskName)
    }

    private var dayTotalsBanner: (count: Int, durStr: String)? {
        let totals = DistractionTracker.shared.dayTotals(date: selectedDate)
        guard totals.count > 0 else { return nil }
        let totalMin = Int(totals.seconds / 60)
        let durStr: String
        if totalMin <= 0 { durStr = "" }
        else if totalMin < 60 { durStr = " · \(totalMin)m away" }
        else {
            let h = totalMin / 60, m = totalMin % 60
            durStr = m > 0 ? " · \(h)h \(m)m away" : " · \(h)h away"
        }
        return (totals.count, durStr)
    }

    private var pauseCountUpFormatted: String {
        guard let p = pausedAt else { return "0:00" }
        let elapsed = max(0, Int(currentTime.timeIntervalSince(p)))
        let m = elapsed / 60
        let s = elapsed % 60
        return String(format: "%d:%02d", m, s)
    }

    private var nowMinutes: Int {
        let c = Calendar.current
        return c.component(.hour, from: currentTime) * 60 + c.component(.minute, from: currentTime)
    }

    private var scheduleEntries: [ScheduleEntry] {
        let lines = notesText.components(separatedBy: .newlines)
        var inside = false
        var result: [ScheduleEntry] = []
        let pattern = #"(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-?\s*(.+)"#
        let regex = try? NSRegularExpression(pattern: pattern)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "START" { inside = true; continue }
            if trimmed == "END"   { inside = false; continue }
            guard inside else { continue }

            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let clean = trimmed
                .replacingOccurrences(of: "~~", with: "")
                .replacingOccurrences(of: #"^\d+\)\s*"#, with: "", options: .regularExpression)

            var startMin: Int? = nil
            var endMin: Int?   = nil
            var task: String?  = nil

            if let r = regex,
               let m = r.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
               let sr = Range(m.range(at: 1), in: clean),
               let er = Range(m.range(at: 2), in: clean),
               let tr = Range(m.range(at: 3), in: clean) {
                startMin = focusModeTimeToMinutes(String(clean[sr]))
                endMin   = focusModeTimeToMinutes(String(clean[er]))
                task     = String(clean[tr]).trimmingCharacters(in: .whitespaces)
            }

            result.append(ScheduleEntry(raw: trimmed, startMinutes: startMin, endMinutes: endMin, task: task, isStruck: isStruck))
        }
        return result
    }

    private func deleteEntry(_ entry: ScheduleEntry) {
        var lines = notesText.components(separatedBy: .newlines)
        lines.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines) == entry.raw }
        notesText = lines.joined(separator: "\n")
        onNotesModified()
    }

    private func clearZeroDurationEntries() {
        let pattern = #"(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-?\s*.+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        var lines = notesText.components(separatedBy: .newlines)
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let m = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let sr = Range(m.range(at: 1), in: trimmed),
                  let er = Range(m.range(at: 2), in: trimmed) else { return false }
            guard let sm = focusModeTimeToMinutes(String(trimmed[sr])),
                  let em = focusModeTimeToMinutes(String(trimmed[er])) else { return false }
            return sm == em
        }
        notesText = lines.joined(separator: "\n")
        onNotesModified()
    }

    private func focusModeTimeToMinutes(_ s: String) -> Int? {
        let clean = s.trimmingCharacters(in: .whitespaces)
        let isPM  = clean.lowercased().contains("pm")
        let isAM  = clean.lowercased().contains("am")
        let timeOnly = clean.replacingOccurrences(of: #"\s*[AaPp][Mm]"#, with: "", options: .regularExpression)
        let parts = timeOnly.components(separatedBy: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        var hour = h
        if isPM && hour != 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        return hour * 60 + m
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.cyan)
                    }
                    Spacer()
                    Text(currentTime, style: .time)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundColor(.cyan)
                    Spacer()
                    HStack(spacing: 16) {
                        // Strike past timeslots
                        Button(action: onStrikePast) {
                            Image(systemName: "text.badge.minus")
                                .font(.title2)
                                .foregroundColor(.yellow)
                        }
                        // Schedule sidebar toggle
                        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showSidebar.toggle() } }) {
                            Image(systemName: showSidebar ? "sidebar.right" : "list.bullet.rectangle")
                                .font(.title2)
                                .foregroundColor(showSidebar ? .indigo : .mint)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Day-total distraction summary
                if let banner = dayTotalsBanner {
                    HStack(spacing: 8) {
                        Text("Today: \(banner.count) distraction\(banner.count == 1 ? "" : "s")\(banner.durStr)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.orange.opacity(0.85))
                        Button(action: { showClearDistractionsConfirm = true }) {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .font(.caption)
                                .foregroundColor(.orange.opacity(0.7))
                        }
                    }
                    .padding(.vertical, 4)
                }

                Spacer()

                // Large timer + smart pause — shown above quotes when a cycle is active
                if settings.isPlaying || settings.isPaused || isWaitingForManualStart {
                    VStack(spacing: 14) {
                        // Task name + serial number
                        HStack(spacing: 8) {
                            if settings.isPlaying || settings.isPaused {
                                let taskNum = currentTaskScheduleNumber ?? (settings.counter + 1)
                                Text("#\(taskNum)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.cyan)
                                    .clipShape(Capsule())
                            }
                            Text(isTransitioning ? "Transitioning..." : currentTaskName.isEmpty ? "Cycle running" : currentTaskName)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.cyan)
                                .tracking(1)
                            if let badge = focusBadge {
                                Text(badge)
                                    .font(.caption2.bold())
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            if totalIdleSeconds > 0 && !isWaitingForManualStart {
                                Text("idle \(formatWaitCountUpFocus(totalIdleSeconds))")
                                    .font(.caption2.bold())
                                    .foregroundColor(.yellow)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.yellow.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }

                        // Time slot
                        if let slot = currentTaskTimeSlot, !isWaitingForManualStart {
                            Text(slot)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.cyan.opacity(0.65))
                        }

                        // Big countdown / waiting state
                        if isWaitingForManualStart {
                            let waitElapsed = max(0, Int(currentTime.timeIntervalSince(manualWaitStartDate ?? currentTime)))
                            VStack(spacing: 6) {
                                Text("Waiting for next task")
                                    .font(.caption)
                                    .foregroundColor(.yellow.opacity(0.8))
                                    .tracking(2)
                                Text(formatWaitCountUpFocus(waitElapsed))
                                    .font(.system(size: 88, weight: .bold, design: .monospaced))
                                    .foregroundColor(.yellow)
                                    .contentTransition(.numericText())
                                Text(pendingNextTaskName)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.yellow.opacity(0.9))
                            }
                        } else {
                            Text(isSmartPaused ? pauseCountUpFormatted : (settings.isPaused ? "Paused" : timeRemainingFormatted))
                                .font(.system(size: 88, weight: .bold, design: .monospaced))
                                .foregroundColor(
                                    isSmartPaused ? .orange :
                                    settings.isPaused ? .orange :
                                    timeRemaining <= 30 ? .red : .white
                                )
                                .contentTransition(.numericText())
                        }

                        // Smart pause / resume + extend row
                        HStack(spacing: 12) {
                            if isWaitingForManualStart {
                                HStack(spacing: 24) {
                                    VStack(spacing: 6) {
                                        Button(action: onStartManualNext) {
                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 52))
                                                .foregroundColor(.yellow)
                                        }
                                        Text("Idle")
                                            .font(.caption)
                                            .foregroundColor(.yellow)
                                    }
                                    VStack(spacing: 6) {
                                        Button(action: onExtendPrevious) {
                                            Image(systemName: "arrowshape.right.circle.fill")
                                                .font(.system(size: 52))
                                                .foregroundColor(.green)
                                        }
                                        Text("Extend")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                                if totalIdleSeconds > 0 {
                                    Text("Idle: \(formatWaitCountUpFocus(totalIdleSeconds))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                                }
                            } else {
                                Button(action: onSmartPause) {
                                    Image(systemName: isSmartPaused ? "play.circle.fill" : "pause.circle.fill")
                                        .font(.title)
                                        .foregroundColor(isSmartPaused ? .green : .orange)
                                }
                                .padding(10)
                                .background(Capsule().fill((isSmartPaused ? Color.green : Color.orange).opacity(0.15)))
                            }

                            if !isWaitingForManualStart && !isTransitioning && !currentTaskName.isEmpty {
                                HStack(spacing: 14) {
                                    // +5 min
                                    Button(action: onExtendTask) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.green)
                                    }
                                    .padding(10)
                                    .background(Capsule().fill(Color.green.opacity(0.15)))

                                    // Interrupt
                                    Button(action: onInterrupt) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.title)
                                            .foregroundColor(.red)
                                    }
                                    .padding(10)
                                    .background(Capsule().fill(Color.red.opacity(0.15)))

                                    // Adjust
                                    Button(action: { showAdjustOptionsFocus = true }) {
                                        Image(systemName: "clock.arrow.2.circlepath")
                                            .font(.title)
                                            .foregroundColor(.purple)
                                    }
                                    .padding(10)
                                    .background(Capsule().fill(Color.purple.opacity(0.15)))

                                    // End & New
                                    Button(action: onEndAndNew) {
                                        Image(systemName: "arrow.trianglehead.turn.up.right.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.orange)
                                    }
                                    .padding(10)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))

                                    // Cancel options
                                    Button(action: { showCancelMenuFocus = true }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.gray)
                                    }
                                    .padding(10)
                                    .background(Capsule().fill(Color.gray.opacity(0.15)))
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }

                // Large quote
                if quotesVisible && quotePool.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "books.vertical")
                            .font(.largeTitle)
                            .foregroundColor(.indigo)
                        Text("Activate a book in the Books library\nto see quotes here")
                            .font(.title3)
                            .foregroundColor(.cyan)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if quotesVisible {
                    let quote = quotePool[currentIndex]
                    VStack(spacing: 24) {
                        Image(systemName: "quote.opening")
                            .font(.title)
                            .foregroundColor(.indigo.opacity(0.6))

                        if showQuote {
                            Text(quote.text)
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    )
                                )
                                .id("fq-\(currentIndex)")

                            VStack(spacing: 4) {
                                Text("— \(quote.author)")
                                    .font(.callout)
                                    .italic()
                                    .foregroundColor(.mint)
                                Text(quote.bookTitle)
                                    .font(.caption)
                                    .foregroundColor(.indigo)
                                if let chNum = quote.chapterNumber {
                                    let label = quote.chapterName.map { "Chapter \(chNum): \($0)" } ?? "Chapter \(chNum)"
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundColor(.teal)
                                }
                            }
                            .transition(.opacity)
                            .id("fa-\(currentIndex)")
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Bottom strip — block duration hint
                if (settings.isPlaying || settings.isPaused) && currentCycleDuration > 0 && !isTransitioning {
                    VStack(spacing: 0) {
                        Divider().background(Color.teal.opacity(0.4))
                        Text("\(currentCycleDuration) min block")
                            .font(.caption2)
                            .foregroundColor(.teal)
                            .padding(.vertical, 10)
                    }
                } else {
                    Color.clear.frame(height: 32)
                }
            }

            // Sidebar overlay
            if showSidebar {
                sidebarPanel
                    .transition(.move(edge: .trailing))
            }
        }
        .onAppear {
            buildQuotePool()
            startCycling()
            clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                currentTime = Date()
            }
        }
        .onDisappear {
            stopCycling()
            clockTimer?.invalidate()
            clockTimer = nil
        }
        .onChange(of: activeBooks.count) { _, _ in
            buildQuotePool()
        }
        .onChange(of: activeBooks.map { $0.id }) { _, _ in
            buildQuotePool()
        }
        .sheet(isPresented: $showSwapSheetFocus) {
            SwapTasksSheet(defaultA: focusSwapDefaults.0, defaultB: focusSwapDefaults.1) { a, b in
                return onSwapTasks(a, b)
            }
        }
        .confirmationDialog("Cancel Current Task", isPresented: $showCancelMenuFocus, titleVisibility: .visible) {
            Button("Stop & Start Next") { onCancelTask() }
            Button("Remove & Adjust Times") { onRemoveCurrentAdjust() }
            Button("Just Remove") { onRemoveCurrentOnly() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Add Adjust (5 min) — start from?", isPresented: $showAdjustOptionsFocus, titleVisibility: .visible) {
            Button("Current Task") { onAdjust(false) }
            Button("Last Completed Task") { onAdjust(true) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Recalculate Distractions", isPresented: $showClearDistractionsConfirm, titleVisibility: .visible) {
            Button("Recalculate from Notes") {
                onRecalculateDistractions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rebuilds distraction counts and time-away from the /N ~Xm values saved in your notes.")
        }
    }

    private var visibleEntries: [ScheduleEntry] {
        guard showActiveOnly else { return scheduleEntries }
        return scheduleEntries.filter { entry in
            guard let em = entry.endMinutes else { return true }
            return em > nowMinutes
        }
    }

    @ViewBuilder
    private var sidebarPanel: some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showSidebar = false } }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Schedule")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        focusSwapDefaults = computeSwapDefaults()
                        showSwapSheetFocus = true
                    }) {
                        Label("Swap", systemImage: "arrow.left.arrow.right")
                            .font(.caption2)
                            .foregroundColor(.indigo)
                    }
                    Button(action: clearZeroDurationEntries) {
                        Label("Clear Zeros", systemImage: "scissors")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showSidebar = false } }) {
                        Image(systemName: "xmark")
                            .font(.callout)
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                .padding(.bottom, 8)

                // Active-only toggle
                HStack {
                    Toggle(isOn: $showActiveOnly) {
                        Text("Active Only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
                    .labelsHidden()
                    Text("Active Only")
                        .font(.caption)
                        .foregroundColor(showActiveOnly ? .cyan : .secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                Divider().background(Color.cyan.opacity(0.3))
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleEntries) { entry in
                            SidebarEntryRow(entry: entry, nowMinutes: nowMinutes, selectedDate: selectedDate, onDelete: deleteEntry)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(width: 240)
            .background(Color(white: 0.08).ignoresSafeArea())
        }
    }

    private func buildQuotePool() {
        var pool: [(text: String, bookTitle: String, author: String, chapterNumber: Int?, chapterName: String?)] = []
        for book in activeBooks {
            for quote in book.quotes ?? [] {
                pool.append((text: quote.text, bookTitle: book.title, author: book.author,
                             chapterNumber: quote.chapterNumber, chapterName: quote.chapterName))
            }
        }
        quotePool = pool.shuffled()
        currentIndex = 0
    }

    private func startCycling() {
        guard cycleTimer == nil else { return }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalSeconds), repeats: true) { _ in
            advanceQuote()
        }
    }

    private func stopCycling() {
        cycleTimer?.invalidate()
        cycleTimer = nil
    }

    private func advanceQuote() {
        guard quotePool.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.4)) { showQuote = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            currentIndex = (currentIndex + 1) % quotePool.count
            withAnimation(.easeInOut(duration: 0.4)) { showQuote = true }
        }
    }

    private func formatSidebarMinutes(_ minutes: Int) -> String {
        let h = (minutes / 60) % 24
        let m = minutes % 60
        let suffix = h >= 12 ? "PM" : "AM"
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", displayH, m, suffix)
    }
}

// MARK: - Sidebar Entry Row (Focus Mode)

private struct SidebarEntryRow: View {
    let entry: ScheduleEntry
    let nowMinutes: Int
    let selectedDate: Date
    let onDelete: (ScheduleEntry) -> Void

    private var sm: Int { entry.startMinutes ?? -1 }
    private var em: Int { entry.endMinutes ?? -1 }
    private var isPast: Bool    { em > 0 && em <= nowMinutes }
    private var isCurrent: Bool { sm >= 0 && em > 0 && nowMinutes >= sm && nowMinutes < em }
    private var isReward: Bool  { entry.task?.contains("[🎁]") == true }
    private var displayTask: String? {
        entry.task?.replacingOccurrences(of: " [🎁]", with: "")
    }
    private var gold: Color { Color(hue: 0.12, saturation: 0.9, brightness: 0.95) }
    private var isFutureReward: Bool { isReward && !entry.isStruck && nowMinutes < sm }

    private var countdownLabel: String? {
        guard isFutureReward, sm > 0 else { return nil }
        let mins = sm - nowMinutes
        let h = mins / 60, m = mins % 60
        return h > 0 ? "in \(h)h \(m)m" : "in \(m)m"
    }

    private func fmt(_ m: Int) -> String {
        let h = (m / 60) % 24, min = m % 60
        let suffix = h >= 12 ? "PM" : "AM"
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", displayH, min, suffix)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isReward && !isPast ? gold : (isCurrent ? Color.green : (isPast || entry.isStruck ? Color.red.opacity(0.5) : Color.indigo)))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                if let task = displayTask {
                    HStack(spacing: 4) {
                        if isReward { Text("🎁").font(.caption) }
                        Text(task)
                            .font(.subheadline)
                            .fontWeight((isCurrent || isReward) ? .semibold : .regular)
                            .foregroundColor(isReward && !isPast ? gold : (isCurrent ? .white : (isPast || entry.isStruck) ? .red.opacity(0.7) : .cyan))
                            .strikethrough(isPast || entry.isStruck, color: .red.opacity(0.7))
                        if sm >= 0 && !entry.isStruck,
                           let badge = DistractionTracker.shared.badgeText(date: selectedDate, startMin: sm, desc: task) {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundColor(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
                HStack(spacing: 6) {
                    if sm >= 0 && em > 0 {
                        Text("\(fmt(sm)) – \(fmt(em))")
                            .font(.caption2)
                            .foregroundColor(isReward && !isPast ? gold.opacity(0.8) : (isCurrent ? .green : (isPast || entry.isStruck) ? .red.opacity(0.5) : .teal))
                    }
                    if isCurrent && isReward {
                        Text("🎁 NOW")
                            .font(.caption2.bold())
                            .foregroundColor(gold)
                    } else if let label = countdownLabel {
                        Text(label)
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundColor(gold)
                    }
                }
            }
            Spacer()
            Button(action: { onDelete(entry) }) {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isReward && !isPast ? gold.opacity(0.06) : (isCurrent ? Color.green.opacity(0.08) : Color.clear))
    }
}

// MARK: - Edit Task Sheet

struct EditTaskSheet: View {
    let task: DailyNotesView.EditTaskItem
    /// Called with (desc, newStart, newEnd). Use `updateTaskAndShiftInNotes` at the call site.
    let onSave: (String, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var desc: String
    @State private var startText: String
    @State private var endText: String
    @State private var endMinutes: Int
    @State private var errorMessage: String = ""

    init(task: DailyNotesView.EditTaskItem, onSave: @escaping (String, Int, Int) -> Void) {
        self.task = task
        self.onSave = onSave
        _desc = State(initialValue: task.originalDesc)
        _startText = State(initialValue: minutesToTimeString(task.originalStart))
        _endText = State(initialValue: minutesToTimeString(task.originalEnd))
        _endMinutes = State(initialValue: task.originalEnd)
    }

    private var currentDurationMinutes: Int {
        let startMins = parseTimeString(startText) ?? task.originalStart
        return max(0, endMinutes - startMins)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Task Name") {
                    TextField("Name", text: $desc)
                }
                Section("Time") {
                    HStack {
                        Text("Start")
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .leading)
                        TextField("e.g. 2:30 PM", text: $startText)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Text("End")
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .leading)
                        TextField("e.g. 3:00 PM", text: $endText)
                            .autocorrectionDisabled()
                            .onChange(of: endText) { _, newVal in
                                if let parsed = parseTimeString(newVal) {
                                    endMinutes = parsed
                                }
                            }
                    }
                    // ±5 quick-adjust row
                    HStack {
                        Text("Duration")
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(formatDuration(currentDurationMinutes))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            adjustEnd(by: -5)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.indigo)
                                .font(.title3)
                        }
                        .buttonStyle(PlainButtonStyle())
                        Text("5 min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .center)
                        Button {
                            adjustEnd(by: +5)
                        } label: {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.indigo)
                                .font(.title3)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { trySave() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func adjustEnd(by delta: Int) {
        let startMins = parseTimeString(startText) ?? task.originalStart
        let newEnd = max(startMins + 1, endMinutes + delta)
        endMinutes = newEnd
        endText = minutesToTimeString(newEnd)
        errorMessage = ""
    }

    private func formatDuration(_ mins: Int) -> String {
        if mins == 0 { return "—" }
        let h = mins / 60
        let m = mins % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func trySave() {
        guard !desc.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Name cannot be empty."
            return
        }
        guard let s = parseTimeString(startText) else {
            errorMessage = "Could not parse start time. Use format like \"2:30 PM\"."
            return
        }
        let e = endMinutes
        guard e > s else {
            errorMessage = "End time must be after start time."
            return
        }
        onSave(desc.trimmingCharacters(in: .whitespaces), s, e)
        dismiss()
    }

    private func parseTimeString(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        let isAM = s.hasSuffix("AM")
        let isPM = s.hasSuffix("PM")
        let digits = s
            .replacingOccurrences(of: "AM", with: "")
            .replacingOccurrences(of: "PM", with: "")
            .trimmingCharacters(in: .whitespaces)
        let parts = digits.components(separatedBy: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 1 else { return nil }
        var h = parts[0]
        let m = parts.count >= 2 ? parts[1] : 0
        guard m >= 0 && m < 60 else { return nil }
        if isPM && h != 12 { h += 12 }
        if isAM && h == 12 { h = 0 }
        guard h >= 0 && h < 24 else { return nil }
        return h * 60 + m
    }
}

// MARK: - Intercept Sheet

struct InterceptSheet: View {
    /// Called with the parsed task lines and the task number to insert after.
    let onApply: ([String], Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tasksText: String = ""
    @State private var afterNumText: String = ""
    @State private var errorMessage: String = ""
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Enter one task per line in the format:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("1:30 PM - 2:00 PM - study\n2:00 PM - 2:30 PM - groceries")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.indigo)
                        .padding(.vertical, 2)
                    Text("Leading numbers like \"1)\" are stripped automatically.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Tasks to Insert")
                }

                Section {
                    TextEditor(text: $tasksText)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 160)
                        .focused($textFocused)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }

                Section("Insert After Task #") {
                    TextField("e.g. 4", text: $afterNumText)
                        .keyboardType(.numberPad)
                    Text("Tasks will be inserted after this task number and the whole list will be renumbered. Leave empty to auto-insert after the nearest time interval.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Intercept Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { tryApply() }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { textFocused = false }.fontWeight(.semibold)
                }
            }
        }
    }

    private func tryApply() {
        let lines = tasksText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            errorMessage = "Enter at least one task."
            return
        }

        let afterNum = Int(afterNumText.trimmingCharacters(in: .whitespaces)) ?? 0
        onApply(lines, afterNum)
        dismiss()
    }
}

// MARK: - Swap Tasks Sheet

struct SwapTasksSheet: View {
    var defaultA: Int? = nil
    var defaultB: Int? = nil
    /// Called with the two task numbers. Returns true if the swap succeeded.
    let onSwap: (Int, Int) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var numAText = ""
    @State private var numBText = ""
    @State private var errorMessage = ""

    private var hasDefaults: Bool { defaultA != nil && defaultB != nil }

    var body: some View {
        NavigationView {
            Form {
                Section("Task Numbers to Swap") {
                    HStack {
                        Text("First")
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)
                        TextField(hasDefaults ? "default: \(defaultA!)" : "e.g. 1", text: $numAText)
                            .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("Second")
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)
                        TextField(hasDefaults ? "default: \(defaultB!)" : "e.g. 3", text: $numBText)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    if hasDefaults && numAText.trimmingCharacters(in: .whitespaces).isEmpty && numBText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Leave both fields empty to swap task \(defaultA!) with task \(defaultB!) (current → next).")
                            .font(.caption)
                            .foregroundColor(.indigo)
                    }
                    Text("The two tasks will be swapped and all times in between will be adjusted to fit the new order.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Swap Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Swap") { trySwap() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func trySwap() {
        let aText = numAText.trimmingCharacters(in: .whitespaces)
        let bText = numBText.trimmingCharacters(in: .whitespaces)

        // Use defaults when both fields are empty
        if aText.isEmpty && bText.isEmpty, let da = defaultA, let db = defaultB {
            if onSwap(da, db) {
                dismiss()
            } else {
                errorMessage = "Tasks \(da) and \(db) not found. Make sure tasks are numbered (e.g. \"1) 2:00 PM - ...\")."
            }
            return
        }

        guard let a = Int(aText), let b = Int(bText) else {
            errorMessage = "Enter valid task numbers."
            return
        }
        guard a != b else {
            errorMessage = "Choose two different task numbers."
            return
        }
        if onSwap(a, b) {
            dismiss()
        } else {
            errorMessage = "Tasks \(a) and \(b) not found. Make sure tasks are numbered (e.g. \"1) 2:00 PM - ...\")."
        }
    }
}

// MARK: - Auto-Schedule Sheet

struct AutoScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedDate: Date
    let allTasks: [Task]
    @Binding var duration: String
    var onGenerate: ([Task], Int, String) -> Void

    @FocusState private var focusedField: Field?
    @State private var startTime: String = Self.currentTimeString()
    /// Ordered list of selected task IDs — position = selection order.
    @State private var selectedIDs: [PersistentIdentifier] = []

    private enum Field { case startTime, duration }

    private var unattendedTasks: [Task] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        return allTasks.filter { t in
            guard let d = t.date else { return false }
            return d >= start && d < end && !t.completed && !t.notCompleted
        }
    }

    private var selectedTasks: [Task] {
        selectedIDs.compactMap { id in unattendedTasks.first { $0.id == id } }
    }

    private var parsedDuration: Int { max(1, Int(duration.trimmingCharacters(in: .whitespaces)) ?? 10) }

    var body: some View {
        NavigationView {
            Form {
                let dayTotals = DistractionTracker.shared.dayTotals(date: selectedDate)
                if dayTotals.count > 0 {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total distractions today: \(dayTotals.count)")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                let totalMin = Int(dayTotals.seconds / 60)
                                if totalMin > 0 {
                                    let durStr: String = {
                                        if totalMin < 60 { return "\(totalMin) min away" }
                                        let h = totalMin / 60, m = totalMin % 60
                                        return m > 0 ? "\(h)h \(m)m away" : "\(h)h away"
                                    }()
                                    Text("Total time: \(durStr)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    } header: {
                        Text("Distraction Summary")
                    }
                }

                Section("Start Time") {
                    TextField("e.g. 12:30 PM", text: $startTime)
                        .focused($focusedField, equals: .startTime)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }

                Section("Duration per Task") {
                    HStack {
                        TextField("10", text: $duration)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .duration)
                            .frame(width: 60)
                        Text("minutes per task")
                            .foregroundColor(.secondary)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focusedField = nil }.fontWeight(.semibold)
                    }
                }

                Section {
                    if unattendedTasks.isEmpty {
                        Text("No unattended tasks for this date.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(unattendedTasks) { task in
                            let selectionIndex = selectedIDs.firstIndex(of: task.id)
                            let isSelected = selectionIndex != nil
                            Button(action: { toggleTask(task) }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        if let idx = selectionIndex {
                                            Circle()
                                                .fill(Color.orange)
                                                .frame(width: 24, height: 24)
                                            Text("\(idx + 1)")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                        } else {
                                            Circle()
                                                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                                                .frame(width: 24, height: 24)
                                        }
                                    }
                                    Text(task.title)
                                        .font(.subheadline)
                                        .foregroundColor(isSelected ? .primary : .secondary)
                                    Spacer()
                                    if let badge = DistractionTracker.shared.badgeTextByTitle(date: selectedDate, title: task.title) {
                                        Text(badge)
                                            .font(.caption2.bold())
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.15), in: Capsule())
                                    }
                                    if isSelected {
                                        Text("\(parsedDuration) min")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                } header: {
                    HStack {
                        Text("Tasks to Schedule (\(selectedIDs.count)/\(unattendedTasks.count))")
                        Spacer()
                        if !unattendedTasks.isEmpty {
                            if selectedIDs.count == unattendedTasks.count {
                                Button("Deselect All") { selectedIDs.removeAll() }
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Button("Select All") { selectAll() }
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }

                if !selectedIDs.isEmpty {
                    Section("Order Preview") {
                        ForEach(Array(selectedTasks.enumerated()), id: \.offset) { idx, task in
                            HStack(spacing: 8) {
                                Text("\(idx + 1).")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .frame(width: 20, alignment: .trailing)
                                Text(task.title)
                                    .font(.caption)
                                Spacer()
                                if let badge = DistractionTracker.shared.badgeTextByTitle(date: selectedDate, title: task.title) {
                                    Text(badge)
                                        .font(.caption2.bold())
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                }
                                Text("\(parsedDuration) min")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text("Tasks will be added in the order shown above, starting at \(startTime.trimmingCharacters(in: .whitespaces).isEmpty ? "current time" : startTime.trimmingCharacters(in: .whitespaces)).")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
            .navigationTitle("Auto-Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { selectAll() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Generate") {
                        onGenerate(selectedTasks, parsedDuration, startTime)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func toggleTask(_ task: Task) {
        if let idx = selectedIDs.firstIndex(of: task.id) {
            selectedIDs.remove(at: idx)
        } else {
            selectedIDs.append(task.id)
        }
    }

    private func selectAll() {
        selectedIDs = unattendedTasks.map { $0.id }
    }

    private static func currentTimeString() -> String {
        let cal = Calendar.current
        let now = Date()
        let h24 = cal.component(.hour, from: now)
        let m   = cal.component(.minute, from: now)
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        let ampm = h24 < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h12, m, ampm)
    }
}

private func minutesToTimeString(_ minutes: Int) -> String {
    let h24 = minutes / 60
    let m = minutes % 60
    let h12 = h24 % 12 == 0 ? 12 : h24 % 12
    let ampm = h24 < 12 ? "AM" : "PM"
    return String(format: "%d:%02d %@", h12, m, ampm)
}

// MARK: - AI Scheduler Sheet

struct AISchedulerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedDate: Date
    let allTasks: [Task]
    let startNumber: Int
    let onInsert: (String) -> Void

    @State private var generatedBlock: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var hasGenerated = false

    private var candidateTasks: [Task] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        // Timed tasks for this date + untimed tasks for this date
        return allTasks.filter { t in
            guard !t.completed && !t.notCompleted else { return false }
            guard let d = t.date else { return false }
            return d >= start && d < end
        }
    }

    private var selectedTasks: [Task] {
        candidateTasks.filter { selectedIDs.contains($0.id) }
    }

    private func priorityLabel(_ t: Task) -> String {
        t.five ? "⭐" : t.priority
    }

    private func estimatedMin(_ t: Task) -> Int {
        AISchedulerService.estimatedMinutes(
            startTime: t.startTime, endTime: t.endTime,
            timeSpent: t.timeSpent, elapsedTime: t.elapsedTime)
    }

    var body: some View {
        NavigationView {
            Form {
                // Task selection
                Section {
                    if candidateTasks.isEmpty {
                        Text("No incomplete tasks found for this date.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(candidateTasks) { task in
                            Button(action: {
                                if selectedIDs.contains(task.id) { selectedIDs.remove(task.id) }
                                else { selectedIDs.insert(task.id) }
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedIDs.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedIDs.contains(task.id) ? .purple : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(task.title)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            if task.five {
                                                Text("⭐")
                                                    .font(.caption2)
                                            } else {
                                                Text(task.priority)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        let mins = estimatedMin(task)
                                        let timedLabel = task.startTime.isEmpty ? "untimed" : "timed"
                                        Text("~\(mins) min · \(timedLabel)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                } header: {
                    HStack {
                        Text("Tasks to Schedule (\(selectedIDs.count)/\(candidateTasks.count))")
                        Spacer()
                        if !candidateTasks.isEmpty {
                            Button(selectedIDs.count == candidateTasks.count ? "Deselect All" : "Select All") {
                                if selectedIDs.count == candidateTasks.count {
                                    selectedIDs.removeAll()
                                } else {
                                    selectedIDs = Set(candidateTasks.map { $0.id })
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.purple)
                        }
                    }
                } footer: {
                    Text("AI will split tasks >40 min, add breaks & fun activities, and respect your 11 PM sleep time.")
                        .font(.caption)
                }

                // Generate button
                if !selectedIDs.isEmpty {
                    Section {
                        Button(action: generate) {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                        .tint(.purple)
                                    Text("Generating…")
                                        .foregroundColor(.purple)
                                } else {
                                    Image(systemName: "sparkles")
                                    Text(hasGenerated ? "Regenerate" : "Generate Schedule")
                                }
                                Spacer()
                            }
                        }
                        .disabled(isLoading)
                        .foregroundColor(.purple)
                    }
                }

                // Error
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    } header: { Text("Error") }
                }

                // Preview
                if hasGenerated && !generatedBlock.isEmpty {
                    Section {
                        ScrollView {
                            Text(generatedBlock)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 300)
                    } header: { Text("Preview") }

                    Section {
                        Button(action: {
                            onInsert(generatedBlock)
                            dismiss()
                        }) {
                            HStack {
                                Spacer()
                                Label("Insert into Daily Notes", systemImage: "square.and.pencil")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.purple)
                    }
                }
            }
            .navigationTitle("AI Scheduler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Pre-select all tasks
                selectedIDs = Set(candidateTasks.map { $0.id })
            }
        }
    }

    private func generate() {
        guard !selectedTasks.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        let inputs = selectedTasks.map { t in
            AISchedulerService.TaskInput(
                title: t.title,
                estimatedMinutes: estimatedMin(t),
                priority: priorityLabel(t),
                isTimed: !t.startTime.isEmpty
            )
        }
        let service = AISchedulerService()
        let date = selectedDate
        let num  = startNumber

        _Concurrency.Task {
            do {
                let block = try await service.generateSchedule(
                    tasks: inputs,
                    currentTime: Date(),
                    selectedDate: date,
                    startNumber: num
                )
                await MainActor.run {
                    generatedBlock = block
                    hasGenerated   = true
                    isLoading      = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading    = false
                }
            }
        }
    }
}

// MARK: - Group By View

struct GroupByView: View {
    @Binding var notesText: String
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    struct TaskItem: Identifiable {
        let id = UUID()
        let num: Int?
        let startMinutes: Int
        let endMinutes: Int
        let description: String
        let isCompleted: Bool
        let isNotCompleted: Bool
        let originalLine: String
        var duration: Int { endMinutes - startMinutes }
    }

    struct TaskGroup: Identifiable {
        let id = UUID()
        let name: String
        var tasks: [TaskItem]
        var totalMinutes: Int { tasks.reduce(0) { $0 + $1.duration } }
        var completedMinutes: Int { tasks.filter { $0.isCompleted }.reduce(0) { $0 + $1.duration } }
    }

    private var groups: [TaskGroup] {
        let allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil, eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return [] }

        let pattern = #"(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var items: [TaskItem] = []
        var prevEnd: Int? = nil

        for i in (s + 1)..<e {
            let trimmed = allLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let isCompleted = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let rawContent  = isCompleted ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            let isNotCompleted = rawContent.contains(" [✗]")

            var num: Int? = nil
            if let pIdx = rawContent.firstIndex(of: ")") {
                num = Int(String(rawContent[rawContent.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces))
            }
            let lineNoPre = rawContent.replacingOccurrences(of: #"^\d+\)\s*"#, with: "", options: .regularExpression)

            guard let m = regex.firstMatch(in: lineNoPre, range: NSRange(lineNoPre.startIndex..., in: lineNoPre)),
                  let sr = Range(m.range(at: 1), in: lineNoPre),
                  let er = Range(m.range(at: 2), in: lineNoPre),
                  let tr = Range(m.range(at: 3), in: lineNoPre) else { continue }

            guard let startMin = gbTimeToMinutes(String(lineNoPre[sr]), prev: prevEnd),
                  let rawEnd   = gbTimeToMinutes(String(lineNoPre[er]), prev: startMin) else { continue }
            let endMin = rawEnd < startMin ? rawEnd + 1440 : rawEnd

            var desc = String(lineNoPre[tr]).trimmingCharacters(in: .whitespaces)
            desc = desc.replacingOccurrences(of: " [✗]", with: "")
                       .replacingOccurrences(of: " [🎁]", with: "")
            if let r = desc.range(of: DistractionTracker.metricsSuffixPattern, options: .regularExpression) {
                desc = String(desc[..<r.lowerBound])
            }
            desc = desc.trimmingCharacters(in: .whitespaces)
            guard !desc.isEmpty else { continue }

            items.append(TaskItem(num: num, startMinutes: startMin, endMinutes: endMin,
                                  description: desc, isCompleted: isCompleted,
                                  isNotCompleted: isNotCompleted, originalLine: trimmed))
            prevEnd = endMin
        }

        var seen: [String] = []
        var map: [String: [TaskItem]] = [:]
        for item in items {
            if map[item.description] == nil { seen.append(item.description) }
            map[item.description, default: []].append(item)
        }
        return seen.compactMap { name in map[name].map { TaskGroup(name: name, tasks: $0) } }
    }

    private func gbTimeToMinutes(_ s: String, prev: Int?) -> Int? {
        let clean   = s.trimmingCharacters(in: .whitespaces)
        let isPM    = clean.lowercased().contains("pm")
        let isAM    = clean.lowercased().contains("am")
        let timeOnly = clean.replacingOccurrences(of: #"\s*[AaPp][Mm]"#, with: "", options: .regularExpression)
        let parts   = timeOnly.components(separatedBy: ":")
        guard parts.count == 2, let h = Int(parts[0]), let mn = Int(parts[1]) else { return nil }
        var hour = h
        if isPM && hour != 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        if !isPM && !isAM, let p = prev {
            let raw = hour * 60 + mn
            if raw < p && raw + 720 <= 1440 { hour += 12 }
        }
        return hour * 60 + mn
    }

    private func fmtMin(_ m: Int) -> String {
        guard m > 0 else { return "0m" }
        let h = m / 60, rem = m % 60
        if h == 0 { return "\(rem)m" }
        return rem > 0 ? "\(h)h \(rem)m" : "\(h)h"
    }

    private func fmtTime(_ minutes: Int) -> String {
        let h = (minutes / 60) % 24
        let m = minutes % 60
        let s = h >= 12 ? "PM" : "AM"
        let dh = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", dh, m, s)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    let distrSecs = DistractionTracker.shared.durationByTitle(date: selectedDate, title: group.name)
                    Section {
                        // Group header with progress
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(group.name).font(.headline)
                                Spacer()
                                Text("\(fmtMin(group.completedMinutes)) / \(fmtMin(group.totalMinutes))")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.18)).frame(height: 6)
                                    let pct = group.totalMinutes > 0
                                        ? CGFloat(group.completedMinutes) / CGFloat(group.totalMinutes) : 0
                                    RoundedRectangle(cornerRadius: 3).fill(Color.green)
                                        .frame(width: geo.size.width * min(pct, 1.0), height: 6)
                                }
                            }
                            .frame(height: 6)
                            if distrSecs > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.circle").font(.caption2).foregroundColor(.orange)
                                    Text("Distracted \(fmtSecs(distrSecs))").font(.caption).foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        // Individual tasks — read only
                        ForEach(group.tasks) { task in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(fmtTime(task.startMinutes)) – \(fmtTime(task.endMinutes))")
                                        .font(.caption).foregroundColor(.secondary)
                                    Text(task.description)
                                        .strikethrough(task.isCompleted, color: .green)
                                        .foregroundColor(
                                            task.isCompleted    ? .secondary :
                                            task.isNotCompleted ? .red.opacity(0.75) : .primary)
                                }
                                Spacer()
                                // Status icon
                                if task.isCompleted {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                                } else if task.isNotCompleted {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.caption)
                                }
                                Text(fmtMin(task.duration)).font(.caption).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Group By Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func fmtSecs(_ secs: TimeInterval) -> String {
        let s = Int(secs)
        let m = s / 60, rem = s % 60
        if m == 0 { return "\(rem)s" }
        return rem > 0 ? "\(m)m \(rem)s" : "\(m)m"
    }
}

#Preview {
    DailyNotesView(selectedDate: Date())
        .modelContainer(for: [DailyNote.self], inMemory: true)
}