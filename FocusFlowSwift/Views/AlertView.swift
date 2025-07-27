import SwiftUI
import SwiftData
import AVFoundation

struct AlertView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AlertSettings]
    @State private var timer: Timer?
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var nextAlertDate = Date()
    
    private var currentSettings: AlertSettings {
        if settings.isEmpty {
            let newSettings = AlertSettings()
            modelContext.insert(newSettings)
            return newSettings
        }
        return settings[0]
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                counterView
                if currentSettings.isPlaying {
                    alertInfoView
                }
                controlsView
            }
            .padding()
            .navigationTitle("Voice Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { 
                startTimerIfNeeded() 
                // Ensure audio session stays active
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            .onDisappear { 
                // Don't invalidate timer when view disappears - keep alerts running
            }
            .onChange(of: currentSettings.isPlaying) { _, newValue in
                if newValue { startTimerIfNeeded() } else { timer?.invalidate() }
            }
            .onChange(of: currentSettings.intervalMinutes) { _, _ in
                if currentSettings.isPlaying { startTimerIfNeeded() }
            }
        }
    }
    
    private var counterView: some View {
        VStack(spacing: 12) {
            Text("\(currentSettings.counter)\(currentSettings.targetIntervals.map { "/\($0)" } ?? "")")
                .font(.system(size: 48, weight: .bold, design: .rounded))
            
            Text("Intervals Completed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if let target = currentSettings.targetIntervals {
                ProgressView(value: Double(currentSettings.counter), total: Double(target))
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            }
        }
    }
    
    private var alertInfoView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.blue)
                Text("Every \(currentSettings.intervalMinutes) minutes")
                Spacer()
            }
            
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
                Text("Next: \(currentSettings.nextAlertTime)")
                Spacer()
            }
        }
        .font(.caption)
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var controlsView: some View {
        VStack(spacing: 16) {
            Toggle(isOn: Binding(
                get: { currentSettings.isPlaying },
                set: { newValue in
                    currentSettings.isPlaying = newValue
                    currentSettings.isPaused = false
                    if newValue {
                        currentSettings.intervalsComplete = false
                        startTimerIfNeeded()
                    } else {
                        timer?.invalidate()
                    }
                    try? modelContext.save()
                }
            )) {
                Text(currentSettings.isPlaying ? "Stop Alerts" : "Start Alerts")
            }
            
            HStack {
                Text("Interval:")
                Spacer()
                TextField("Minutes", value: Binding(
                    get: { currentSettings.intervalMinutes },
                    set: { currentSettings.intervalMinutes = max(1, $0); try? modelContext.save() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                Text("min")
            }
            
            HStack {
                Text("Target:")
                Spacer()
                TextField("Optional", value: Binding(
                    get: { currentSettings.targetIntervals ?? 0 },
                    set: { currentSettings.targetIntervals = $0 > 0 ? $0 : nil; try? modelContext.save() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                Text("intervals")
            }
            
            HStack {
                Button("Reset") {
                    currentSettings.counter = 0
                    currentSettings.intervalsComplete = false
                    try? modelContext.save()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Clear") {
                    currentSettings.isPlaying = false
                    timer?.invalidate()
                    currentSettings.intervalMinutes = 5
                    currentSettings.targetIntervals = nil
                    try? modelContext.save()
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private func startTimerIfNeeded() {
        timer?.invalidate()
        guard currentSettings.isPlaying else { return }
        
        // Ensure audio session is active
        try? AVAudioSession.sharedInstance().setActive(true)
        
        nextAlertDate = Date().addingTimeInterval(TimeInterval(currentSettings.intervalMinutes * 60))
        updateNextAlertTime()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            updateNextAlertTime()
            if Date() >= nextAlertDate {
                playSound()
                nextAlertDate = Date().addingTimeInterval(TimeInterval(currentSettings.intervalMinutes * 60))
            }
        }
        
        // Keep timer running in background
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    private func playSound() {
        currentSettings.counter += 1
        
        if let target = currentSettings.targetIntervals, currentSettings.counter >= target {
            currentSettings.intervalsComplete = true
            currentSettings.isPlaying = false
            timer?.invalidate()
        }
        
        // Ensure audio session is active before playing
        try? AVAudioSession.sharedInstance().setActive(true)
        
        let utterance = AVSpeechUtterance(string: "Interval \(currentSettings.counter)")
        utterance.rate = 0.5
        utterance.volume = 1.0
        
        // Stop any current speech and play new one
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        speechSynthesizer.speak(utterance)
        NotificationManager.shared.scheduleIntervalNotification(counter: currentSettings.counter)
        try? modelContext.save()
    }
    
    private func updateNextAlertTime() {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        currentSettings.nextAlertTime = formatter.string(from: nextAlertDate)
    }
}