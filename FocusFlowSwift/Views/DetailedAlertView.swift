import SwiftUI
import SwiftData
import AVFoundation

struct DetailedAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var instance: AlertInstance
    @State private var showingCycleConfiguration = false
    @State private var showingEditView = false
    @State private var countdownTimer: Timer?
    @State private var timeRemaining: TimeInterval = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    counterView
                    
                    if instance.isRunning || instance.isPaused {
                        alertInfoView
                    }
                    
                    // Cycle navigation controls (only show in cycles mode)
                    if instance.useCycles && !instance.cyclePhases.isEmpty {
                        cycleNavigationControls
                    }
                    
                    // Time information
                    timeInformationView
                    
                    if instance.useCycles {
                        cyclesControlView
                    } else {
                        regularControlsView
                    }
                    
                    actionButtonsView
                    
                    Color.clear.frame(height: 20)
                }
                .padding()
            }
            .navigationTitle(instance.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") { showingEditView = true }
                }
            }
            .sheet(isPresented: $showingEditView) {
                EditAlertInstanceView(instance: instance)
            }
            .sheet(isPresented: $showingCycleConfiguration) {
                AlertInstanceCycleConfigurationView(instance: instance)
            }
            .onAppear {
                startCountdownTimer()
            }
            .onDisappear {
                stopCountdownTimer()
            }
        }
    }
    
    private var counterView: some View {
        VStack(spacing: 12) {
            if instance.useCycles {
                // Show cycle progress
                let cycleProgress = instance.getCurrentCycleProgress()
                let totalProgress = instance.getTotalCyclesProgress()
                
                VStack(spacing: 8) {
                    Text("\(cycleProgress.current)/\(cycleProgress.total)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    
                    // Countdown timer for cycles
                    if instance.isRunning && !instance.isPaused {
                        Text(formatTimeRemaining(timeRemaining))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(instance.isInRestPeriod ? .yellow : (timeRemaining <= 30 ? .red : .green))
                            .animation(.easeInOut(duration: 0.3), value: timeRemaining <= 30)
                    }
                    
                    HStack {
                        Text("Current Cycle Progress")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if instance.isRunning && !instance.isPaused {
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
                Text("\(instance.counter)\(instance.targetIntervals.map { "/\($0)" } ?? "")")
                    .font(.system(size: 48, weight: .bold, design: .rounded))

                // Countdown timer for regular mode
                if instance.isRunning && !instance.isPaused {
                    Text(formatTimeRemaining(timeRemaining))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(instance.isInRestPeriod ? .yellow : (timeRemaining <= 30 ? .red : .green))
                        .animation(.easeInOut(duration: 0.3), value: timeRemaining <= 30)
                }

                HStack {
                    Text("Intervals Completed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if instance.isRunning && !instance.isPaused {
                        Text("Next Alert")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let target = instance.targetIntervals {
                    ProgressView(
                        value: Double(instance.counter),
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
                Image(systemName: instance.isPaused ? "pause.circle.fill" : (instance.isInRestPeriod ? "bed.double.fill" : "speaker.wave.2.fill"))
                    .foregroundStyle(instance.isPaused ? .orange : (instance.isInRestPeriod ? .yellow : .blue))
                if instance.isPaused {
                    Text("Paused")
                } else if instance.isInRestPeriod {
                    if instance.restMinutes > 0 && instance.restSeconds > 0 {
                        Text("Rest: \(instance.restMinutes)m \(instance.restSeconds)s")
                    } else if instance.restMinutes > 0 {
                        Text("Rest: \(instance.restMinutes)m")
                    } else {
                        Text("Rest: \(instance.restSeconds)s")
                    }
                } else {
                    if instance.intervalMinutes > 0 && instance.intervalSeconds > 0 {
                        Text("Every \(instance.intervalMinutes)m \(instance.intervalSeconds)s")
                    } else if instance.intervalMinutes > 0 {
                        Text("Every \(instance.intervalMinutes)m")
                    } else {
                        Text("Every \(instance.intervalSeconds)s")
                    }
                }
                Spacer()
            }

            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.green)
                Text("Started: \(instance.startTime)")
                Spacer()
            }
            
            if !instance.isPaused {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.orange)
                    Text("Next: \(instance.nextAlertTime)")
                    Spacer()
                }
                
                // Countdown Timer
                HStack {
                    Image(systemName: "timer")
                        .foregroundStyle(instance.isInRestPeriod ? .yellow : (timeRemaining <= 30 ? .red : .blue))
                    Text("Time remaining: \(formatTimeRemaining(timeRemaining))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(instance.isInRestPeriod ? .yellow : (timeRemaining <= 30 ? .red : .blue))
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.3), value: timeRemaining <= 30)
            }
            
            if instance.useCycles && !instance.cyclePhases.isEmpty && instance.currentCycleIndex < instance.cyclePhases.count {
                let orderedPhases = instance.orderedCyclePhases
                if instance.currentCycleIndex < orderedPhases.count {
                    HStack {
                        Image(systemName: "repeat.circle.fill")
                            .foregroundStyle(.purple)
                        Text("Current: \(orderedPhases[instance.currentCycleIndex].name)")
                        Spacer()
                    }
                }
            }
        }
        .font(.caption)
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var cyclesControlView: some View {
        VStack(spacing: 20) {
            // Cycle configuration section
            VStack(spacing: 16) {
                HStack {
                    Text("Cycle Setup")
                        .font(.headline)
                    Spacer()
                    Text("\(instance.cyclePhases.count) cycles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Interval Duration:")
                    Spacer()
                    if instance.intervalMinutes > 0 && instance.intervalSeconds > 0 {
                        Text("\(instance.intervalMinutes)m \(instance.intervalSeconds)s")
                            .foregroundStyle(.secondary)
                    } else if instance.intervalMinutes > 0 {
                        Text("\(instance.intervalMinutes)m")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(instance.intervalSeconds)s")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button(action: { showingCycleConfiguration = true }) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // Current cycles display
            if !instance.cyclePhases.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Configured Cycles")
                            .font(.headline)
                        Spacer()
                        Text("\(instance.cyclePhases.reduce(0) { $0 + $1.totalMinutes }) min total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    LazyVStack(spacing: 8) {
                        ForEach(Array(instance.orderedCyclePhases.enumerated()), id: \.element.id) { index, phase in
                            HStack {
                                Circle()
                                    .fill(index == instance.currentCycleIndex ? .blue : .gray.opacity(0.3))
                                    .frame(width: 10, height: 10)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phase.name)
                                        .font(.subheadline)
                                        .fontWeight(index == instance.currentCycleIndex ? .semibold : .regular)
                                        .foregroundStyle(index == instance.currentCycleIndex ? .primary : .secondary)
                                    
                                    Text("\(phase.totalMinutes) min • \(phase.totalIntervals(intervalMinutes: instance.intervalMinutes)) intervals")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                
                                Spacer()
                                
                                if index == instance.currentCycleIndex && instance.isRunning {
                                    let progress = instance.getCurrentCycleProgress()
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
            
            HStack {
                Text("Interval:")
                Spacer()
                if instance.intervalMinutes > 0 && instance.intervalSeconds > 0 {
                    Text("\(instance.intervalMinutes)m \(instance.intervalSeconds)s")
                        .foregroundStyle(.secondary)
                } else if instance.intervalMinutes > 0 {
                    Text("\(instance.intervalMinutes)m")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(instance.intervalSeconds)s")
                        .foregroundStyle(.secondary)
                }
            }

            if let target = instance.targetIntervals {
                HStack {
                    Text("Target:")
                    Spacer()
                    Text("\(target) intervals")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var actionButtonsView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Button(action: {
                    if instance.isRunning {
                        instance.pause()
                    } else {
                        instance.start()
                    }
                }) {
                    Image(systemName: instance.isRunning ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: { instance.reset() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var cycleNavigationControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Cycle Navigation")
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 16) {
                Button(action: {
                    instance.skipToPreviousCycle()
                }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .disabled(instance.currentCycleIndex <= 0)
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text("Current Cycle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if instance.currentCycleIndex < instance.orderedCyclePhases.count {
                        Text(instance.orderedCyclePhases[instance.currentCycleIndex].name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    instance.skipToNextCycle()
                }) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .disabled(instance.currentCycleIndex >= instance.orderedCyclePhases.count - 1)
            }
        }
        .padding()
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var timeInformationView: some View {
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
                    
                    let completedMinutes = instance.getTotalTimeCompleted()
                    let hours = completedMinutes / 60
                    let minutes = completedMinutes % 60
                    
                    if hours > 0 {
                        Text("\(hours)h \(minutes)m")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    } else {
                        Text("\(minutes)m")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                }
                
                Spacer()
                
                if instance.useCycles {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Total Duration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        let totalMinutes = instance.getTotalCycleDuration()
                        let totalHours = totalMinutes / 60
                        let remainingMinutes = totalMinutes % 60
                        
                        if totalHours > 0 {
                            Text("\(totalHours)h \(remainingMinutes)m")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        } else {
                            Text("\(remainingMinutes)m")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            
            if instance.useCycles {
                let completedMinutes = instance.getTotalTimeCompleted()
                let totalMinutes = instance.getTotalCycleDuration()
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
        if instance.isRunning && !instance.isPaused {
            timeRemaining = max(0, instance.nextAlertDate.timeIntervalSinceNow)
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
    let instance = AlertInstance(name: "Test Alert", intervalMinutes: 5, useCycles: false)
    return DetailedAlertView(instance: instance)
}