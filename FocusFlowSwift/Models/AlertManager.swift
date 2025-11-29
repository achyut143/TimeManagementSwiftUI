import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import UIKit
import os.log

class AlertManager: ObservableObject {
    @Published var alertInstances: [AlertInstance] = []
    private let logger = Logger(subsystem: "FocusFlowSwift", category: "AlertManager")
    var modelContext: ModelContext?
    private var isInitialized = false
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        if modelContext != nil {
            loadAlertInstances()
        }
    }
    
    func loadAlertInstances() {
        guard let modelContext = modelContext, !isInitialized else { return }
        
        do {
            let descriptor = FetchDescriptor<AlertInstance>()
            let loadedInstances = try modelContext.fetch(descriptor)
            
            // Restore running state for instances that were running
            for instance in loadedInstances {
                if instance.isRunning {
                    // Check if we need to catch up on missed alerts
                    let now = Date()
                    if now >= instance.nextAlertDate {
                        // We missed alerts while the app was closed
                        instance.handleAlertFire()
                    } else {
                        // Restart the timer normally
                        instance.scheduleNextAlert()
                    }
                }
            }
            
            alertInstances = loadedInstances
            isInitialized = true
            logger.info("Loaded \(self.alertInstances.count) alert instances")
        } catch {
            logger.error("Failed to load alert instances: \(error.localizedDescription)")
        }
    }
    
    private func saveContext() {
        guard let modelContext = modelContext else { return }
        
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")
        }
    }
    
    var activeCount: Int {
        alertInstances.filter { $0.isRunning }.count
    }
    
    var pausedCount: Int {
        alertInstances.filter { $0.isPaused }.count
    }
    
    func addAlert(_ instance: AlertInstance) {
        alertInstances.append(instance)
        modelContext?.insert(instance)
        saveContext()
        logger.info("Added new alert instance: \(instance.name)")
    }
    
    func removeAlert(_ instance: AlertInstance) {
        instance.stop()
        alertInstances.removeAll { $0.id == instance.id }
        modelContext?.delete(instance)
        saveContext()
        logger.info("Removed alert instance: \(instance.name)")
    }
    
    func toggleAlert(_ instance: AlertInstance) {
        if instance.isRunning {
            instance.pause()
        } else {
            instance.start()
        }
    }
    
    func pauseAll() {
        for instance in alertInstances where instance.isRunning {
            instance.pause()
        }
        logger.info("Paused all active alerts")
    }
    
    func resumeAll() {
        for instance in alertInstances where instance.isPaused {
            instance.start()
        }
        logger.info("Resumed all paused alerts")
    }
    
    func hideAlert(_ instance: AlertInstance) {
        instance.isHidden = true
        saveContext()
        logger.info("Hidden alert instance: \(instance.name)")
    }
    
    func showAlert(_ instance: AlertInstance) {
        instance.isHidden = false
        saveContext()
        logger.info("Shown alert instance: \(instance.name)")
    }
    
    var visibleAlerts: [AlertInstance] {
        alertInstances.filter { !$0.isHidden }
    }
    
    var hiddenAlerts: [AlertInstance] {
        alertInstances.filter { $0.isHidden }
    }
    
    func handleAppLifecycleChange(isActive: Bool) {
        for instance in alertInstances {
            if isActive {
                instance.handleAppDidBecomeActive()
            } else {
                instance.handleAppWillResignActive()
            }
        }
    }
    
    func stopAll() {
        for instance in alertInstances {
            instance.stop()
        }
        logger.info("Stopped all alerts")
    }
}

@Model
class AlertInstance: Identifiable {
    @Transient var id = UUID()
    @Transient private var logger = Logger(subsystem: "FocusFlowSwift", category: "AlertInstance")
    
    var name: String
    var intervalMinutes: Int
    var intervalSeconds: Int = 0
    var restMinutes: Int = 0
    var restSeconds: Int = 0
    var isInRestPeriod: Bool = false
    var workIntervalText: String = ""
    var restIntervalText: String = ""
    var useCycles: Bool
    var targetIntervals: Int?
    var isHidden: Bool = false
    
    var isRunning: Bool = false
    var isPaused: Bool = false
    var counter: Int = 0
    var startTime: String = ""
    var nextAlertTime: String = ""
    var nextAlertDate: Date = Date()
    
    // Cycle-specific properties
    var cyclePhases: [CyclePhase] = []
    var currentCycleIndex: Int = 0
    
    @Transient private var timer: Timer?
    @Transient private var speechSynthesizer = AVSpeechSynthesizer()
    @Transient private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    init(name: String, intervalMinutes: Int, intervalSeconds: Int = 0, restMinutes: Int = 0, restSeconds: Int = 0, workIntervalText: String = "", restIntervalText: String = "", useCycles: Bool, targetIntervals: Int? = nil) {
        self.name = name
        self.intervalMinutes = intervalMinutes
        self.intervalSeconds = intervalSeconds
        self.restMinutes = restMinutes
        self.restSeconds = restSeconds
        self.workIntervalText = workIntervalText
        self.restIntervalText = restIntervalText
        self.useCycles = useCycles
        self.targetIntervals = targetIntervals
        self.id = UUID()
        self.logger = Logger(subsystem: "FocusFlowSwift", category: "AlertInstance")
        self.timer = nil
        self.speechSynthesizer = AVSpeechSynthesizer()
        self.backgroundTaskID = .invalid
        
        if useCycles {
            setupDefaultCycles()
        }
    }
    
    func start() {
        isRunning = true
        isPaused = false
        
        if startTime.isEmpty {
            updateStartTime()
        }
        
        // Start background task to keep timer running
        startBackgroundTask()
        scheduleNextAlert()
        logger.info("Started alert instance: \(self.name)")
    }
    
    func pause() {
        isRunning = false
        isPaused = true
        timer?.invalidate()
        timer = nil
        endBackgroundTask()
        logger.info("Paused alert instance: \(self.name)")
    }
    
    func stop() {
        isRunning = false
        isPaused = false
        timer?.invalidate()
        timer = nil
        endBackgroundTask()
        logger.info("Stopped alert instance: \(self.name)")
    }
    
    func reset() {
        stop()
        counter = 0
        startTime = ""
        nextAlertTime = ""
        currentCycleIndex = 0
        isInRestPeriod = false
        
        if useCycles {
            for phase in cyclePhases {
                phase.reset()
            }
        }
        
        logger.info("Reset alert instance: \(self.name)")
    }
    
    func scheduleNextAlert() {
        timer?.invalidate()
        
        let totalSeconds = isInRestPeriod ? 
            TimeInterval(restMinutes * 60 + restSeconds) : 
            TimeInterval(intervalMinutes * 60 + intervalSeconds)
        
        nextAlertDate = Date().addingTimeInterval(totalSeconds)
        updateNextAlertTime()
        
        let interval = max(nextAlertDate.timeIntervalSinceNow, 0.1) // Ensure positive interval
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleAlertFire()
            }
        }
        
        // Add to both common and default run loop modes for better reliability
        if let timer = timer {
            RunLoop.current.add(timer, forMode: .common)
            RunLoop.current.add(timer, forMode: .default)
        }
    }
    
    func handleAlertFire() {
        // Check if we're in rest period
        if isInRestPeriod {
            // Rest period is over, start next interval
            isInRestPeriod = false
            logger.info("Rest period ended for \(self.name), starting next interval")
            
            // Announce work interval starting (if custom text provided)
            playWorkIntervalSound()
            
            // Schedule next interval
            scheduleNextAlert()
            return
        }
        
        counter += 1
        logger.info("Alert fired for \(self.name)! Counter: \(self.counter)")
        
        // Handle cycles logic
        if useCycles && !cyclePhases.isEmpty {
            let orderedPhases = orderedCyclePhases
            
            guard currentCycleIndex < orderedPhases.count else {
                // All cycles complete
                stop()
                playCompletionSound()
                return
            }
            
            orderedPhases[currentCycleIndex].currentIntervals += 1
            let currentPhase = orderedPhases[currentCycleIndex]
            let totalIntervalsForPhase = currentPhase.totalIntervals(intervalMinutes: intervalMinutes)
            
            // Check if current cycle phase is complete
            if currentPhase.currentIntervals >= totalIntervalsForPhase {
                currentCycleIndex += 1
                
                // Check if all cycles are complete
                if currentCycleIndex >= orderedPhases.count {
                    stop()
                    playCompletionSound()
                    return
                }
            }
        }
        
        // Play alert sound
        playAlertSound()
        
        // Check target intervals
        if let target = targetIntervals, counter >= target {
            stop()
            playCompletionSound()
            return
        }
        
        // Schedule next alert if still running
        if isRunning {
            // Check if we should start a rest period
            let hasRestPeriod = restMinutes > 0 || restSeconds > 0
            if hasRestPeriod {
                isInRestPeriod = true
                logger.info("Starting rest period for \(self.name)")
            }
            scheduleNextAlert()
        }
    }
    
    private func getCurrentNotificationMessage() -> String {
        var message = "Interval \(counter + 1)"
        
        if useCycles && !cyclePhases.isEmpty {
            let orderedPhases = orderedCyclePhases
            if currentCycleIndex < orderedPhases.count {
                let currentPhase = orderedPhases[currentCycleIndex]
                message = "\(currentPhase.name) - Interval \(currentPhase.currentIntervals + 1)"
            }
        }
        
        return message
    }
    
    private func playAlertSound() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        
        var message = ""
        
        // Use custom work interval text if provided, otherwise use default
        if !workIntervalText.trimmingCharacters(in: .whitespaces).isEmpty {
            message = workIntervalText
        } else {
            message = "Interval \(counter)"
            
            if useCycles && !cyclePhases.isEmpty {
                let orderedPhases = orderedCyclePhases
                if currentCycleIndex < orderedPhases.count {
                    let currentPhase = orderedPhases[currentCycleIndex]
                    message = "\(currentPhase.name) - Interval \(currentPhase.currentIntervals)"
                }
            }
        }
        
        // Add rest period notification if configured and custom text is provided
        let hasRestPeriod = restMinutes > 0 || restSeconds > 0
        if hasRestPeriod && !restIntervalText.trimmingCharacters(in: .whitespaces).isEmpty {
            message += ". \(restIntervalText)"
        }
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.5
        utterance.volume = 0.8
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speechSynthesizer.speak(utterance)
    }
    
    private func playWorkIntervalSound() {
        // Only speak if custom work text is provided
        guard !workIntervalText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        
        let message = workIntervalText
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.5
        utterance.volume = 0.8
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speechSynthesizer.speak(utterance)
    }
    
    private func playCompletionSound() {
        let message = "\(name) completed!"
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.5
        utterance.volume = 1.0
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speechSynthesizer.speak(utterance)
    }
    
    private func updateNextAlertTime() {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        nextAlertTime = formatter.string(from: nextAlertDate)
    }
    
    private func updateStartTime() {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        startTime = formatter.string(from: Date())
    }
    
    // MARK: - Cycles functionality
    
    private func setupDefaultCycles() {
        cyclePhases = [
            CyclePhase(name: "Focus", totalMinutes: 25, order: 0),
            CyclePhase(name: "Break", totalMinutes: 5, order: 1),
            CyclePhase(name: "Focus", totalMinutes: 25, order: 2),
            CyclePhase(name: "Long Break", totalMinutes: 15, order: 3)
        ]
    }
    
    func skipToNextCycle() {
        guard useCycles && !cyclePhases.isEmpty else { return }
        
        let orderedPhases = orderedCyclePhases
        guard currentCycleIndex < orderedPhases.count - 1 else { return }
        
        // Mark current cycle as complete
        let currentPhase = orderedPhases[currentCycleIndex]
        let totalIntervalsForPhase = currentPhase.totalIntervals(intervalMinutes: intervalMinutes)
        currentPhase.currentIntervals = totalIntervalsForPhase
        
        // Move to next cycle
        currentCycleIndex += 1
        
        // If running, reschedule timer for new cycle
        if isRunning {
            scheduleNextAlert()
        }
        
        logger.info("Skipped to next cycle: \(orderedPhases[self.currentCycleIndex].name)")
    }
    
    func skipToPreviousCycle() {
        guard useCycles && !cyclePhases.isEmpty else { return }
        guard currentCycleIndex > 0 else { return }
        
        // Reset current cycle
        let orderedPhases = orderedCyclePhases
        orderedPhases[currentCycleIndex].reset()
        
        // Move to previous cycle
        currentCycleIndex -= 1
        
        // Reset the previous cycle's progress
        orderedPhases[currentCycleIndex].reset()
        
        // If running, reschedule timer for new cycle
        if isRunning {
            scheduleNextAlert()
        }
        
        logger.info("Skipped to previous cycle: \(orderedPhases[self.currentCycleIndex].name)")
    }
    
    func getTotalTimeCompleted() -> Int {
        guard useCycles && !cyclePhases.isEmpty else {
            // For regular mode, return total intervals * interval duration
            return counter * intervalMinutes
        }
        
        let orderedPhases = orderedCyclePhases
        var totalMinutes = 0
        
        // Add completed cycles
        for i in 0..<currentCycleIndex {
            if i < orderedPhases.count {
                totalMinutes += orderedPhases[i].totalMinutes
            }
        }
        
        // Add partial progress from current cycle
        if currentCycleIndex < orderedPhases.count {
            let currentPhase = orderedPhases[currentCycleIndex]
            let completedIntervals = currentPhase.currentIntervals
            totalMinutes += completedIntervals * intervalMinutes
        }
        
        return totalMinutes
    }
    
    func getTotalCycleDuration() -> Int {
        guard useCycles else { return 0 }
        return cyclePhases.reduce(0) { $0 + $1.totalMinutes }
    }
    
    func getCurrentCycleProgress() -> (current: Int, total: Int) {
        guard useCycles && !cyclePhases.isEmpty else {
            return (0, 0)
        }
        
        let orderedPhases = orderedCyclePhases
        guard currentCycleIndex < orderedPhases.count else {
            return (0, 0)
        }
        
        let currentPhase = orderedPhases[currentCycleIndex]
        let total = currentPhase.totalIntervals(intervalMinutes: intervalMinutes)
        return (currentPhase.currentIntervals, total)
    }
    
    func getTotalCyclesProgress() -> (current: Int, total: Int) {
        return (currentCycleIndex + 1, cyclePhases.count)
    }
    
    var orderedCyclePhases: [CyclePhase] {
        return cyclePhases.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }
    
    // MARK: - Background Task Management
    
    private func startBackgroundTask() {
        endBackgroundTask() // End any existing task
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "AlertTimer") { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    // MARK: - App State Management
    
    func handleAppDidBecomeActive() {
        // Restart timer if the alert should still be running
        if isRunning && !isPaused {
            // Check if we missed any alerts while in background
            let now = Date()
            if now >= nextAlertDate {
                // We missed an alert, fire it now
                handleAlertFire()
            } else {
                // Reschedule the timer
                scheduleNextAlert()
            }
        }
    }
    
    func handleAppWillResignActive() {
        // Keep the timer running but prepare for background
        if isRunning {
            startBackgroundTask()
        }
    }
    
    // MARK: - Lifecycle Management
    
    deinit {
        timer?.invalidate()
        endBackgroundTask()
    }
}