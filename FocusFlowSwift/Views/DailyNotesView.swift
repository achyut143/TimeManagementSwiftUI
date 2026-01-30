import SwiftUI
import SwiftData
import AVFoundation
import ActivityKit
import Combine

// MARK: - Speech Synthesizer Manager
class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func speak(_ text: String) {
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
        
        // Use safer string construction (24-hour format for TimeEntry)
        return "\(hours):\(String(format: "%02d", mins))"
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
                            TextField("+30 or -15", text: $adjustmentMinutes)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 100)
                            Button("Apply") {
                                adjustTimesInNotes()
                            }
                            .disabled(adjustmentMinutes.isEmpty)
                        }
                        
                        // Quick adjustment buttons
                        HStack(spacing: 8) {
                            Text("Quick:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("-30") {
                                adjustmentMinutes = "-30"
                                adjustTimesInNotes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("-15") {
                                adjustmentMinutes = "-15"
                                adjustTimesInNotes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("+15") {
                                adjustmentMinutes = "15"
                                adjustTimesInNotes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("+30") {
                                adjustmentMinutes = "30"
                                adjustTimesInNotes()
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
                            Text("Automatically detects your schedule from START/END sections and starts appropriate cycles based on current time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            
                            if settings.isPlaying || settings.isPaused {
                                cycleStatusView
                            }
                        }
                    }
                }
                
                Section("Daily Notes") {
                    RichTextEditor(text: $notesText)
                        .frame(height: 300)
                        .id(editorKey)
                }
                
                Section("Schedule Generator") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("From:")
                                .frame(width: 60, alignment: .leading)
                            TextField("12:30", text: $scheduleFrom)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numbersAndPunctuation)
                        }
                        
                        HStack {
                            Text("To:")
                                .frame(width: 60, alignment: .leading)
                            TextField("5:30", text: $scheduleTo)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numbersAndPunctuation)
                        }
                        
                        HStack {
                            Text("Interval:")
                                .frame(width: 60, alignment: .leading)
                            TextField("30", text: $scheduleInterval)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                            Text("min")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Gap:")
                                .frame(width: 60, alignment: .leading)
                            TextField("5", text: $scheduleGap)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                            Text("min")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Task:")
                                .frame(width: 60, alignment: .leading)
                            TextField("work", text: $scheduleTaskName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        Button("Generate Schedule") {
                            generateSchedule()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(scheduleFrom.isEmpty || scheduleTo.isEmpty || 
                                 scheduleInterval.isEmpty || scheduleGap.isEmpty || 
                                 scheduleTaskName.isEmpty)
                        
                        Text("Generates time blocks with specified intervals and gaps between them")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
            }
            .onAppear {
                loadNotesForDate(selectedDate)
                startCountdownTimer()
                
                // Load persistent pause state
                loadPauseState()
                
                // If cycles were previously enabled, restart them
                if useCycles {
                    startSmartCycles()
                }
            }
            .onDisappear {
                stopCountdownTimer()
                cycleEndObserver?.cancel()
                speechManager.stopSpeaking()
            }
            .onChange(of: selectedDate) { _, _ in
                loadNotesForDate(selectedDate)
            }
            .onChange(of: notesText) { _, _ in
                // If cycles are enabled, update them when notes change
                DispatchQueue.main.async {
                    if self.useCycles {
                        self.startSmartCycles()
                    }
                }
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
            
            // Smart Pause button (separate from regular pause)
            if settings.isPlaying {
                Button(pausedAt != nil ? "Smart Resume" : "Smart Pause") {
                    DispatchQueue.main.async {
                        self.handleSmartPause()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(pausedAt != nil ? .green : .orange)
                .frame(maxWidth: .infinity)
            }
            
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
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
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
                let remainingMinutes = currentEntry.endMinutes - currentMinutes
                self.currentCycleDuration = remainingMinutes
                
                // Start cycle for remaining time
                self.startCycleWithDuration(remainingMinutes, taskName: currentEntry.description)
                
            } else if let nextEntry = self.findNextTask(after: currentMinutes, in: timeEntries) {
                // In a gap before next task - start preparation/rest/Drink Water cycle
                let gapMinutes = nextEntry.startMinutes - currentMinutes
                self.currentTaskName = "Preparation/Rest/Drink Water"
                self.currentCycleDuration = gapMinutes
                
                // Start preparation cycle
                self.startCycleWithDuration(gapMinutes, taskName: "Preparation/Rest/Drink Water")
                
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
            currentMinutes >= entry.startMinutes && currentMinutes < entry.endMinutes
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
        
        print("🎯 Started cycle: \(taskName) for \(minutes) minutes")
    }
    
    private func setupCycleEndObserver() {
        // Cancel any existing observer
        cycleEndObserver?.cancel()
        
        // Create a timer that checks more frequently for cycle completion
        cycleEndObserver = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak settings] _ in
                guard let settings = settings else { return }
                
                // Check if cycle just completed
                if settings.isPlaying && !settings.isPaused {
                    let timeRemaining = settings.nextAlertDate.timeIntervalSinceNow
                    
                    // If time is up or very close (within 1 second)
                    if timeRemaining <= 1.0 && timeRemaining > -2.0 {
                        // Trigger transition
                        DispatchQueue.main.async {
                            self.handleCycleCompletion()
                        }
                    }
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
            
            // Reset pause tracking
            self.pausedAt = nil
            self.totalPausedDuration = 0
            self.savePauseState()
        }
    }
    
    // MARK: - Smart Pause/Resume Logic
    
    private func handleSmartPause() {
        if pausedAt != nil {
            // Resume - calculate pause duration and adjust schedule
            resumeWithScheduleAdjustment()
        } else {
            // Pause - record the pause time AND pause the timer
            pausedAt = Date()
            savePauseState()
            
            // Pause the timer (but keep isPlaying true)
            settings.isPaused = true
            
            let announcement = "Smart pause activated. Schedule will adjust on resume."
            speechManager.speak(announcement)
            
            print("⏸️ Smart Paused at \(currentTimeString)")
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
        
        for line in lines {
            // Skip strikethrough lines completely
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("~~") && trimmedLine.hasSuffix("~~") {
                result.append(line)
                continue
            }
            if trimmedLine.contains("~~") {
                result.append(line)
                continue
            }
            
            if let entry = parseTimeEntry(line) {
                // Check if this is a fixed task (marked with **text**)
                if entry.isFixed {
                    // Fixed tasks remain unchanged
                    result.append(line)
                    print("📝 Kept fixed task: \(entry.description) at \(safeMinutesToTime(entry.startMinutes))-\(safeMinutesToTime(entry.endMinutes))")
                    continue
                }
                
                // Check if this was the current task when we PAUSED (not when we resume)
                let wasCurrentTask = pauseMinutes >= entry.startMinutes && pauseMinutes < entry.endMinutes
                
                if wasCurrentTask {
                    // Current task: shift by pause duration, keep FULL original duration
                    let taskDuration = entry.duration  // Keep full original duration (15 minutes)
                    
                    // New start time should be: original start time + pause duration
                    let newStartMinutes = entry.startMinutes + minutes  // Shift by pause duration
                    let newEndMinutes = newStartMinutes + taskDuration  // Full duration
                    
                    let adjustedEntry = TimeEntry(
                        startMinutes: newStartMinutes,
                        endMinutes: newEndMinutes,
                        description: entry.description,
                        isFixed: entry.isFixed,
                        originalLine: entry.originalLine
                    )
                    
                    result.append(adjustedEntry.toLine())
                    print("📝 Adjusted current task: \(entry.description) from \(safeMinutesToTime(entry.startMinutes))-\(safeMinutesToTime(entry.endMinutes)) to \(safeMinutesToTime(newStartMinutes))-\(safeMinutesToTime(newEndMinutes)) (full \(taskDuration) min preserved)")
                    
                } else if entry.startMinutes > pauseMinutes {
                    // Future task (starts after pause time): shift by pause duration
                    let adjustedStartMinutes = entry.startMinutes + minutes
                    let adjustedEndMinutes = entry.endMinutes + minutes
                    
                    let adjustedEntry = TimeEntry(
                        startMinutes: adjustedStartMinutes,
                        endMinutes: adjustedEndMinutes,
                        description: entry.description,
                        isFixed: entry.isFixed,
                        originalLine: entry.originalLine
                    )
                    
                    result.append(adjustedEntry.toLine())
                    print("📝 Adjusted future task: \(entry.description) from \(safeMinutesToTime(entry.startMinutes))-\(safeMinutesToTime(entry.endMinutes)) to \(safeMinutesToTime(adjustedStartMinutes))-\(safeMinutesToTime(adjustedEndMinutes))")
                    
                } else {
                    // Past task (ended before pause time) - keep as is
                    result.append(line)
                    print("📝 Kept past task: \(entry.description) at \(safeMinutesToTime(entry.startMinutes))-\(safeMinutesToTime(entry.endMinutes))")
                }
            } else {
                // Non-time line - keep as is (empty lines, comments, etc.)
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
        
        print("📝 Parsing schedule from notes (lines \(startIndex + 1) to \(endIndex - 1)):")
        print("📝 Content to parse: \(contentLines.count) lines")
        
        for (lineIndex, line) in contentLines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            if trimmedLine.isEmpty {
                continue
            }
            
            if let entry = parseTimeEntry(line) {
                timeEntries.append(entry)
                // Add safety checks to prevent EXC_BAD_ACCESS
                let startTimeStr = safeMinutesToTime(entry.startMinutes)
                let endTimeStr = safeMinutesToTime(entry.endMinutes)
                let description = entry.description.isEmpty ? "No description" : entry.description
                print("✅ Parsed line \(lineIndex + 1): \(startTimeStr) - \(endTimeStr) - \(description)")
            } else {
                print("⚠️ Could not parse line \(lineIndex + 1): '\(trimmedLine)'")
            }
        }
        
        let sortedEntries = timeEntries.sorted { $0.startMinutes < $1.startMinutes }
        print("📅 Final schedule (\(sortedEntries.count) entries):")
        for entry in sortedEntries {
            let startTimeStr = safeMinutesToTime(entry.startMinutes)
            let endTimeStr = safeMinutesToTime(entry.endMinutes)
            let description = entry.description.isEmpty ? "No description" : entry.description
            print("   \(startTimeStr) - \(endTimeStr) - \(description)")
        }
        
        return sortedEntries
    }
    
    // MARK: - Existing Methods (unchanged)
    
    private func loadNotesForDate(_ date: Date) {
        if let existingNote = getNoteForDate(date) {
            notesText = existingNote.content
        } else {
            notesText = ""
        }
        editorKey = UUID()
    }
    
    private func saveNotes() {
        if let existingNote = getNoteForDate(selectedDate) {
            existingNote.updateContent(notesText)
        } else if !notesText.isEmpty {
            let newNote = DailyNote(date: selectedDate, content: notesText)
            modelContext.insert(newNote)
        }
        
        try? modelContext.save()
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
    
    private func parseTimeEntry(_ line: String) -> TimeEntry? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip strikethrough lines - check the entire line, not just if it contains ~~
        if trimmedLine.hasPrefix("~~") && trimmedLine.hasSuffix("~~") {
            return nil
        }
        
        // Also skip if the line contains ~~ anywhere (partial strikethrough)
        if trimmedLine.contains("~~") {
            return nil
        }
        
        // Pattern to match time ranges - support both 12-hour and 24-hour formats
        let pattern = #"(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*-?\s*(.+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: trimmedLine, range: NSRange(location: 0, length: trimmedLine.utf16.count)),
              let startTimeRange = Range(match.range(at: 1), in: trimmedLine),
              let endTimeRange = Range(match.range(at: 2), in: trimmedLine),
              let descriptionRange = Range(match.range(at: 3), in: trimmedLine) else {
            return nil
        }
        
        let startTimeStr = String(trimmedLine[startTimeRange])
        let endTimeStr = String(trimmedLine[endTimeRange])
        let description = String(trimmedLine[descriptionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse both times with context awareness
        guard let startMinutes = timeToMinutesWithContext(startTimeStr, endTimeStr: endTimeStr, startTimeStr: startTimeStr),
              let endMinutes = timeToMinutesWithContext(endTimeStr, endTimeStr: endTimeStr, startTimeStr: startTimeStr) else {
            return nil
        }
        
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
            let now = Date()
            let calendar = Calendar.current
            let currentHour = calendar.component(.hour, from: now)
            let isCurrentlyPM = currentHour >= 12
            
            // Check if we're dealing with a time range that crosses noon
            var isSpecialNoonCrossing = false
            if let startTime = startTimeStr, let endTime = endTimeStr {
                let startComponents = startTime.replacingOccurrences(of: "\\s*[AaPp][Mm]", with: "", options: .regularExpression).components(separatedBy: ":")
                let endComponents = endTime.replacingOccurrences(of: "\\s*[AaPp][Mm]", with: "", options: .regularExpression).components(separatedBy: ":")
                
                if let startHour = Int(startComponents[0]), let endHour = Int(endComponents[0]) {
                    // Special case: 11:XX - 12:XX when current time is PM
                    isSpecialNoonCrossing = (startHour == 11 && endHour == 12 && isCurrentlyPM)
                }
            }
            
            if isSpecialNoonCrossing {
                // Handle the edge case: 11:30 - 12:30 when current time is PM
                if hours == 11 {
                    finalHours = 11 // Keep 11:XX as 11 AM
                } else if hours == 12 {
                    finalHours = 12 // Keep 12:XX as 12 PM (noon)
                } else {
                    // For other hours in this context, follow current time
                    if isCurrentlyPM && hours < 12 {
                        finalHours = hours + 12
                    } else if hours == 12 && !isCurrentlyPM {
                        finalHours = 0
                    }
                }
            } else {
                // Normal context-based interpretation
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
            // When paused, keep the timeRemaining value frozen (don't update it)
            // This preserves the time that was remaining when we paused
            previousTimeRemaining = timeRemaining
            // Don't change timeRemaining - keep it at the paused value
        } else {
            // When stopped completely
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
        
        guard let intervalMinutes = Int(scheduleInterval),
              let gapMinutes = Int(scheduleGap),
              let fromMinutes = parseTimeToMinutes(scheduleFrom),
              var toMinutes = parseTimeToMinutes(scheduleTo) else {
            print("❌ Invalid input values")
            print("   Interval parse: \(Int(scheduleInterval) != nil ? "✓" : "✗")")
            print("   Gap parse: \(Int(scheduleGap) != nil ? "✓" : "✗")")
            print("   From parse: \(parseTimeToMinutes(scheduleFrom) != nil ? "✓" : "✗")")
            print("   To parse: \(parseTimeToMinutes(scheduleTo) != nil ? "✓" : "✗")")
            return
        }
        
        // Adjust end time if it's before start time (assume PM)
        toMinutes = adjustEndTimeIfNeeded(startMinutes: fromMinutes, endMinutes: toMinutes)
        
        print("✅ All inputs parsed successfully")
        print("   From minutes: \(fromMinutes), To minutes: \(toMinutes)")
        
        var scheduleLines: [String] = []
        var currentStart = fromMinutes
        
        while currentStart < toMinutes {
            let currentEnd = min(currentStart + intervalMinutes, toMinutes)
            
            let startTime = formatMinutesToTime(currentStart)
            let endTime = formatMinutesToTime(currentEnd)
            
            let line = "\(startTime) - \(endTime) - \(scheduleTaskName)"
            scheduleLines.append(line)
            print("   Generated: \(line)")
            
            // Move to next block (add interval + gap)
            currentStart = currentEnd + gapMinutes
        }
        
        print("📝 Generated \(scheduleLines.count) schedule blocks")
        
        // Append to notes
        let generatedSchedule = scheduleLines.joined(separator: "\n")
        print("📋 Current notes length: \(notesText.count)")
        
        if notesText.isEmpty {
            notesText = generatedSchedule
        } else {
            notesText += "\n" + generatedSchedule
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
        let components = cleanTime.components(separatedBy: ":")
        
        guard components.count == 2,
              let hours = Int(components[0]),
              let mins = Int(components[1]) else {
            return nil
        }
        
        return hours * 60 + mins
    }
    
    private func adjustEndTimeIfNeeded(startMinutes: Int, endMinutes: Int) -> Int {
        // If end time is before start time, assume it's meant to be PM (add 12 hours)
        if endMinutes < startMinutes && endMinutes < 720 { // 720 = 12:00
            return endMinutes + (12 * 60)
        }
        return endMinutes
    }
    
    private func formatMinutesToTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return String(format: "%d:%02d", hours, mins)
    }
    
    private func startNextCycle() {
        print("🔄 Starting next cycle...")
        
        // Show transitioning state
        isTransitioning = true
        
        // Stop the timer to ensure clean transition
        settings.stopTimer()
        
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
            let remainingMinutes = currentEntry.endMinutes - currentMinutes
            currentCycleDuration = remainingMinutes
            
            if remainingMinutes > 0 {
                print("🎯 Starting task cycle: \(currentEntry.description) for \(remainingMinutes) minutes")
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
                    
                    currentTaskName = "Preparation/Rest/Drink Water"
                    currentCycleDuration = gapMinutes
                    
                    if gapMinutes > 0 {
                        print("🎯 Starting preparation cycle for \(gapMinutes) minutes")
                        // Small delay to ensure clean state transition
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.startCycleWithDuration(gapMinutes, taskName: "Preparation/Rest/Drink Water")
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
            
            currentTaskName = "Preparation/Rest/Drink Water"
            currentCycleDuration = gapMinutes
            
            if gapMinutes > 0 {
                print("🎯 Starting preparation cycle for \(gapMinutes) minutes")
                // Small delay to ensure clean state transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startCycleWithDuration(gapMinutes, taskName: "Preparation/Rest/Drink Water")
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
}

#Preview {
    DailyNotesView(selectedDate: Date())
        .modelContainer(for: [DailyNote.self], inMemory: true)
}