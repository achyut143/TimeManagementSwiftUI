import SwiftUI
import SwiftData
import AVFoundation
import ActivityKit

struct AlertView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AlertSettings.shared
    @State private var countdownTimer: Timer?
    @State private var timeRemaining: TimeInterval = 0
    @State private var displayPausedTime: TimeInterval = 0  // Separate state for displaying paused time
    @State private var showingChildLockAlert = false
    @State private var pendingAction: (() -> Void)?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    counterView
                    
                    // Main control buttons - moved up for easy access
                    mainControlButtonsView
                    
                    if settings.isPlaying || settings.isPaused {
                        alertInfoView
                        
                        // Live Activity status for user feedback
                        if #available(iOS 16.1, *) {
                            liveActivityStatusView
                        }
                    }
                    
                    regularControlsView
                    
                    // Add some bottom padding for better scrolling
                    Color.clear.frame(height: 20)
                }
                .padding()
            }
            .navigationTitle("Voice Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        settings.childLockEnabled.toggle()
                    }) {
                        Image(systemName: settings.childLockEnabled ? "lock.fill" : "lock.open.fill")
                            .foregroundStyle(settings.childLockEnabled ? .orange : .secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if settings.isPlaying {
                    try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
                    try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                    
                    // Only reschedule if the timer is not already running or if we missed the alert
                    if settings.nextAlertDate <= Date() {
                        settings.nextAlertDate = Date().addingTimeInterval(TimeInterval(settings.intervalMinutes * 60))
                        settings.scheduleIntervalTimer()
                    }
                    // Don't reschedule if the timer is still valid - just ensure it's running
                }
            }
            .onChange(of: settings.isPlaying) { _, newValue in
                if newValue {
                    // Starting or resuming
                    if settings.isPaused {
                        // Resuming from pause - the AlertSettings will handle restoring the time
                        settings.isPaused = false
                    } else {
                        // Starting fresh - only set new alert time if we're starting fresh
                        if settings.nextAlertDate <= Date() || settings.startTime.isEmpty {
                            settings.nextAlertDate = Date().addingTimeInterval(TimeInterval(settings.intervalMinutes * 60))
                        }
                    }
                    settings.scheduleIntervalTimer()
                    startCountdownTimer()
                    
                    // Resume Live Activity if it was paused
                    if #available(iOS 16.1, *) {
                        settings.resumeLiveActivity()
                    }
                } else {
                    // Stopping (not pausing - that's handled separately)
                    if !settings.isPaused {
                        settings.stopTimer()
                        stopCountdownTimer()
                    }
                }
            }
            .onChange(of: settings.intervalMinutes) { _, _ in
                if settings.isPlaying {
                    // Only reschedule if the interval change requires it
                    // Keep the existing next alert time if it's still in the future
                    if settings.nextAlertDate <= Date() {
                        settings.nextAlertDate = Date().addingTimeInterval(TimeInterval(settings.intervalMinutes * 60))
                    }
                    settings.scheduleIntervalTimer()
                    startCountdownTimer() // Restart countdown with new interval
                }
            }
            .onChange(of: settings.isPaused) { _, newValue in
                if newValue {
                    // Pausing - store remaining time for both AlertSettings and display
                    let remainingTime = max(0, settings.nextAlertDate.timeIntervalSinceNow)
                    settings.pausedTimeRemaining = remainingTime
                    displayPausedTime = remainingTime  // Store for display purposes
                    settings.stopTimer()
                    // Keep countdown timer running to show paused time
                    
                    // Pause Live Activity
                    if #available(iOS 16.1, *) {
                        settings.pauseLiveActivity()
                    }
                } else if settings.isPlaying {
                    // Resuming - restore the paused time and restart timer
                    if settings.pausedTimeRemaining > 0 {
                        settings.nextAlertDate = Date().addingTimeInterval(settings.pausedTimeRemaining)
                    }
                    displayPausedTime = 0  // Clear display paused time when resuming
                    settings.scheduleIntervalTimer()
                    startCountdownTimer()
                    
                    // Resume Live Activity
                    if #available(iOS 16.1, *) {
                        settings.resumeLiveActivity()
                    }
                }
            }
        }
        .onAppear {
            startCountdownTimer()
            // Initialize display paused time if we're already paused
            if settings.isPaused && settings.pausedTimeRemaining > 0 {
                displayPausedTime = settings.pausedTimeRemaining
            }
        }
        .onDisappear {
            stopCountdownTimer()
        }
        .alert("Child Lock Enabled", isPresented: $showingChildLockAlert) {
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
            Button("Unlock & Continue", role: .destructive) {
                settings.childLockEnabled = false
                pendingAction?()
                pendingAction = nil
            }
        } message: {
            Text("Child lock is enabled to prevent accidental changes. Unlock to continue.")
        }
    }
    
    private func executeWithChildLockCheck(action: @escaping () -> Void) {
        if settings.childLockEnabled {
            pendingAction = action
            showingChildLockAlert = true
        } else {
            action()
        }
    }

    private var counterView: some View {
        VStack(spacing: 12) {
            // Regular counter view
            Text("\(settings.counter)\(settings.targetIntervals.map { "/\($0)" } ?? "")")
                .font(.system(size: 48, weight: .bold, design: .rounded))

            // if settings.isPlaying && !settings.isPaused {
                Text(formatTimeRemaining(timeRemaining))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(settings.isInRestPeriod ? .yellow : (timeRemaining <= 30 ? .red : .green))
                    .animation(.easeInOut(duration: 0.3), value: timeRemaining <= 30)
            // }

            HStack {
                Text("Intervals Completed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if settings.isPlaying && !settings.isPaused {
                    Text("Next Alert")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let target = settings.targetIntervals {
                ProgressView(
                    value: Double(settings.counter),
                    total: Double(target)
                )
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            }
        }
        .padding(.vertical)
    }

    private var alertInfoView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: settings.isPaused ? "pause.circle.fill" : (settings.isInRestPeriod ? "bed.double.fill" : "speaker.wave.2.fill"))
                    .foregroundStyle(settings.isPaused ? .orange : (settings.isInRestPeriod ? .yellow : .blue))
                if settings.isPaused {
                    Text("Paused")
                } else if settings.isInRestPeriod {
                    let totalSeconds = settings.restMinutes * 60 + settings.restSeconds
                    if settings.restMinutes > 0 && settings.restSeconds > 0 {
                        Text("Rest: \(settings.restMinutes)m \(settings.restSeconds)s")
                    } else if settings.restMinutes > 0 {
                        Text("Rest: \(settings.restMinutes)m")
                    } else {
                        Text("Rest: \(settings.restSeconds)s")
                    }
                } else {
                    let totalSeconds = settings.intervalMinutes * 60 + settings.intervalSeconds
                    if settings.intervalMinutes > 0 && settings.intervalSeconds > 0 {
                        Text("Every \(settings.intervalMinutes)m \(settings.intervalSeconds)s")
                    } else if settings.intervalMinutes > 0 {
                        Text("Every \(settings.intervalMinutes)m")
                    } else {
                        Text("Every \(settings.intervalSeconds)s")
                    }
                }
                Spacer()
            }

            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.green)
                Text("Started: \(settings.startTime)")
                Spacer()
            }
            
            if !settings.isPaused {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.orange)
                    Text("Next: \(settings.nextAlertTime)")
                    Spacer()
                }
                
                // Countdown Timer
                HStack {
                    Image(systemName: "timer")
                        .foregroundStyle(settings.isInRestPeriod ? .yellow : (timeRemaining <= 30 ? .red : .blue))
                    Text("Time remaining: \(formatTimeRemaining(timeRemaining))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(settings.isInRestPeriod ? .yellow : (timeRemaining <= 30 ? .red : .blue))
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.3), value: timeRemaining <= 30)
            }
        }
        .font(.caption)
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var regularControlsView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Interval:")
                    if settings.childLockEnabled {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }
                
                HStack {
                    TextField(
                        "0",
                        text: Binding(
                            get: { String(settings.intervalMinutes) },
                            set: { newValue in
                                if !settings.childLockEnabled {
                                    if let value = Int(newValue) {
                                        settings.intervalMinutes = max(0, value)
                                    } else if newValue.isEmpty {
                                        settings.intervalMinutes = 0
                                    }
                                }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .keyboardType(.numberPad)
                    .disabled(settings.childLockEnabled)
                    Text("min")
                    
                    TextField(
                        "0",
                        text: Binding(
                            get: { String(settings.intervalSeconds) },
                            set: { newValue in
                                if !settings.childLockEnabled {
                                    if let value = Int(newValue) {
                                        settings.intervalSeconds = max(0, min(59, value))
                                    } else if newValue.isEmpty {
                                        settings.intervalSeconds = 0
                                    }
                                }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .keyboardType(.numberPad)
                    .disabled(settings.childLockEnabled)
                    Text("sec")
                }
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Rest Period:")
                    if settings.childLockEnabled {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }
                
                HStack {
                    TextField(
                        "0",
                        text: Binding(
                            get: { String(settings.restMinutes) },
                            set: { newValue in
                                if !settings.childLockEnabled {
                                    if let value = Int(newValue) {
                                        settings.restMinutes = max(0, value)
                                    } else if newValue.isEmpty {
                                        settings.restMinutes = 0
                                    }
                                }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .keyboardType(.numberPad)
                    .disabled(settings.childLockEnabled)
                    Text("min")
                    
                    TextField(
                        "0",
                        text: Binding(
                            get: { String(settings.restSeconds) },
                            set: { newValue in
                                if !settings.childLockEnabled {
                                    if let value = Int(newValue) {
                                        settings.restSeconds = max(0, min(59, value))
                                    } else if newValue.isEmpty {
                                        settings.restSeconds = 0
                                    }
                                }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .keyboardType(.numberPad)
                    .disabled(settings.childLockEnabled)
                    Text("sec")
                }
                
                Text("Optional rest between intervals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Speech Announcements")
                        .font(.headline)
                    if settings.childLockEnabled {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }
                
                VStack(spacing: 8) {
                    HStack {
                        Text("Work:")
                            .frame(width: 50, alignment: .leading)
                        TextField(
                            "Optional",
                            text: Binding(
                                get: { settings.workIntervalText },
                                set: { newValue in
                                    if !settings.childLockEnabled {
                                        settings.workIntervalText = newValue
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .disabled(settings.childLockEnabled)
                    }
                    
                    HStack {
                        Text("Rest:")
                            .frame(width: 50, alignment: .leading)
                        TextField(
                            "Optional",
                            text: Binding(
                                get: { settings.restIntervalText },
                                set: { newValue in
                                    if !settings.childLockEnabled {
                                        settings.restIntervalText = newValue
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .disabled(settings.childLockEnabled)
                    }
                }
                
                Text("Customize what is spoken during intervals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Target:")
                if settings.childLockEnabled {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                TextField(
                    "Optional",
                    value: Binding(
                        get: { settings.targetIntervals ?? 0 },
                        set: {
                            if !settings.childLockEnabled {
                                settings.targetIntervals = $0 > 0 ? $0 : nil
                            }
                        }
                    ),
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .keyboardType(.numberPad)
                .disabled(settings.childLockEnabled)
                Text("intervals")
            }
        }
        .padding()
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var mainControlButtonsView: some View {
        VStack(spacing: 12) {
            // Play/Pause Toggle
            Toggle(isOn: Binding(
                get: { settings.isPlaying },
                set: { newValue in
                    executeWithChildLockCheck {
                        if newValue {
                            // Starting/Resuming alerts
                            if settings.isPaused {
                                // Resuming from pause
                                settings.isPaused = false
                                settings.isPlaying = true
                            } else {
                                // Starting fresh
                                settings.isPlaying = true
                                settings.isPaused = false
                                
                                // Force clear any old Live Activity instances first
                                if #available(iOS 16.1, *) {
                                    LiveActivityManager.shared.forceEndAndClearActivity()
                                }
                                
                                // Set start time only if not resuming
                                if settings.startTime.isEmpty {
                                    settings.intervalsComplete = false
                                }
                            }
                        } else {
                            // Pausing alerts (not stopping completely)
                            settings.isPaused = true
                            settings.isPlaying = false
                        }
                    }
                }
            )) {
                HStack {
                    Text(settings.isPlaying ? "Stop Alerts" : 
                         (settings.isPaused ? "Resume Alerts" : "Start Alerts"))
                        .font(.headline)
                    if settings.childLockEnabled {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            .disabled(settings.childLockEnabled)

            // Action buttons row
            HStack(spacing: 12) {
                Button(action: {
                    executeWithChildLockCheck {
                        settings.isPlaying = false
                        settings.isPaused = false
                        settings.counter = 0
                        settings.intervalsComplete = false
                        settings.startTime = ""
                        settings.clearPauseState()
                        settings.stopTimer()
                        displayPausedTime = 0  // Clear display paused time
                        
                        // End Live Activity on reset and ensure it's properly cleared
                        if #available(iOS 16.1, *) {
                            LiveActivityManager.shared.forceEndAndClearActivity()
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                        if settings.childLockEnabled {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(settings.childLockEnabled)

                Button(action: {
                    executeWithChildLockCheck {
                        settings.isPlaying = false
                        settings.isPaused = false
                        settings.stopTimer()
                        settings.counter = 0
                        settings.startTime = ""
                        settings.intervalMinutes = 5
                        settings.intervalSeconds = 0
                        settings.restMinutes = 0
                        settings.restSeconds = 0
                        settings.isInRestPeriod = false
                        settings.workIntervalText = ""
                        settings.restIntervalText = ""
                        settings.targetIntervals = nil
                        settings.clearPauseState()
                        displayPausedTime = 0  // Clear display paused time
                        
                        // End Live Activity on clear all
                        if #available(iOS 16.1, *) {
                            LiveActivityManager.shared.endCurrentActivity()
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All")
                        if settings.childLockEnabled {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(settings.childLockEnabled)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    @available(iOS 16.1, *)
    private var liveActivityStatusView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "iphone")
                    .foregroundStyle(.blue)
                Text("Device Status")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack {
                Image(systemName: settings.getLiveActivityStatus().contains("not available") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(settings.getLiveActivityStatus().contains("not available") ? .orange : .green)
                    .font(.caption)
                
                Text(settings.getLiveActivityStatus())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            
            if settings.isPlaying {
                VStack(spacing: 8) {
                    HStack {
                        Button("Force Refresh Dynamic Island") {
                            settings.forceRefreshLiveActivity()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        
                        Button("Debug State") {
                            if #available(iOS 16.1, *) {
                                settings.debugLiveActivityState()
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        
                        Spacer()
                    }
                    
                    if #available(iOS 16.1, *) {
                        Text("Counter: \(settings.counter) | Active: \(settings.liveActivityManager.isActivityActive ? "Yes" : "No")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func handleAlertFire() {
        // Speech is now handled in AlertSettings
    }
    
    // MARK: - Countdown Timer Methods
    
    private func startCountdownTimer() {
        stopCountdownTimer() // Stop any existing timer
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateTimeRemaining()
        }
    }
    
    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    private func updateTimeRemaining() {
        if settings.isPlaying && !settings.isPaused {
            // Timer is running - show actual time remaining
            timeRemaining = max(0, settings.nextAlertDate.timeIntervalSinceNow)
        } else if settings.isPaused {
            // Timer is paused - show the stored paused time (frozen)
            timeRemaining = displayPausedTime
        } else if !settings.isPlaying {
            // Timer is stopped - show full interval time
            let totalSeconds = settings.intervalMinutes * 60 + settings.intervalSeconds
            timeRemaining = TimeInterval(totalSeconds)
        } else {
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
}

#Preview {
    AlertView()
        .modelContainer(for: [CycleConfiguration.self], inMemory: true)
}