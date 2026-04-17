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
    @Query private var allTasksQuery: [Task]
    @State private var showInterceptSheet = false
    @State private var showSwapSheet = false
    @State private var swapSheetDefaults: (Int?, Int?) = (nil, nil)
    @State private var scheduleRenderID: UUID = UUID()
    @State private var showDeleteOptions = false
    @State private var pendingDeleteStart: Int = 0
    @State private var pendingDeleteEnd: Int = 0
    @State private var pendingDeleteDesc: String = ""
    @State private var showCancelOptions = false
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
                            
                            if settings.isPlaying || settings.isPaused || isTransitioning || currentCycleDuration > 0 {
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
                    // Template toolbar
                    HStack(spacing: 8) {
                        Button(action: { showTemplates = true }) {
                            Label("Templates", systemImage: "doc.on.doc.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.indigo)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.indigo.opacity(0.1)))
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: { showAutoGenSheet = true }) {
                            Label("Auto-Schedule", systemImage: "wand.and.stars")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                        }
                        .buttonStyle(PlainButtonStyle())

                        if hasSchedule, currentScheduleBlock != nil {
                            Button(action: { showSaveTemplate = true }) {
                                Label("Save as Template", systemImage: "square.and.arrow.down")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
                            }
                            .buttonStyle(PlainButtonStyle())
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
                            Text("(leave empty to append)")
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
                startCountdownTimer()
                
                // Load persistent pause state
                loadPauseState()

                if useCycles {
                    if pausedAt != nil {
                        // Restore smart-paused state: timer off, Smart Resume button active
                        settings.isPlaying = true
                        settings.isPaused = true
                    } else {
                        // Mirror the toggle: full reset then clean start so stale
                        // AlertSettings state (counter, isPlaying, isTransitioning) is cleared
                        stopCycles()
                        startSmartCycles()
                    }
                }
            }
            .onDisappear {
                stopCountdownTimer()
                cycleEndObserver?.cancel()
                speechManager.stopSpeaking()
                reminderTimer?.invalidate()
            }
            .onChange(of: selectedDate) { _, _ in
                loadNotesForDate(selectedDate)
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
                    onGenerate: { tasks, duration in
                        autoGenerateSchedule(tasks: tasks, minutesPerTask: duration)
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
            .fullScreenCover(isPresented: $isFocusMode) {
                FocusModeView(
                    isPresented: $isFocusMode,
                    currentTaskName: currentTaskName,
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
                    onEndAndNew:          { endAndStartNewTask() },
                    onCancelTask:         { cancelCurrentTask() },
                    onRemoveCurrentAdjust: { removeCurrentTaskFromNotes(adjustTime: true) },
                    onRemoveCurrentOnly:   { removeCurrentTaskFromNotes(adjustTime: false) },
                    onSwapTasks:           { a, b in swapScheduleTasks(numA: a, numB: b) },
                    onNotesModified:       { saveNotes() },
                    computeSwapDefaults:   { currentAndNextTaskNums() }
                )
            }
        }
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
            
            HStack(spacing: 16) {
                Button(settings.isPlaying ? "Stop" : "Start") {
                    DispatchQueue.main.async {
                        if self.settings.isPlaying {
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
        // Ensure this runs on the main thread since it updates UI state
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
                guard self.useCycles && !self.isTransitioning && self.pausedAt == nil else { return }
                guard self.currentCycleDuration > 0 else { return }

                let timeRemaining = settings.nextAlertDate.timeIntervalSinceNow
                if timeRemaining <= 1.0 && timeRemaining > -5.0 {
                    self.handleCycleCompletion()
                }
            }
    }
    
    private func stopCycles() {
        // Ensure this runs on the main thread since it updates UI state
        DispatchQueue.main.async {
            self.settings.isPlaying = false
            self.settings.isPaused = false
            self.settings.stopTimer()
            self.currentTaskName = ""
            self.currentCycleDuration = 0
            self.isTransitioning = false
            self.cycleEndObserver?.cancel()
            self.speechManager.stopSpeaking()
            
            // Stop reminder timer
            self.stopReminderTimer()
            
            // Reset pause tracking
            self.pausedAt = nil
            self.totalPausedDuration = 0
            self.savePauseState()
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
        // Prevent multiple simultaneous transitions
        guard !isTransitioning else {
            print("⚠️ Already transitioning, skipping duplicate call")
            return
        }

        // Mark transitioning immediately so the block stays visible
        // even if AlertSettings resets isPlaying during the 2-second gap
        isTransitioning = true

        print("🔔 Cycle completed! Transitioning to next task...")

        // Announce task completion
        let completionAnnouncement = "\(currentTaskName) completed"
        speechManager.speak(completionAnnouncement)

        // Cancel the observer to prevent duplicate triggers
        cycleEndObserver?.cancel()

        // Wait a moment for the announcement, then start next cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.startNextCycle()
        }
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
            notesText = ""
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

    /// Replaces or appends the START…END block in current notes with the template content.
    private func applyTemplates(_ templates: [ScheduleTemplate]) {
        guard !templates.isEmpty else { return }
        // Extract task lines from all templates in order
        var rawLines: [String] = []
        for template in templates {
            var inBlock = false
            for line in template.content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "START" { inBlock = true; continue }
                if trimmed == "END"   { inBlock = false; continue }
                if inBlock { rawLines.append(line) }
            }
        }
        // Renumber sequentially from max existing number + 1
        let startNum = maxScheduleNumber() + 1
        let numberedLines = renumberedLines(rawLines, from: startNum)
        let combinedLines = (["START"] + numberedLines + ["END"])

        var lines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil
        var eIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        if let s = sIdx, let e = eIdx {
            lines.replaceSubrange(s...e, with: combinedLines)
        } else {
            if lines.last?.isEmpty == false { lines.append("") }
            lines.append(contentsOf: combinedLines)
        }
        notesText = lines.joined(separator: "\n")
        editorKey = UUID()
        saveNotes()
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

    /// Generates a schedule block from the given unattended tasks, `minutesPerTask` each,
    /// starting from the current time, numbered from maxScheduleNumber() + 1.
    private func autoGenerateSchedule(tasks: [Task], minutesPerTask: Int) {
        guard !tasks.isEmpty else { return }
        let cal = Calendar.current
        let now = Date()
        let startMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let startNum = maxScheduleNumber() + 1

        var newLines: [String] = []
        for (i, task) in tasks.enumerated() {
            let taskStart = startMin + i * minutesPerTask
            let taskEnd   = taskStart + minutesPerTask
            let startStr  = safeMinutesToTime(taskStart)
            let endStr    = safeMinutesToTime(taskEnd)
            newLines.append("\(startNum + i)) \(startStr) - \(endStr) - \(task.title)")
        }

        // Append inside existing block or create new one
        var lines = notesText.components(separatedBy: .newlines)
        var eIdx: Int? = nil
        var sIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        if let e = eIdx {
            // Insert new lines just before END
            lines.insert(contentsOf: newLines, at: e)
        } else {
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
        let description = String(lineWithoutNumbering[descriptionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        
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
            let newTimeRemaining = max(0, settings.nextAlertDate.timeIntervalSinceNow)
            previousTimeRemaining = timeRemaining
            timeRemaining = newTimeRemaining
        } else if settings.isPlaying && settings.isPaused {
            // When paused, keep the timeRemaining value frozen
            previousTimeRemaining = timeRemaining
        } else {
            // isPlaying and isPaused are both false.
            // If useCycles is on and a cycle was active, AlertSettings dropped isPlaying
            // (line 194 or line 334 in AlertSettings_OrderFixed.swift).
            if useCycles && currentCycleDuration > 0 && !isTransitioning && pausedAt == nil {
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
        } else if let endIdx = endLineIndex {
            // Insert the generated lines just before the END tag
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

    /// Swaps two numbered tasks in the schedule and rebuilds times for the entire range between them.
    /// Inserts `lines` after task number `afterNum` in the START…END block, then renumbers all tasks.
    private func applyIntercept(lines: [String], afterNum: Int) {
        guard !lines.isEmpty else { return }

        var allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil, eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }

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

        if let s = sIdx, let e = eIdx {
            // Find insertion point: line index of task `afterNum` inside the block
            var insertAfterLineIdx: Int? = nil
            var taskCounter = 0
            for i in (s + 1)..<e {
                let t = allLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                // Count any non-empty line as a task slot (numbered or not)
                if let pIdx = t.firstIndex(of: ")"),
                   let n = Int(String(t[t.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)),
                   !t[t.startIndex..<pIdx].contains(" "), n > 0, n < 1000 {
                    if n == afterNum { insertAfterLineIdx = i; break }
                    _ = taskCounter; taskCounter = n
                } else {
                    taskCounter += 1
                    if taskCounter == afterNum { insertAfterLineIdx = i; break }
                }
            }
            // Default: insert before END if not found
            let insertAt = (insertAfterLineIdx ?? (e - 1)) + 1
            allLines.insert(contentsOf: strippedLines, at: insertAt)
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
                // Strip existing number if present
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

    private func parseFormattedTaskItems() -> [(num: Int?, start: Int, end: Int, desc: String, struck: Bool, fixed: Bool)] {
        let allLines = notesText.components(separatedBy: .newlines)
        var sIdx: Int? = nil
        var eIdx: Int? = nil
        for (i, line) in allLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "START" && sIdx == nil { sIdx = i }
            else if t == "END" && sIdx != nil && eIdx == nil { eIdx = i; break }
        }
        guard let s = sIdx, let e = eIdx else { return [] }

        var result: [(num: Int?, start: Int, end: Int, desc: String, struck: Bool, fixed: Bool)] = []
        var prevEnd: Int? = nil

        for line in allLines[(s + 1)..<e] {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed

            // Extract task number from "N) ..." prefix
            var num: Int? = nil
            if let parenIdx = parseLine.firstIndex(of: ")") {
                let prefix = String(parseLine[parseLine.startIndex..<parenIdx])
                num = Int(prefix.trimmingCharacters(in: .whitespaces))
            }

            if let entry = parseTimeEntrySequential(parseLine, previousEndMinutes: prevEnd) {
                result.append((num: num, start: entry.startMinutes, end: entry.endMinutes,
                               desc: entry.description, struck: isStruck, fixed: entry.isFixed))
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
        for i in (s + 1)..<e {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let parseLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed
            if let entry = parseTimeEntrySequential(parseLine, previousEndMinutes: prevEnd) {
                if entry.startMinutes == startMin && entry.endMinutes == endMin && entry.description == desc {
                    lines[i] = isStruck ? parseLine : "~~\(trimmed)~~"
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
        guard let cur = findBestCurrentTask(at: nowMin, in: timeEntries) else { return }

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
                                   nowMin: nowMin,
                                   onToggleStrike: { toggleStrikeTask(startMin: task.start, endMin: task.end, desc: task.desc) },
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
                                struck: Bool, fixed: Bool, nowMin: Int,
                                onToggleStrike: (() -> Void)? = nil,
                                onDelete: (() -> Void)? = nil) -> some View {
        let isCurrent = !struck && nowMin >= startMin && nowMin < endMin
        let isPastUnack = !struck && nowMin >= endMin
        let accentColor: Color = struck ? .green : (isCurrent ? .blue : (isPastUnack ? .orange : .primary))
        let duration = endMin - startMin

        HStack(spacing: 12) {
            // Number/status badge
            ZStack {
                Circle()
                    .fill(accentColor.opacity(struck ? 0.2 : (isCurrent ? 0.18 : 0.1)))
                    .frame(width: 34, height: 34)
                if let n = num {
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
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundColor(struck ? .secondary : .primary)
                        .strikethrough(struck, color: .secondary)
                        .lineLimit(2)
                }
                Text("\(safeMinutesToTime(startMin)) – \(safeMinutesToTime(endMin))")
                    .font(.caption)
                    .foregroundColor(accentColor.opacity(0.85))
                    .monospacedDigit()
            }

            Spacer()

            Text("\(duration)m")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.1), in: Capsule())

            if let onToggleStrike {
                Button(action: onToggleStrike) {
                    Image(systemName: struck ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundColor(struck ? .green : .secondary.opacity(0.5))
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
                .fill(isCurrent ? Color.blue.opacity(0.07) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(isCurrent ? 0.45 : 0.15), lineWidth: 1)
        )
    }

    // MARK: - Interrupt Current Task

    private func insertInterruptTask() {
        let now = Date()
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        let timeEntries = extractTimeEntriesFromNotes()
        guard let currentEntry = findBestCurrentTask(at: nowMin, in: timeEntries) else { return }

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

    // MARK: - End Current Task and Start New

    private func endAndStartNewTask() {
        let now = Date()
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        let timeEntries = extractTimeEntriesFromNotes()
        guard let currentEntry = findBestCurrentTask(at: nowMin, in: timeEntries) else { return }

        let newTaskDuration = 5
        // How much the following tasks need to shift:
        // positive = they move later, negative = they move earlier (we finished early)
        let shiftAmount = (nowMin + newTaskDuration) - currentEntry.endMinutes

        // Timer counts down the new 5-minute task
        settings.nextAlertDate = now.addingTimeInterval(TimeInterval(newTaskDuration * 60))

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

                    var baseNum: Int? = nil
                    if let pIdx = trimmed.firstIndex(of: ")") {
                        baseNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces))
                    }

                    // Truncated original task
                    let part1Num = baseNum.map { "\($0)) " } ?? ""
                    result.append("\(part1Num)\(safeMinutesToTime(entry.startMinutes)) - \(safeMinutesToTime(nowMin)) - \(entry.description)")

                    // New 5-minute task
                    let part2Num = baseNum.map { "\($0 + 1)) " } ?? ""
                    result.append("\(part2Num)\(safeMinutesToTime(nowMin)) - \(safeMinutesToTime(nowMin + newTaskDuration)) - new task")

                    prevEnd = nowMin + newTaskDuration

                } else if foundCurrent && entry.startMinutes >= currentEntry.endMinutes && !entry.isFixed {
                    // Shift by shiftAmount and bump number by +1
                    var shiftedNum: Int? = nil
                    if let pIdx = trimmed.firstIndex(of: ")") {
                        shiftedNum = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)).map { $0 + 1 }
                    }
                    let numStr   = shiftedNum.map { "\($0)) " } ?? ""
                    let newStart = safeMinutesToTime(max(0, entry.startMinutes + shiftAmount))
                    let newEnd   = safeMinutesToTime(max(0, entry.endMinutes   + shiftAmount))
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
                    // Truncate current task's end time to now
                    let numStr: String
                    if let pIdx = trimmed.firstIndex(of: ")"),
                       let num = Int(String(trimmed[trimmed.startIndex..<pIdx]).trimmingCharacters(in: .whitespaces)) {
                        numStr = "\(num)) "
                    } else {
                        numStr = ""
                    }
                    let newEnd = safeMinutesToTime(nowMin)
                    result.append("\(numStr)\(safeMinutesToTime(entry.startMinutes)) - \(newEnd) - \(entry.description)")
                    prevEnd = nowMin

                } else if foundCurrent && entry.startMinutes >= currentEntry.endMinutes && !entry.isFixed {
                    // Shift following tasks earlier
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

        // Find the line for task #taskNum
        var insertAfterLine: Int = eIdx  // default: before END
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

        let newCount = scheduleLines.count
        // Renumber generated lines to start from taskNum+1
        let renumbered: [String] = scheduleLines.enumerated().map { (i, line) in
            line.replacingOccurrences(of: #"^\d+\)\s*"#, with: "\(taskNum + 1 + i)) ", options: .regularExpression)
        }

        // Insert generated lines after the found position
        allLines.insert(contentsOf: renumbered, at: insertAfterLine + 1)

        // Renumber and shift lines that came after the insertion point
        let shiftFrom = insertAfterLine + 1 + newCount
        let newEndIdx = eIdx + newCount

        for lineIdx in shiftFrom..<newEndIdx {
            let line = allLines[lineIdx]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let isStruck = trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~")
            let workLine = isStruck ? String(trimmed.dropFirst(2).dropLast(2)) : trimmed

            // Extract old number prefix
            if let numRange = workLine.range(of: #"^\d+\)"#, options: .regularExpression) {
                let numStr = String(workLine[numRange].dropLast())  // drop ")"
                if let oldNum = Int(numStr) {
                    let newNum = oldNum + newCount
                    var updated = workLine.replacingOccurrences(
                        of: #"^\d+\)\s*"#, with: "\(newNum)) ", options: .regularExpression)
                    // Shift times if it's a time entry and not fixed
                    if let entry = parseTimeEntry(updated), !entry.isFixed {
                        let newStart = formatMinutesToTime(entry.startMinutes + shiftMinutes)
                        let newEnd = formatMinutesToTime(entry.endMinutes + shiftMinutes)
                        updated = "\(newNum)) \(newStart) - \(newEnd) - \(entry.description)"
                    }
                    allLines[lineIdx] = isStruck ? "~~\(updated)~~" : updated
                }
            } else if let entry = parseTimeEntry(workLine), !entry.isFixed {
                let newStart = formatMinutesToTime(entry.startMinutes + shiftMinutes)
                let newEnd = formatMinutesToTime(entry.endMinutes + shiftMinutes)
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
    let onEndAndNew: () -> Void
    let onCancelTask: () -> Void
    let onRemoveCurrentAdjust: () -> Void
    let onRemoveCurrentOnly: () -> Void
    let onSwapTasks: (Int, Int) -> Bool
    let onNotesModified: () -> Void
    let computeSwapDefaults: () -> (Int?, Int?)

    @Query(filter: #Predicate<Book> { $0.isActive }) private var activeBooks: [Book]
    @AppStorage("display.quotesInterval") private var intervalSeconds: Int = 10

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

    private var timeRemainingFormatted: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
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

                Spacer()

                // Large timer + smart pause — shown above quotes when a cycle is active
                if settings.isPlaying || settings.isPaused {
                    VStack(spacing: 14) {
                        // Task name + serial number
                        HStack(spacing: 8) {
                            if settings.isPlaying || settings.isPaused {
                                Text("#\(settings.counter + 1)")
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
                        }

                        // Big countdown (count-up when smart paused)
                        Text(isSmartPaused ? pauseCountUpFormatted : (settings.isPaused ? "Paused" : timeRemainingFormatted))
                            .font(.system(size: 88, weight: .bold, design: .monospaced))
                            .foregroundColor(
                                isSmartPaused ? .orange :
                                settings.isPaused ? .orange :
                                timeRemaining <= 30 ? .red : .white
                            )
                            .contentTransition(.numericText())

                        // Smart pause / resume + extend row
                        HStack(spacing: 12) {
                            Button(action: onSmartPause) {
                                HStack(spacing: 8) {
                                    Image(systemName: isSmartPaused ? "play.circle.fill" : "pause.circle.fill")
                                        .font(.title2)
                                    Text(isSmartPaused ? "Smart Resume" : "Smart Pause")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(isSmartPaused ? .green : .orange)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill((isSmartPaused ? Color.green : Color.orange).opacity(0.15))
                                )
                            }

                            if !isTransitioning && !currentTaskName.isEmpty {
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
                if quotePool.isEmpty {
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
                } else {
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
                .padding(.bottom, 12)
                Divider().background(Color.cyan.opacity(0.3))
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(scheduleEntries) { entry in
                            SidebarEntryRow(entry: entry, nowMinutes: nowMinutes, onDelete: deleteEntry)
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
    let onDelete: (ScheduleEntry) -> Void

    private var sm: Int { entry.startMinutes ?? -1 }
    private var em: Int { entry.endMinutes ?? -1 }
    private var isPast: Bool    { em > 0 && em <= nowMinutes }
    private var isCurrent: Bool { sm >= 0 && em > 0 && nowMinutes >= sm && nowMinutes < em }

    private func fmt(_ m: Int) -> String {
        let h = (m / 60) % 24, min = m % 60
        let suffix = h >= 12 ? "PM" : "AM"
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", displayH, min, suffix)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isCurrent ? Color.green : (isPast || entry.isStruck ? Color.red.opacity(0.5) : Color.indigo))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                if let task = entry.task {
                    Text(task)
                        .font(.subheadline)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundColor(isCurrent ? .white : (isPast || entry.isStruck) ? .red.opacity(0.7) : .cyan)
                        .strikethrough(isPast || entry.isStruck, color: .red.opacity(0.7))
                }
                if sm >= 0 && em > 0 {
                    Text("\(fmt(sm)) – \(fmt(em))")
                        .font(.caption2)
                        .foregroundColor(isCurrent ? .green : (isPast || entry.isStruck) ? .red.opacity(0.5) : .teal)
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
        .background(isCurrent ? Color.green.opacity(0.08) : Color.clear)
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
                    Text("Tasks will be inserted after this task number and the whole list will be renumbered. Leave empty to append at the end.")
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
    var onGenerate: ([Task], Int) -> Void

    @FocusState private var durationFocused: Bool
    /// Ordered list of selected task IDs — position = selection order.
    @State private var selectedIDs: [PersistentIdentifier] = []

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
                Section("Duration per Task") {
                    HStack {
                        TextField("10", text: $duration)
                            .keyboardType(.numberPad)
                            .focused($durationFocused)
                            .frame(width: 60)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") { durationFocused = false }.fontWeight(.semibold)
                                }
                            }
                        Text("minutes per task")
                            .foregroundColor(.secondary)
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
                                Text("\(parsedDuration) min")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text("Tasks will be added in the order shown above, starting at current time.")
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
                        onGenerate(selectedTasks, parsedDuration)
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
}

private func minutesToTimeString(_ minutes: Int) -> String {
    let h24 = minutes / 60
    let m = minutes % 60
    let h12 = h24 % 12 == 0 ? 12 : h24 % 12
    let ampm = h24 < 12 ? "AM" : "PM"
    return String(format: "%d:%02d %@", h12, m, ampm)
}

#Preview {
    DailyNotesView(selectedDate: Date())
        .modelContainer(for: [DailyNote.self], inMemory: true)
}