import SwiftUI
import SwiftData

struct AlertManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var alertManager: AlertManager
    @State private var showingNewAlertSheet = false
    @State private var editingAlert: AlertInstance? = nil
    @State private var selectedAlert: AlertInstance? = nil
    @State private var showHiddenAlerts = false
    @State private var showingMultitaskingTimer = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                let currentAlerts = showHiddenAlerts ? alertManager.hiddenAlerts : alertManager.visibleAlerts
                VStack(spacing: 20) {
                    // Header with global controls
                    headerView
                    
                    // Active alerts section
                    if !currentAlerts.isEmpty {
                        activeAlertsSection(currentAlerts)
                    }
                    
                    // Multitasking Timer button
                    if !showHiddenAlerts {
                        multitaskingTimerSection
                    }
                    
                    // Add new alert button
                    if !showHiddenAlerts {
                        addAlertSection
                    }
                    
                    Color.clear.frame(height: 20)
                }
                .padding()
            }
            .navigationTitle("Alert Manager")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingNewAlertSheet) {
                NewAlertInstanceView(alertManager: alertManager)
            }
            .sheet(item: $editingAlert) { instance in
                EditAlertInstanceView(instance: instance)
            }
            .sheet(item: $selectedAlert) { instance in
                DetailedAlertView(instance: instance)
            }
            .fullScreenCover(isPresented: $showingMultitaskingTimer) {
                MultitaskingTimerView()
            }
            .onAppear {
                // Initialize AlertManager with modelContext
                if alertManager.modelContext == nil {
                    alertManager.modelContext = modelContext
                }
                alertManager.loadAlertInstances()
                
                // Force refresh Live Activity when alert manager appears
                if #available(iOS 16.1, *) {
                    AlertSettings.shared.forceRefreshLiveActivity()
                }
            }
            .onDisappear {
                // Save context when view disappears to persist state
                try? modelContext.save()
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(showHiddenAlerts ? "Hidden Alerts" : "Active Alerts")
                        .font(.headline)
                    if showHiddenAlerts {
                        Text("\(alertManager.hiddenAlerts.count) hidden alerts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(alertManager.activeCount) running • \(alertManager.pausedCount) paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    if !showHiddenAlerts {
                        Button(action: alertManager.pauseAll) {
                            Image(systemName: "pause.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(alertManager.activeCount == 0)
                        
                        Button(action: alertManager.resumeAll) {
                            Image(systemName: "play.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(alertManager.pausedCount == 0)
                    }
                    
                    Button(action: { showHiddenAlerts.toggle() }) {
                        Image(systemName: showHiddenAlerts ? "eye" : "eye.slash")
                            .font(.title3)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(showHiddenAlerts ? alertManager.hiddenAlerts.isEmpty : alertManager.visibleAlerts.isEmpty)
                }
            }
            
            let currentAlerts = showHiddenAlerts ? alertManager.hiddenAlerts : alertManager.visibleAlerts
            if currentAlerts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: showHiddenAlerts ? "eye.slash" : "bell.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(showHiddenAlerts ? "No hidden alerts" : "No alerts configured")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(showHiddenAlerts ? "Hidden alerts will appear here" : "Create your first alert to get started")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func activeAlertsSection(_ currentAlerts: [AlertInstance]) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(showHiddenAlerts ? "Hidden Alert Instances" : "Alert Instances")
                    .font(.headline)
                Spacer()
            }
            
            LazyVStack(spacing: 12) {
                ForEach(currentAlerts) { instance in
                    AlertInstanceCard(
                        instance: instance,
                        onToggle: { alertManager.toggleAlert(instance) },
                        onDelete: { alertManager.removeAlert(instance) },
                        onEdit: { editingAlert = instance },
                        onTap: { selectedAlert = instance },
                        onHide: { 
                            if showHiddenAlerts {
                                alertManager.showAlert(instance)
                            } else {
                                alertManager.hideAlert(instance)
                            }
                        },
                        isShowingHidden: showHiddenAlerts
                    )
                }
            }
        }
    }
    
    private var multitaskingTimerSection: some View {
        Button(action: { showingMultitaskingTimer = true }) {
            HStack {
                Image(systemName: "timer.square")
                    .font(.title3)
                Text("Multitasking Timer")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.purple)
        }
    }
    
    private var addAlertSection: some View {
        Button(action: { showingNewAlertSheet = true }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add New Alert")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.blue)
        }
    }
}

struct AlertInstanceCard: View {
    let instance: AlertInstance
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onTap: () -> Void
    let onHide: () -> Void
    let isShowingHidden: Bool
    
    @State private var countdownTimer: Timer?
    @State private var timeRemaining: TimeInterval = 0
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
            // Header with name and controls
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(instance.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 8) {
                        Text(instance.useCycles ? "Cycles Mode" : "Regular Mode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        
                        if instance.intervalMinutes > 0 && instance.intervalSeconds > 0 {
                            Text("\(instance.intervalMinutes)m \(instance.intervalSeconds)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if instance.intervalMinutes > 0 {
                            Text("\(instance.intervalMinutes)m")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(instance.intervalSeconds)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if instance.useCycles && !instance.cyclePhases.isEmpty {
                            let orderedPhases = instance.orderedCyclePhases
                            if instance.currentCycleIndex < orderedPhases.count {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                
                                Text("\(orderedPhases[instance.currentCycleIndex].name)")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        
                        if let target = instance.targetIntervals {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            
                            Text("Target: \(target)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: onHide) {
                        Image(systemName: isShowingHidden ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.orange)
                    
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.red)
                }
            }
            
            // Interval counter display
            intervalCounterView
            
            // Countdown timer (only show when running)
            if instance.isRunning && !instance.isPaused {
                countdownTimerView
            }
            
            // Status and progress
            statusView
            
            // Cycle navigation controls (only show in cycles mode)
            if instance.useCycles && !instance.cyclePhases.isEmpty {
                cycleNavigationControls
            }
            
            // Time information
            timeInformationView
            
            // Controls
            HStack {
                Button(action: onToggle) {
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
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(instance.isRunning ? .blue : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            startCountdownTimer()
        }
        .onDisappear {
            stopCountdownTimer()
        }
    }
    
    private var countdownTimerView: some View {
        HStack {
            Image(systemName: "timer")
                .foregroundStyle(instance.isInRestPeriod ? .yellow : (timeRemaining <= 30 ? .red : .blue))
                .font(.caption)
            
            Text(instance.isInRestPeriod ? "Rest ends in: \(formatTimeRemaining(timeRemaining))" : "Next alert in: \(formatTimeRemaining(timeRemaining))")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(instance.isInRestPeriod ? .yellow : (timeRemaining <= 30 ? .red : .blue))
            
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            (instance.isInRestPeriod ? Color.yellow : (timeRemaining <= 30 ? Color.red : Color.blue)).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .animation(.easeInOut(duration: 0.3), value: timeRemaining <= 30)
    }
    
    private var statusView: some View {
        VStack(spacing: 8) {
            HStack {
                statusIndicator
                Spacer()
                if instance.isRunning || instance.isPaused {
                    timeInfo
                }
            }
            
            if instance.useCycles {
                cycleProgressView
                cycleSummaryView
            } else {
                regularProgressView
            }
        }
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(instance.isRunning ? .green : (instance.isPaused ? .orange : .gray))
                .frame(width: 8, height: 8)
            
            Text(instance.isRunning ? "Running" : (instance.isPaused ? "Paused" : "Stopped"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var timeInfo: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if !instance.startTime.isEmpty {
                Text("Started: \(instance.startTime)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if instance.isRunning && !instance.nextAlertTime.isEmpty {
                Text("Next: \(instance.nextAlertTime)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var cycleProgressView: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Cycle Progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                let cycleProgress = instance.getCurrentCycleProgress()
                let totalProgress = instance.getTotalCyclesProgress()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(cycleProgress.current)/\(cycleProgress.total)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("Cycle \(totalProgress.current)/\(totalProgress.total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            let progress = instance.getCurrentCycleProgress()
            ProgressView(value: Double(progress.current), total: Double(progress.total))
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
    }
    
    private var regularProgressView: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Intervals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(instance.counter)\(instance.targetIntervals.map { "/\($0)" } ?? "")")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    if instance.targetIntervals != nil {
                        Text("completed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("total completed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if let target = instance.targetIntervals {
                ProgressView(value: Double(instance.counter), total: Double(target))
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            }
        }
    }
    
    private var intervalCounterView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if instance.useCycles {
                    let cycleProgress = instance.getCurrentCycleProgress()
                    let _ = instance.getTotalCyclesProgress()
                    
                    Text("\(cycleProgress.current)/\(cycleProgress.total)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Text("Current Cycle Intervals")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(instance.counter)\(instance.targetIntervals.map { "/\($0)" } ?? "")")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Text("Intervals Completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if instance.useCycles {
                let totalProgress = instance.getTotalCyclesProgress()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Cycle \(totalProgress.current)/\(totalProgress.total)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                    
                    Text("Overall Progress")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let target = instance.targetIntervals {
                VStack(alignment: .trailing, spacing: 4) {
                    let percentage = target > 0 ? Int((Double(instance.counter) / Double(target)) * 100) : 0
                    Text("\(percentage)%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                    
                    Text("Complete")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var cycleSummaryView: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Cycle Phases")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            HStack(spacing: 4) {
                ForEach(Array(instance.orderedCyclePhases.enumerated()), id: \.element.id) { index, phase in
                    Text(phase.name)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            index == instance.currentCycleIndex ? .blue.opacity(0.2) : .gray.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                        .foregroundStyle(index == instance.currentCycleIndex ? .blue : .secondary)
                        .fontWeight(index == instance.currentCycleIndex ? .medium : .regular)
                }
                Spacer()
            }
        }
    }
    
    private var cycleNavigationControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Cycle Navigation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            HStack(spacing: 12) {
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
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    if instance.currentCycleIndex < instance.orderedCyclePhases.count {
                        Text(instance.orderedCyclePhases[instance.currentCycleIndex].name)
                            .font(.caption)
                            .fontWeight(.medium)
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
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var timeInformationView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Time Information")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Completed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    let completedMinutes = instance.getTotalTimeCompleted()
                    let hours = completedMinutes / 60
                    let minutes = completedMinutes % 60
                    
                    if hours > 0 {
                        Text("\(hours)h \(minutes)m")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    } else {
                        Text("\(minutes)m")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                }
                
                Spacer()
                
                if instance.useCycles {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Total Duration")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        
                        let totalMinutes = instance.getTotalCycleDuration()
                        let totalHours = totalMinutes / 60
                        let remainingMinutes = totalMinutes % 60
                        
                        if totalHours > 0 {
                            Text("\(totalHours)h \(remainingMinutes)m")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        } else {
                            Text("\(remainingMinutes)m")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Progress")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    if instance.useCycles {
                        let completedMinutes = instance.getTotalTimeCompleted()
                        let totalMinutes = instance.getTotalCycleDuration()
                        let percentage = totalMinutes > 0 ? Int((Double(completedMinutes) / Double(totalMinutes)) * 100) : 0
                        
                        Text("\(percentage)%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.purple)
                    } else if let target = instance.targetIntervals {
                        let percentage = target > 0 ? Int((Double(instance.counter) / Double(target)) * 100) : 0
                        Text("\(percentage)%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.purple)
                    } else {
                        Text("\(instance.counter)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.purple)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
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

struct NewAlertInstanceView: View {
    @Environment(\.dismiss) private var dismiss
    let alertManager: AlertManager
    
    @State private var alertName = ""
    @State private var intervalMinutes = 5
    @State private var intervalSeconds = 0
    @State private var restMinutes = 0
    @State private var restSeconds = 0
    @State private var workIntervalText = ""
    @State private var restIntervalText = ""
    @State private var useCycles = false
    @State private var targetIntervals: Int? = nil
    
    var body: some View {
        NavigationView {
            Form {
                Section("Basic Settings") {
                    TextField("Alert Name", text: $alertName)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interval Duration")
                            .font(.subheadline)
                        HStack {
                            TextField("0", text: Binding(
                                get: { String(intervalMinutes) },
                                set: { if let value = Int($0) { intervalMinutes = max(0, value) } else if $0.isEmpty { intervalMinutes = 0 } }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                            Text("min")
                            
                            TextField("0", text: Binding(
                                get: { String(intervalSeconds) },
                                set: { if let value = Int($0) { intervalSeconds = max(0, min(59, value)) } else if $0.isEmpty { intervalSeconds = 0 } }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                            Text("sec")
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rest Period (Optional)")
                            .font(.subheadline)
                        HStack {
                            TextField("0", text: Binding(
                                get: { String(restMinutes) },
                                set: { if let value = Int($0) { restMinutes = max(0, value) } else if $0.isEmpty { restMinutes = 0 } }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                            Text("min")
                            
                            TextField("0", text: Binding(
                                get: { String(restSeconds) },
                                set: { if let value = Int($0) { restSeconds = max(0, min(59, value)) } else if $0.isEmpty { restSeconds = 0 } }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                            Text("sec")
                        }
                    }
                    
                    Toggle("Use Cycles", isOn: $useCycles)
                }
                
                Section("Speech Announcements (Optional)") {
                    TextField("Work interval text", text: $workIntervalText)
                    TextField("Rest period text", text: $restIntervalText)
                }
                
                if !useCycles {
                    Section("Target") {
                        HStack {
                            Text("Target Intervals")
                            Spacer()
                            TextField("Optional", value: Binding(
                                get: { targetIntervals ?? 0 },
                                set: { targetIntervals = $0 > 0 ? $0 : nil }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                        }
                    }
                }
            }
            .navigationTitle("New Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createAlert()
                        dismiss()
                    }
                    .disabled(alertName.isEmpty)
                }
            }
        }
    }
    
    private func createAlert() {
        let instance = AlertInstance(
            name: alertName,
            intervalMinutes: intervalMinutes,
            intervalSeconds: intervalSeconds,
            restMinutes: restMinutes,
            restSeconds: restSeconds,
            workIntervalText: workIntervalText,
            restIntervalText: restIntervalText,
            useCycles: useCycles,
            targetIntervals: targetIntervals
        )
        alertManager.addAlert(instance)
    }
}

#Preview {
    AlertManagerView()
        .environmentObject(AlertManager())
        .modelContainer(for: [AlertInstance.self, CyclePhase.self], inMemory: true)
}