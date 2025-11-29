import SwiftUI
import AVFoundation

struct MultitaskingTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var timerManager = MultitaskingTimerManager()
    @State private var showingTaskPicker = false
    @State private var selectingSlot: Int = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.1, green: 0.1, blue: 0.15), Color(red: 0.05, green: 0.05, blue: 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Header with controls
                    headerControlsView
                    
                    // Scrollable grid of timers
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ], spacing: 16) {
                            ForEach(0..<timerManager.tasks.count, id: \.self) { slot in
                                taskCardView(slot: slot)
                            }
                            
                            // Add timer button
                            addTimerCard
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundStyle(.white)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Task Timer")
                            .foregroundStyle(.white)
                            .fontWeight(.semibold)
                        if timerManager.isRunning, let active = timerManager.activeSlot, let taskName = timerManager.tasks[active] {
                            Text(taskName)
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { timerManager.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(Color(red: 0.1, green: 0.1, blue: 0.15), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingTaskPicker) {
                TaskPickerView(selectedTask: $timerManager.tasks[selectingSlot])
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    timerManager.handleAppDidBecomeActive()
                case .background, .inactive:
                    timerManager.handleAppWillResignActive()
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func taskCardView(slot: Int) -> some View {
        VStack(spacing: 0) {
            // Task header with delete button
            HStack {
                Spacer()
                
                VStack(spacing: 8) {
                    if let task = timerManager.tasks[slot] {
                        Text(task)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("No Task")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    
                    // Active indicator
                    if timerManager.activeSlot == slot && timerManager.isRunning {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Active")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text("Inactive")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                
                Spacer()
                
                // Delete button (only show if more than 2 timers)
                if timerManager.tasks.count > 2 {
                    Button(action: {
                        timerManager.removeTimer(at: slot)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .padding(.trailing, 8)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 12)
            
            Spacer()
            
            // Timer display
            Button(action: {
                if timerManager.tasks[slot] != nil {
                    timerManager.switchToTask(slot)
                }
            }) {
                Text(formatTime(timerManager.times[slot]))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(timerManager.activeSlot == slot ? .green : .white.opacity(0.7))
                    .monospacedDigit()
            }
            .buttonStyle(.plain)
            .disabled(timerManager.tasks[slot] == nil)
            
            Spacer()
            
            // Task selection button
            Button(action: {
                selectingSlot = slot
                showingTaskPicker = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: timerManager.tasks[slot] == nil ? "plus.circle.fill" : "pencil.circle.fill")
                        .font(.caption)
                    Text(timerManager.tasks[slot] == nil ? "Add Task" : "Change")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.white.opacity(0.1), in: Capsule())
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(cardBackground(for: slot))
        .shadow(color: timerManager.activeSlot == slot ? .green.opacity(0.3) : .clear, radius: 10)
    }
    
    private func cardBackground(for slot: Int) -> some View {
        let isActive = timerManager.activeSlot == slot
        let fillColor = isActive ? Color.green.opacity(0.15) : Color.white.opacity(0.05)
        let strokeColor = isActive ? Color.green.opacity(0.5) : Color.white.opacity(0.1)
        
        return RoundedRectangle(cornerRadius: 20)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(strokeColor, lineWidth: 2)
            )
    }
    
    private var addTimerCard: some View {
        Button(action: {
            timerManager.addTimer()
        }) {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                
                Text("Add Timer")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                            .foregroundStyle(.white.opacity(0.3))
                    )
            )
        }
    }
    
    private var headerControlsView: some View {
        let hasAnyTask = timerManager.tasks.contains(where: { $0 != nil })
        
        return VStack(spacing: 16) {
            // Play/Pause button
            Button(action: {
                timerManager.toggleTimer()
            }) {
                HStack(spacing: 12) {
                    Image(systemName: timerManager.isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                    Text(timerManager.isRunning ? "Pause" : "Start")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(timerManager.isRunning ? Color.orange : Color.blue)
                )
            }
            .disabled(!hasAnyTask)
            .opacity(hasAnyTask ? 1 : 0.5)
            .padding(.horizontal)
            
            // Instructions
            if !hasAnyTask {
                Text("Add at least one task to start tracking")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            } else if !timerManager.isRunning {
                Text("Tap a timer to switch tasks")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}

class MultitaskingTimerManager: ObservableObject {
    @Published var tasks: [String?] = [nil, nil] {
        didSet { 
            if isInitialized { saveTasks() }
        }
    }
    @Published var times: [TimeInterval] = [0, 0] {
        didSet { 
            if isInitialized { saveTimes() }
        }
    }
    @Published var activeSlot: Int? = nil {
        didSet { 
            if isInitialized { saveActiveSlot() }
        }
    }
    @Published var isRunning = false {
        didSet { 
            if isInitialized { saveRunningState() }
        }
    }
    
    private var timer: Timer?
    private var speechSynthesizer = AVSpeechSynthesizer()
    private var isInitialized = false
    
    init() {
        loadState()
        isInitialized = true
    }
    
    func addTimer() {
        tasks.append(nil)
        times.append(0)
    }
    
    func removeTimer(at index: Int) {
        guard tasks.count > 2 else { return } // Keep minimum 2 timers
        
        // If removing active timer, stop it
        if activeSlot == index {
            pauseTimer()
            activeSlot = nil
        } else if let active = activeSlot, active > index {
            // Adjust active slot if needed
            activeSlot = active - 1
        }
        
        tasks.remove(at: index)
        times.remove(at: index)
        
        // Clear saved state for removed timer
        UserDefaults.standard.removeObject(forKey: "multitasking_task_\(index)")
        UserDefaults.standard.removeObject(forKey: "multitasking_time_\(index)")
    }
    
    func switchToTask(_ slot: Int) {
        guard tasks[slot] != nil else { return }
        
        // If switching to a different task while running
        if isRunning && activeSlot != slot {
            // Announce the switch
            if let taskName = tasks[slot] {
                announceSwitch(to: taskName)
            }
        }
        
        activeSlot = slot
        
        // Auto-start if not running
        if !isRunning {
            startTimer()
        }
    }
    
    func toggleTimer() {
        if isRunning {
            pauseTimer()
        } else {
            startTimer()
        }
    }
    
    private func startTimer() {
        // Check if at least one task is set
        guard tasks.contains(where: { $0 != nil }) else { return }
        
        // Don't start if already running
        if timer != nil {
            return
        }
        
        // Start with first non-nil task if none selected
        if activeSlot == nil {
            activeSlot = tasks.firstIndex(where: { $0 != nil }) ?? 0
        }
        
        isRunning = true
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let active = self.activeSlot else { return }
            if active < self.times.count {
                self.times[active] += 0.1
            }
        }
    }
    
    private func pauseTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    func reset() {
        pauseTimer()
        times = Array(repeating: 0, count: tasks.count)
        activeSlot = nil
        
        // Clear saved state
        for i in 0..<tasks.count {
            UserDefaults.standard.removeObject(forKey: "multitasking_time_\(i)")
        }
        UserDefaults.standard.removeObject(forKey: "multitasking_active_slot")
        UserDefaults.standard.removeObject(forKey: "multitasking_is_running")
        UserDefaults.standard.removeObject(forKey: "multitasking_last_save")
    }
    
    private func announceSwitch(to taskName: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        
        let utterance = AVSpeechUtterance(string: taskName)
        utterance.rate = 0.5
        utterance.volume = 0.8
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speechSynthesizer.speak(utterance)
    }
    
    // MARK: - Persistence
    
    private func saveTasks() {
        UserDefaults.standard.set(tasks.count, forKey: "multitasking_timer_count")
        for (index, task) in tasks.enumerated() {
            if let task = task {
                UserDefaults.standard.set(task, forKey: "multitasking_task_\(index)")
            } else {
                UserDefaults.standard.removeObject(forKey: "multitasking_task_\(index)")
            }
        }
    }
    
    private func saveTimes() {
        for (index, time) in times.enumerated() {
            UserDefaults.standard.set(time, forKey: "multitasking_time_\(index)")
        }
        UserDefaults.standard.set(Date(), forKey: "multitasking_last_save")
    }
    
    private func saveActiveSlot() {
        if let slot = activeSlot {
            UserDefaults.standard.set(slot, forKey: "multitasking_active_slot")
        } else {
            UserDefaults.standard.removeObject(forKey: "multitasking_active_slot")
        }
    }
    
    private func saveRunningState() {
        UserDefaults.standard.set(isRunning, forKey: "multitasking_is_running")
        if isRunning {
            UserDefaults.standard.set(Date(), forKey: "multitasking_last_save")
        }
    }
    
    private func loadState() {
        // Load timer count (default to 2)
        let timerCount = UserDefaults.standard.integer(forKey: "multitasking_timer_count")
        let count = timerCount > 0 ? timerCount : 2
        
        // Load tasks
        var loadedTasks: [String?] = []
        for i in 0..<count {
            let task = UserDefaults.standard.string(forKey: "multitasking_task_\(i)")
            loadedTasks.append(task)
        }
        tasks = loadedTasks
        
        // Load times
        var loadedTimes: [TimeInterval] = []
        for i in 0..<count {
            let time = UserDefaults.standard.double(forKey: "multitasking_time_\(i)")
            loadedTimes.append(time)
        }
        times = loadedTimes
        
        // Load active slot
        if UserDefaults.standard.object(forKey: "multitasking_active_slot") != nil {
            let slot = UserDefaults.standard.integer(forKey: "multitasking_active_slot")
            if slot < tasks.count {
                activeSlot = slot
            }
        }
        
        // Load running state and calculate elapsed time
        let wasRunning = UserDefaults.standard.bool(forKey: "multitasking_is_running")
        if wasRunning, let lastSave = UserDefaults.standard.object(forKey: "multitasking_last_save") as? Date,
           let active = activeSlot, active < times.count {
            // Calculate time elapsed since last save (only if reasonable)
            let elapsed = Date().timeIntervalSince(lastSave)
            if elapsed > 0 && elapsed < 86400 {
                times[active] += elapsed
            }
            
            // Auto-resume if it was running
            isRunning = true
            
            // Start timer after a brief delay to ensure UI is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                if self.timer == nil && self.isRunning {
                    self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                        guard let self = self, let active = self.activeSlot, active < self.times.count else { return }
                        self.times[active] += 0.1
                    }
                }
            }
        }
    }
    
    func handleAppWillResignActive() {
        // Save current state when app goes to background
        if isRunning {
            UserDefaults.standard.set(Date(), forKey: "multitasking_last_save")
        }
    }
    
    func handleAppDidBecomeActive() {
        // Don't process if we just loaded state
        guard isInitialized else { return }
        
        // Recalculate time if timer was running
        if isRunning, let lastSave = UserDefaults.standard.object(forKey: "multitasking_last_save") as? Date,
           let active = activeSlot {
            let elapsed = Date().timeIntervalSince(lastSave)
            
            // Only add elapsed time if it's reasonable (less than 24 hours)
            if elapsed > 0 && elapsed < 86400 {
                // Temporarily disable auto-save during update
                isInitialized = false
                times[active] += elapsed
                isInitialized = true
            }
            
            UserDefaults.standard.set(Date(), forKey: "multitasking_last_save")
            
            // Restart timer if it's not already running
            if timer == nil && isRunning {
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self = self, let active = self.activeSlot else { return }
                    self.times[active] += 0.1
                }
            }
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

struct TaskPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTask: String?
    @State private var customTaskName = ""
    
    let predefinedTasks = [
        "Work",
        "Study",
        "Exercise",
        "Reading",
        "Writing",
        "Coding",
        "Meeting",
        "Break",
        "Personal Project",
        "Learning"
    ]
    
    var body: some View {
        NavigationView {
            List {
                Section("Predefined Tasks") {
                    ForEach(predefinedTasks, id: \.self) { task in
                        Button(action: {
                            selectedTask = task
                            dismiss()
                        }) {
                            HStack {
                                Text(task)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedTask == task {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                
                Section("Custom Task") {
                    TextField("Enter task name", text: $customTaskName)
                    
                    Button("Use Custom Task") {
                        if !customTaskName.isEmpty {
                            selectedTask = customTaskName
                            dismiss()
                        }
                    }
                    .disabled(customTaskName.isEmpty)
                }
            }
            .navigationTitle("Select Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    MultitaskingTimerView()
}
