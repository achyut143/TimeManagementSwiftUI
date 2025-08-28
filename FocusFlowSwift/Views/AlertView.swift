import SwiftUI
import SwiftData
import AVFoundation
import ActivityKit

struct AlertView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AlertSettings.shared
    @State private var showingCycleConfiguration = false
    @State private var showingConfigurationSelector = false
    @State private var showingConfigurationCreator = false
    @Query private var savedConfigurations: [CycleConfiguration]
    @State private var countdownTimer: Timer?
    @State private var timeRemaining: TimeInterval = 0
    @State private var childLockEnabled = false
    @State private var showingChildLockAlert = false
    @State private var pendingAction: (() -> Void)?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    counterView
                    
                    if settings.isPlaying || settings.isPaused {
                        alertInfoView
                        
                        // Live Activity status for user feedback
                        if #available(iOS 16.1, *) {
                            liveActivityStatusView
                        }
                    }
                    
                    cyclesToggleView
                    
                    if settings.useCycles {
                        cyclesControlView
                    } else {
                        regularControlsView
                    }
                    
                    actionButtonsView
                    
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
                        childLockEnabled.toggle()
                    }) {
                        Image(systemName: childLockEnabled ? "lock.fill" : "lock.open.fill")
                            .foregroundStyle(childLockEnabled ? .orange : .secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCycleConfiguration) {
                CycleConfigurationView()
            }
            .sheet(isPresented: $showingConfigurationSelector) {
                ConfigurationSelectorView(configurations: savedConfigurations)
            }
            .sheet(isPresented: $showingConfigurationCreator) {
                ConfigurationCreatorView()
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
                    // Only set new alert time if we're starting fresh (not resuming)
                    if settings.nextAlertDate <= Date() || settings.startTime.isEmpty {
                        settings.nextAlertDate = Date().addingTimeInterval(TimeInterval(settings.intervalMinutes * 60))
                    }
                    settings.scheduleIntervalTimer()
                    startCountdownTimer()
                    
                    // Resume Live Activity if it was paused
                    if #available(iOS 16.1, *) {
                        settings.resumeLiveActivity()
                    }
                } else {
                    settings.stopTimer()
                    stopCountdownTimer()
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
                    stopCountdownTimer()
                } else if settings.isPlaying {
                    startCountdownTimer()
                }
            }
        }
        .onAppear {
            startCountdownTimer()
        }
        .onDisappear {
            stopCountdownTimer()
        }
        .alert("Child Lock Enabled", isPresented: $showingChildLockAlert) {
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
            Button("Unlock & Continue", role: .destructive) {
                childLockEnabled = false
                pendingAction?()
                pendingAction = nil
            }
        } message: {
            Text("Child lock is enabled to prevent accidental changes. Unlock to continue.")
        }
    }
    
    private func executeWithChildLockCheck(action: @escaping () -> Void) {
        if childLockEnabled {
            pendingAction = action
            showingChildLockAlert = true
        } else {
            action()
        }
    }

    private var counterView: some View {
        VStack(spacing: 12) {
            if settings.useCycles {
                // Show cycle progress
                let cycleProgress = settings.getCurrentCycleProgress()
                let totalProgress = settings.getTotalCyclesProgress()
                
                VStack(spacing: 8) {
                    Text("\(cycleProgress.current)/\(cycleProgress.total)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    
                    if settings.isPlaying && !settings.isPaused {
                        Text(formatTimeRemaining(timeRemaining))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(settings.isInRestPeriod ? .yellow : (timeRemaining <= 30 ? .red : .green))
                            .animation(.easeInOut(duration: 0.3), value: timeRemaining <= 30)
                    }
                    
                    HStack {
                        Text("Current Cycle Progress")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if settings.isPlaying && !settings.isPaused {
                            Text("Next Alert")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    ProgressView(
                        value: Double(cycleProgress.current),
                        total: Double(cycleProgress.total)
                    )
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    
                    Text("Cycle \(totalProgress.current) of \(totalProgress.total)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                // Regular counter view
                Text("\(settings.counter)\(settings.targetIntervals.map { "/\($0)" } ?? "")")
                    .font(.system(size: 48, weight: .bold, design: .rounded))

                if settings.isPlaying && !settings.isPaused {
                    Text(formatTimeRemaining(timeRemaining))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(settings.isInRestPeriod ? .yellow : (timeRemaining <= 30 ? .red : .green))
                        .animation(.easeInOut(duration: 0.3), value: timeRemaining <= 30)
                }

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
            
            if settings.useCycles && !settings.cyclePhases.isEmpty && settings.currentCycleIndex < settings.cyclePhases.count {
                HStack {
                    Image(systemName: "repeat.circle.fill")
                        .foregroundStyle(.purple)
                    Text("Current: \(settings.cyclePhases[settings.currentCycleIndex].name)")
                    Spacer()
                }
            }
            
            if let config = settings.currentCycleConfiguration {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.orange)
                    Text("Config: \(config.name)")
                    Spacer()
                }
            }
        }
        .font(.caption)
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var cyclesToggleView: some View {
        VStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { settings.useCycles },
                set: { newValue in
                    executeWithChildLockCheck {
                        settings.useCycles = newValue
                        if newValue {
                            settings.setupDefaultCycles()
                        }
                    }
                }
            )) {
                HStack {
                    Text("Use Cycles")
                        .font(.headline)
                    if childLockEnabled {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .disabled(childLockEnabled)
            
            if settings.useCycles {
                Text("Configure custom interval cycles with different durations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var cyclesControlView: some View {
        VStack(spacing: 20) {
            // Configuration management section
            VStack(spacing: 12) {
                HStack {
                    Text("Configuration")
                        .font(.headline)
                    Spacer()
                }
                
                HStack {
                    Text("Current:")
                    Spacer()
                    if let config = settings.currentCycleConfiguration {
                        Text(config.name)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    } else {
                        Text("Custom")
                            .foregroundStyle(.tertiary)
                    }
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button(action: {
                            executeWithChildLockCheck {
                                showingConfigurationSelector = true
                            }
                        }) {
                            HStack {
                                Text("Load Config")
                                if childLockEnabled {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(childLockEnabled)
                        
                        Button(action: {
                            executeWithChildLockCheck {
                                showingConfigurationCreator = true
                            }
                        }) {
                            HStack {
                                Text("Save Config")
                                if childLockEnabled {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(childLockEnabled)
                        
                        if settings.currentCycleConfiguration != nil {
                            Button(action: {
                                executeWithChildLockCheck {
                                    settings.currentCycleConfiguration = nil
                                    settings.setupDefaultCycles()
                                }
                            }) {
                                HStack {
                                    Text("Clear Config")
                                    if childLockEnabled {
                                        Image(systemName: "lock.fill")
                                            .font(.caption2)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .foregroundStyle(.red)
                            .disabled(childLockEnabled)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding()
            .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            
            Divider()
            
            // Cycle configuration section
            VStack(spacing: 16) {
                HStack {
                    Text("Cycle Setup")
                        .font(.headline)
                    Spacer()
                    Text("\(settings.cyclePhases.count) cycles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack(spacing: 12) {
                    HStack {
                        Text("Interval Duration:")
                        if childLockEnabled {
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
                                    if !childLockEnabled {
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
                        .disabled(childLockEnabled)
                        Text("min")
                        
                        TextField(
                            "0",
                            text: Binding(
                                get: { String(settings.intervalSeconds) },
                                set: { newValue in
                                    if !childLockEnabled {
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
                        .disabled(childLockEnabled)
                        Text("sec")
                    }
                }
                
                VStack(spacing: 12) {
                    HStack {
                        Text("Rest Period:")
                        if childLockEnabled {
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
                                    if !childLockEnabled {
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
                        .disabled(childLockEnabled)
                        Text("min")
                        
                        TextField(
                            "0",
                            text: Binding(
                                get: { String(settings.restSeconds) },
                                set: { newValue in
                                    if !childLockEnabled {
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
                        .disabled(childLockEnabled)
                        Text("sec")
                    }
                    
                    Text("Optional rest between intervals")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                VStack(spacing: 12) {
                    HStack {
                        Text("Speech Announcements")
                            .font(.headline)
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
                                        if !childLockEnabled {
                                            settings.workIntervalText = newValue
                                        }
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .disabled(childLockEnabled)
                        }
                        
                        HStack {
                            Text("Rest:")
                                .frame(width: 50, alignment: .leading)
                            TextField(
                                "Optional",
                                text: Binding(
                                    get: { settings.restIntervalText },
                                    set: { newValue in
                                        if !childLockEnabled {
                                            settings.restIntervalText = newValue
                                        }
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .disabled(childLockEnabled)
                        }
                    }
                    
                    Text("Optional: Add custom speech for work/rest periods")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Button(action: {
                    executeWithChildLockCheck {
                        showingCycleConfiguration = true
                    }
                }) {
                    HStack {
                        Text("Configure Cycles")
                        if childLockEnabled {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(childLockEnabled)
            }
            
            // Cycle navigation controls
            if settings.isPlaying && !settings.cyclePhases.isEmpty {
                VStack(spacing: 12) {
                    HStack {
                        Text("Cycle Navigation")
                            .font(.headline)
                        Spacer()
                    }
                    
                    HStack(spacing: 16) {
                        Button(action: {
                            settings.skipToPreviousCycle()
                        }) {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.bordered)
                        .disabled(settings.currentCycleIndex <= 0)
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            Text("Current Cycle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if settings.currentCycleIndex < settings.orderedCyclePhases.count {
                                Text(settings.orderedCyclePhases[settings.currentCycleIndex].name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            settings.skipToNextCycle()
                        }) {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.bordered)
                        .disabled(settings.currentCycleIndex >= settings.orderedCyclePhases.count - 1)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            
            // Time information
            VStack(spacing: 12) {
                HStack {
                    Text("Time Information")
                        .font(.headline)
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Time Completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        let completedMinutes = settings.getTotalTimeCompleted()
                        let hours = completedMinutes / 60
                        let minutes = completedMinutes % 60
                        
                        if hours > 0 {
                            Text("\(hours)h \(minutes)m")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        } else {
                            Text("\(minutes)m")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    Spacer()
                    
                    if settings.useCycles {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Total Duration")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            let totalMinutes = settings.getTotalCycleDuration()
                            let totalHours = totalMinutes / 60
                            let remainingMinutes = totalMinutes % 60
                            
                            if totalHours > 0 {
                                Text("\(totalHours)h \(remainingMinutes)m")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            } else {
                                Text("\(remainingMinutes)m")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                
                if settings.useCycles {
                    let completedMinutes = settings.getTotalTimeCompleted()
                    let totalMinutes = settings.getTotalCycleDuration()
                    let percentage = totalMinutes > 0 ? Double(completedMinutes) / Double(totalMinutes) : 0
                    
                    ProgressView(value: percentage)
                        .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                    
                    HStack {
                        Text("Overall Progress")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(percentage * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.purple)
                    }
                }
            }
            .padding()
            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            
            // Current cycles display
            if !settings.cyclePhases.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Configured Cycles")
                            .font(.headline)
                        Spacer()
                        Text("\(settings.cyclePhases.reduce(0) { $0 + $1.totalMinutes }) min total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    LazyVStack(spacing: 8) {
                        ForEach(Array(settings.orderedCyclePhases.enumerated()), id: \.element.id) { index, phase in
                            HStack {
                                Circle()
                                    .fill(index == settings.currentCycleIndex ? .blue : .gray.opacity(0.3))
                                    .frame(width: 10, height: 10)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phase.name)
                                        .font(.subheadline)
                                        .fontWeight(index == settings.currentCycleIndex ? .semibold : .regular)
                                        .foregroundStyle(index == settings.currentCycleIndex ? .primary : .secondary)
                                    
                                    Text("\(phase.totalMinutes) min • \(phase.totalIntervals(intervalMinutes: settings.intervalMinutes)) intervals")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                
                                Spacer()
                                
                                if index == settings.currentCycleIndex && settings.isPlaying {
                                    let progress = settings.getCurrentCycleProgress()
                                    Text("\(progress.current)/\(progress.total)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            }
        }
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
                    if childLockEnabled {
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
                                if !childLockEnabled {
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
                    .disabled(childLockEnabled)
                    Text("min")
                    
                    TextField(
                        "0",
                        text: Binding(
                            get: { String(settings.intervalSeconds) },
                            set: { newValue in
                                if !childLockEnabled {
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
                    .disabled(childLockEnabled)
                    Text("sec")
                }
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Rest Period:")
                    if childLockEnabled {
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
                                if !childLockEnabled {
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
                    .disabled(childLockEnabled)
                    Text("min")
                    
                    TextField(
                        "0",
                        text: Binding(
                            get: { String(settings.restSeconds) },
                            set: { newValue in
                                if !childLockEnabled {
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
                    .disabled(childLockEnabled)
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
                    if childLockEnabled {
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
                                    if !childLockEnabled {
                                        settings.workIntervalText = newValue
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .disabled(childLockEnabled)
                    }
                    
                    HStack {
                        Text("Rest:")
                            .frame(width: 50, alignment: .leading)
                        TextField(
                            "Optional",
                            text: Binding(
                                get: { settings.restIntervalText },
                                set: { newValue in
                                    if !childLockEnabled {
                                        settings.restIntervalText = newValue
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .disabled(childLockEnabled)
                    }
                }
                
                Text("Customize what is spoken during intervals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Target:")
                if childLockEnabled {
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
                            if !childLockEnabled {
                                settings.targetIntervals = $0 > 0 ? $0 : nil
                            }
                        }
                    ),
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .keyboardType(.numberPad)
                .disabled(childLockEnabled)
                Text("intervals")
            }
        }
        .padding()
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var actionButtonsView: some View {
        VStack(spacing: 16) {
            Toggle(isOn: Binding(
                get: { settings.isPlaying },
                set: { newValue in
                    executeWithChildLockCheck {
                        if newValue {
                            // Starting/Resuming alerts
                            settings.isPlaying = true
                            settings.isPaused = false
                            
                            // Force clear any old Live Activity instances first
                            if #available(iOS 16.1, *) {
                                LiveActivityManager.shared.forceEndAndClearActivity()
                            }
                            
                            // Only reset cycles if this is a fresh start (not resuming)
                            if settings.useCycles && settings.shouldResetCyclesOnStart {
                                settings.resetAllCycles()
                                settings.shouldResetCyclesOnStart = false
                            }
                            
                            // Set start time only if not resuming
                            if settings.startTime.isEmpty {
                                settings.intervalsComplete = false
                            }
                            

                        } else {
                            // Pausing alerts
                            settings.isPlaying = false
                            settings.isPaused = true
                            settings.stopTimer()
                            
                            // Pause Live Activity
                            if #available(iOS 16.1, *) {
                                settings.pauseLiveActivity()
                            }
                        }
                    }
                }
            )) {
                HStack {
                    Text(settings.isPlaying ? (settings.useCycles ? "Pause Alerts" : "Stop Alerts") : 
                         (settings.isPaused && settings.useCycles ? "Resume Alerts" : "Start Alerts"))
                        .font(.headline)
                    if childLockEnabled {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            .disabled(childLockEnabled)

            HStack(spacing: 16) {
                Button(action: {
                    executeWithChildLockCheck {
                        settings.counter = 0
                        settings.intervalsComplete = false
                        settings.isPaused = false
                        settings.startTime = ""
                        if settings.useCycles {
                            settings.resetAllCycles()
                            settings.shouldResetCyclesOnStart = true
                        }
                        
                        // End Live Activity on reset and ensure it's properly cleared
                        if #available(iOS 16.1, *) {
                            LiveActivityManager.shared.forceEndAndClearActivity()
                        }
                    }
                }) {
                    HStack {
                        Text("Reset")
                        if childLockEnabled {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(childLockEnabled)

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
                        settings.useCycles = false
                        settings.numberOfCycles = 1
                        settings.currentCycleConfiguration = nil
                        settings.shouldResetCyclesOnStart = true
                        settings.setupDefaultCycles()
                        
                        // End Live Activity on clear all
                        if #available(iOS 16.1, *) {
                            LiveActivityManager.shared.endCurrentActivity()
                        }
                    }
                }) {
                    HStack {
                        Text("Clear All")
                        if childLockEnabled {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(childLockEnabled)
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
            timeRemaining = max(0, settings.nextAlertDate.timeIntervalSinceNow)
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

struct CycleConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode
    @StateObject private var settings = AlertSettings.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("Configure Cycles")
                            .font(.headline)
                        
                        Text("Base interval: \(settings.intervalMinutes) minutes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if !settings.cyclePhases.isEmpty {
                            Text("Tap Edit to reorder cycles by dragging")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top)
                    
                    // Add/Remove cycles section
                    VStack(spacing: 12) {
                        HStack {
                            Text("Cycles (\(settings.cyclePhases.count))")
                                .font(.headline)
                            Spacer()
                            Button("Add Cycle") {
                                addNewCycle()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        if settings.cyclePhases.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "plus.circle.dashed")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No cycles configured")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text("Add your first cycle to get started")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Button("Add First Cycle") {
                                    addNewCycle()
                                }
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    
                    List {
                        ForEach(settings.orderedCyclePhases, id: \.id) { cycle in
                            if let index = settings.orderedCyclePhases.firstIndex(where: { $0.id == cycle.id }) {
                                CycleConfigurationRow(
                                    index: index,
                                    onDelete: {
                                        deleteCycle(at: index)
                                    }
                                )
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .onMove(perform: moveCycles)
                        .onDelete { indexSet in
                            for index in indexSet {
                                deleteCycle(at: index)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .frame(minHeight: CGFloat(settings.orderedCyclePhases.count * 120))
                    
                    Color.clear.frame(height: 20)
                }
                .padding()
            }
            .scrollDisabled(editMode?.wrappedValue.isEditing == true)
            .navigationTitle("Configure Cycles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        EditButton()
                        Button("Done") { 
                            updateNumberOfCycles()
                            dismiss() 
                        }
                    }
                }
            }
        }
    }
    
    private func addNewCycle() {
        let newCycle = CyclePhase(
            name: "Cycle \(settings.cyclePhases.count + 1)",
            totalMinutes: settings.cyclePhases.isEmpty ? 30 : 10,
            order: settings.cyclePhases.count
        )
        settings.cyclePhases.append(newCycle)
    }
    
    private func deleteCycle(at index: Int) {
        guard settings.cyclePhases.count > 1 else { return } // Keep at least one cycle
        
        // Get ordered cycles to find the correct cycle to delete
        let orderedCycles = settings.orderedCyclePhases
        guard index < orderedCycles.count else { return }
        
        let cycleToDelete = orderedCycles[index]
        
        // Remove from the actual array
        if let actualIndex = settings.cyclePhases.firstIndex(where: { $0.id == cycleToDelete.id }) {
            settings.cyclePhases.remove(at: actualIndex)
        }
        
        // Reorder remaining cycles
        let remainingCycles = settings.orderedCyclePhases
        for (i, cycle) in remainingCycles.enumerated() {
            cycle.order = i
            if cycle.name.hasPrefix("Cycle ") {
                cycle.name = "Cycle \(i + 1)"
            }
        }
        
        // Reset current cycle index if needed
        if settings.currentCycleIndex >= settings.cyclePhases.count {
            settings.currentCycleIndex = 0
        }
        
        // Force UI update
        settings.objectWillChange.send()
    }
    
    private func updateNumberOfCycles() {
        settings.updateCycleCount()
    }
    
    private func moveCycles(from source: IndexSet, to destination: Int) {
        // Get the current ordered cycles
        var orderedCycles = settings.orderedCyclePhases
        
        // Perform the move operation on the ordered array
        orderedCycles.move(fromOffsets: source, toOffset: destination)
        
        // Update the order property for all cycles based on their new positions
        // This is crucial - we need to update the order property which will cause
        // the orderedCyclePhases computed property to return them in the new order
        for (newIndex, cycle) in orderedCycles.enumerated() {
            cycle.order = newIndex
        }
        
        // Force immediate UI refresh
        settings.objectWillChange.send()
    }
}

struct CycleConfigurationRow: View {
    @StateObject private var settings = AlertSettings.shared
    let index: Int
    let onDelete: () -> Void
    @State private var cycleName: String = ""
    @State private var cycleMinutes: String = ""
    
    // Safe access to cycle phase
    private var cyclePhase: CyclePhase? {
        guard index < settings.orderedCyclePhases.count else { return nil }
        return settings.orderedCyclePhases[index]
    }
    
    var body: some View {
        Group {
            if let phase = cyclePhase {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        
                        Text("Cycle \(index + 1)")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Button("Remove") {
                            onDelete()
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                        .font(.caption)
                    }
                    
                    VStack(spacing: 8) {
                        HStack {
                            Text("Name:")
                                .frame(width: 60, alignment: .leading)
                            TextField("Cycle name", text: $cycleName)
                                .textFieldStyle(.roundedBorder)
                                .onAppear {
                                    cycleName = phase.name
                                }
                                .onChange(of: cycleName) { _, newValue in
                                    if let currentPhase = cyclePhase {
                                        currentPhase.name = newValue
                                    }
                                }
                        }
                        
                        HStack {
                            Text("Duration:")
                                .frame(width: 60, alignment: .leading)
                            TextField("Minutes", text: $cycleMinutes)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .keyboardType(.numberPad)
                                .onAppear {
                                    cycleMinutes = "\(phase.totalMinutes)"
                                }
                                .onChange(of: cycleMinutes) { _, newValue in
                                    if let minutes = Int(newValue), minutes > 0,
                                       let currentPhase = cyclePhase {
                                        currentPhase.totalMinutes = minutes
                                    }
                                }
                            Text("min")
                            
                            Spacer()
                            
                            let intervals = phase.totalIntervals(intervalMinutes: settings.intervalMinutes)
                            Text("(\(intervals) intervals)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            } else {
                // Fallback for invalid index
                EmptyView()
            }
        }
    }
}

struct ConfigurationSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AlertSettings.shared
    let configurations: [CycleConfiguration]
    
    var body: some View {
        NavigationView {
            List {
                if configurations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Saved Configurations")
                            .font(.headline)
                        Text("Create and save cycle configurations to reuse them later")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(configurations) { config in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(config.name)
                                    .font(.headline)
                                Spacer()
                                if settings.currentCycleConfiguration?.id == config.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            
                            Text("\(config.cycles.count) cycles • \(config.totalDuration) min total")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text("Created: \(config.createdDate.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            settings.currentCycleConfiguration = config
                            dismiss()
                        }
                    }
                    .onDelete(perform: deleteConfigurations)
                }
            }
            .navigationTitle("Saved Configurations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func deleteConfigurations(offsets: IndexSet) {
        for index in offsets {
            let config = configurations[index]
            if settings.currentCycleConfiguration?.id == config.id {
                settings.currentCycleConfiguration = nil
            }
            modelContext.delete(config)
        }
        try? modelContext.save()
    }
}

struct ConfigurationCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AlertSettings.shared
    @State private var configurationName = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        TextField("Configuration Name", text: $configurationName)
                            .textFieldStyle(.roundedBorder)
                            .font(.headline)
                        
                        Text("This will save your current cycle configuration")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cycles to Save:")
                            .font(.headline)
                        
                        ForEach(Array(settings.orderedCyclePhases.enumerated()), id: \.element.id) { index, phase in
                            HStack {
                                Text("\(index + 1).")
                                    .fontWeight(.medium)
                                    .frame(width: 30, alignment: .leading)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phase.name)
                                        .fontWeight(.medium)
                                    Text("\(phase.totalMinutes) min • \(phase.totalIntervals(intervalMinutes: settings.intervalMinutes)) intervals")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                    
                    Color.clear.frame(height: 20)
                }
                .padding()
            }
            .navigationTitle("Save Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        settings.createCycleConfiguration(
                            name: configurationName.isEmpty ? "Untitled Configuration" : configurationName,
                            context: modelContext
                        )
                        dismiss()
                    }
                    .disabled(settings.cyclePhases.isEmpty)
                }
            }
        }
    }
}