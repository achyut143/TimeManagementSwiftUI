import Foundation
import os.log
import AVFoundation
import SwiftData
import ActivityKit
import WidgetKit
import UIKit

class AlertSettings: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AlertSettings()
    private let logger = Logger(subsystem: "FocusFlowSwift", category: "AlertSettings")
    private var isUpdatingCycleCount = false
    
    @Published var isPlaying: Bool = false {
        didSet { logger.info("isPlaying changed: \(oldValue) -> \(self.isPlaying)") }
    }
    @Published var isSimple: Bool = false {
        didSet { logger.info("isSimple changed: \(oldValue) -> \(self.isSimple)") }
    }
    @Published var isPaused: Bool = false {
        didSet { 
            logger.info("isPaused changed: \(oldValue) -> \(self.isPaused)")
            if isPaused {
                logger.info("Alerts paused - cycle progress preserved")
            }
        }
    }
    @Published var intervalMinutes: Int = 5 {
        didSet { logger.info("intervalMinutes changed: \(oldValue) -> \(self.intervalMinutes)") }
    }
    @Published var intervalSeconds: Int = 0 {
        didSet { logger.info("intervalSeconds changed: \(oldValue) -> \(self.intervalSeconds)") }
    }
    @Published var restMinutes: Int = 0 {
        didSet { logger.info("restMinutes changed: \(oldValue) -> \(self.restMinutes)") }
    }
    @Published var restSeconds: Int = 0 {
        didSet { logger.info("restSeconds changed: \(oldValue) -> \(self.restSeconds)") }
    }
    @Published var isInRestPeriod: Bool = false {
        didSet { logger.info("isInRestPeriod changed: \(oldValue) -> \(self.isInRestPeriod)") }
    }
    @Published var workIntervalText: String = "" {
        didSet { logger.info("workIntervalText changed: '\(oldValue)' -> '\(self.workIntervalText)'") }
    }
    @Published var restIntervalText: String = "" {
        didSet { logger.info("restIntervalText changed: '\(oldValue)' -> '\(self.restIntervalText)'") }
    }
    @Published var counter: Int = 0 {
        didSet { logger.info("counter changed: \(oldValue) -> \(self.counter)") }
    }
    @Published var targetIntervals: Int? = nil {
        didSet { logger.info("targetIntervals changed: \(String(describing: oldValue)) -> \(String(describing: self.targetIntervals))") }
    }
    @Published var intervalsComplete: Bool = false {
        didSet { logger.info("intervalsComplete changed: \(oldValue) -> \(self.intervalsComplete)") }
    }
    @Published var startTime: String = "" {
        didSet { logger.info("startTime changed: '\(oldValue)' -> '\(self.startTime)'") }
    }
    @Published var nextAlertTime: String = "" {
        didSet { logger.info("nextAlertTime changed: '\(oldValue)' -> '\(self.nextAlertTime)'") }
    }
    @Published var nextAlertDate: Date = Date() {
        didSet { logger.info("nextAlertDate changed: \(oldValue) -> \(self.nextAlertDate)") }
    }
    @Published var positionX: Double = 20 {
        didSet { logger.info("positionX changed: \(oldValue) -> \(self.positionX)") }
    }
    @Published var positionY: Double = 20 {
        didSet { logger.info("positionY changed: \(oldValue) -> \(self.positionY)") }
    }
    @Published var isMinimized: Bool = false {
        didSet { logger.info("isMinimized changed: \(oldValue) -> \(self.isMinimized)") }
    }
    
    // Active task name (set by DailyNotesView auto-scheduler, read by global banner)
    @Published var activeTaskName: String = ""

    // Cycles functionality
    @Published var numberOfCycles: Int = 1 {
        didSet { 
            logger.info("numberOfCycles changed: \(oldValue) -> \(self.numberOfCycles)")
            if numberOfCycles != oldValue && !isUpdatingCycleCount {
                setupDefaultCycles()
            }
        }
    }
    @Published var currentCycleConfiguration: CycleConfiguration? = nil {
        didSet { 
            logger.info("currentCycleConfiguration changed")
            if let config = currentCycleConfiguration {
                loadCycleConfiguration(config)
            }
        }
    }
    @Published var cyclePhases: [CyclePhase] = [] {
        didSet { logger.info("cyclePhases changed, count: \(self.cyclePhases.count)") }
    }
    @Published var currentCycleIndex: Int = 0 {
        didSet { logger.info("currentCycleIndex changed: \(oldValue) -> \(self.currentCycleIndex)") }
    }
    @Published var useCycles: Bool = false {
        didSet { 
            logger.info("useCycles changed: \(oldValue) -> \(self.useCycles)")
            if useCycles {
                // Clear target intervals when switching to cycles mode
                targetIntervals = nil
                if cyclePhases.isEmpty {
                    setupDefaultCycles()
                }
                shouldResetCyclesOnStart = true
            }
        }
    }
    @Published var shouldResetCyclesOnStart: Bool = true {
        didSet { logger.info("shouldResetCyclesOnStart changed: \(oldValue) -> \(self.shouldResetCyclesOnStart)") }
    }
    @Published var childLockEnabled: Bool = false {
        didSet { logger.info("childLockEnabled changed: \(oldValue) -> \(self.childLockEnabled)") }
    }
    @Published var pausedTimeRemaining: TimeInterval = 0 {
        didSet { logger.info("pausedTimeRemaining changed: \(oldValue) -> \(self.pausedTimeRemaining)") }
    }
    
    // Pause/Resume state management
    private var pausedAt: Date?
    
    private var timer: Timer?
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    @available(iOS 16.1, *)
    var liveActivityManager: LiveActivityManager {
        LiveActivityManager.shared
    }
    
    private override init() {
        super.init()
        logger.info("AlertSettings initialized")
        setupDefaultCycles()
        migrateCyclePhaseOrders()
        
        // Listen for Live Activity state changes
        if #available(iOS 16.1, *) {
            NotificationCenter.default.addObserver(
                forName: .liveActivityEnded,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleLiveActivityEnded()
            }
            
            NotificationCenter.default.addObserver(
                forName: .liveActivityStarted,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.logger.info("Live Activity started")
            }
            
            // Listen for app becoming active to refresh Live Activity
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshLiveActivityOnAppActive()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func migrateCyclePhaseOrders() {
        // Ensure all cycle phases have order values for migration compatibility
        for (index, phase) in cyclePhases.enumerated() {
            if phase.order == nil {
                phase.order = index
                logger.info("Migrated CyclePhase '\(phase.name)' to order \(index)")
            }
        }
    }
    
    func scheduleIntervalTimer() {
        timer?.invalidate()
        guard isPlaying else { 
            logger.info("Not scheduling timer - isPlaying is false")
            return 
        }
        
        // Validate interval duration
        let intervalTotalSeconds = intervalMinutes * 60 + intervalSeconds
        guard intervalTotalSeconds > 0 else {
            logger.error("Invalid interval duration: must be greater than 0")
            isPlaying = false
            return
        }
        
        // Set start time when timer begins
        if startTime.isEmpty {
            updateStartTime()
        }
        
        // Handle pause/resume logic
        var interval: TimeInterval
        if let _ = pausedAt, pausedTimeRemaining > 0 {
            // Resuming from pause - use the stored remaining time
            interval = pausedTimeRemaining
            nextAlertDate = Date().addingTimeInterval(interval)
            logger.info("Resuming from pause with \(interval) seconds remaining")
            // Clear pause state
            self.pausedAt = nil
            self.pausedTimeRemaining = 0
        } else {
            // Starting fresh or continuing normally
            interval = nextAlertDate.timeIntervalSinceNow
            if interval <= 0 {
                let totalSeconds = isInRestPeriod ? 
                    TimeInterval(restMinutes * 60 + restSeconds) : 
                    TimeInterval(intervalMinutes * 60 + intervalSeconds)
                nextAlertDate = Date().addingTimeInterval(totalSeconds)
                interval = totalSeconds
            }
        }
        
        updateNextAlertTime()
        
        let nextInterval = nextAlertDate.timeIntervalSinceNow
        logger.info("Scheduling timer for \(nextInterval) seconds (\(nextInterval/60) minutes) - Rest period: \(self.isInRestPeriod)")
        timer = Timer.scheduledTimer(withTimeInterval: nextInterval, repeats: false) { [weak self] _ in
            self?.handleAlertFire()
        }
        RunLoop.current.add(timer!, forMode: .common)
        
        // Start or update Live Activity
        if #available(iOS 16.1, *) {
            // Small delay to ensure everything is set up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.updateLiveActivity()
            }
        }
    }
    
    private func handleAlertFire() {
        // Check if we're in rest period
        if isInRestPeriod {
            // Rest period is over, start next interval
            isInRestPeriod = false
            logger.info("🔔 Rest period ended, starting next interval")
            
            // Announce work interval starting
            playWorkIntervalSound()
            
            // Schedule next interval
            let totalSeconds = TimeInterval(intervalMinutes * 60 + intervalSeconds)
            self.nextAlertDate = Date().addingTimeInterval(totalSeconds)
            self.updateNextAlertTime()
            self.scheduleIntervalTimer()
            
            // Update Live Activity
            if #available(iOS 16.1, *) {
                self.updateLiveActivity()
            }
            
            // Post notification
            NotificationCenter.default.post(name: .intervalAlert, object: nil)
            return
        }
        
        self.counter += 1
        logger.info("🔔 Alert fired! Counter: \(self.counter)")
        print("🔔 Alert fired! New counter: \(self.counter)")
        
        // Immediately update Live Activity with new counter
        if #available(iOS 16.1, *) {
            print("🔄 Immediate Live Activity update - Counter: \(self.counter)")
            self.updateLiveActivity()
        }
        
        // Handle cycles logic
        if self.useCycles && !self.cyclePhases.isEmpty {
            let orderedPhases = self.orderedCyclePhases
            logger.info("Using cycles. Current cycle index: \(self.currentCycleIndex), Total cycles: \(orderedPhases.count)")
            
            guard self.currentCycleIndex < orderedPhases.count else { 
                // All cycles are already complete, stop alerts
                logger.info("All cycles complete - stopping alerts")
                self.intervalsComplete = true
                self.isPlaying = false
                self.timer?.invalidate()
                self.timer = nil
                self.playSound()
                // Post notification once at the end
                NotificationCenter.default.post(name: .intervalAlert, object: nil)
                return 
            }
            
            orderedPhases[self.currentCycleIndex].currentIntervals += 1
            
            let currentPhase = orderedPhases[self.currentCycleIndex]
            let totalIntervalsForPhase = currentPhase.totalIntervals(intervalMinutes: self.intervalMinutes)
            
            logger.info("Current phase: \(currentPhase.name), intervals: \(currentPhase.currentIntervals)/\(totalIntervalsForPhase)")
            
            // Check if current cycle phase is complete
            if currentPhase.currentIntervals >= totalIntervalsForPhase {
                // Move to next cycle
                self.currentCycleIndex += 1
                logger.info("Cycle phase complete! Moving to cycle index: \(self.currentCycleIndex)")
                
                // Check if all cycles are complete
                if self.currentCycleIndex >= orderedPhases.count {
                    logger.info("All cycles complete - stopping alerts")
                    self.intervalsComplete = true
                    self.isPlaying = false
                    self.shouldResetCyclesOnStart = true  // Reset cycles on next start
                    self.timer?.invalidate()
                    self.timer = nil
                    self.playSound()
                    // Post notification once at the end
                    NotificationCenter.default.post(name: .intervalAlert, object: nil)
                    return
                }
            }
        }
        
        // Play speech sound
        self.playSound()
        
        // Check target intervals (applies to both cycle and non-cycle modes)
        logger.info("Checking target intervals: targetIntervals=\(String(describing: self.targetIntervals)), counter=\(self.counter)")
        if let target = self.targetIntervals, self.counter >= target {
            logger.info("Target intervals reached: \(self.counter)/\(target) - stopping alerts")
            self.intervalsComplete = true
            self.isPlaying = false
            self.timer?.invalidate()
            self.timer = nil
        } else {
            // Check if we should start a rest period
            let hasRestPeriod = restMinutes > 0 || restSeconds > 0
            if hasRestPeriod {
                isInRestPeriod = true
                let totalRestSeconds = TimeInterval(restMinutes * 60 + restSeconds)
                self.nextAlertDate = Date().addingTimeInterval(totalRestSeconds)
                logger.info("Starting rest period for \(totalRestSeconds) seconds")
            } else {
                // Continue with next interval
                let totalSeconds = TimeInterval(self.intervalMinutes * 60 + self.intervalSeconds)
                self.nextAlertDate = Date().addingTimeInterval(totalSeconds)
            }
            
            self.updateNextAlertTime()
            self.scheduleIntervalTimer()
            logger.info("Scheduled next alert for: \(self.nextAlertTime)")
            
            // Update Live Activity with new interval - single update only
            if #available(iOS 16.1, *) {
                print("🔄 About to update Live Activity with counter: \(self.counter)")
                self.updateLiveActivity()
            }
        }
        
        // Post notification once at the end for all cases
        NotificationCenter.default.post(name: .intervalAlert, object: nil)
    }
    
    private func getCurrentNotificationMessage() -> String {
        var message = "Interval \(counter + 1)"
        
        if useCycles && !cyclePhases.isEmpty {
            let orderedPhases = orderedCyclePhases
            if currentCycleIndex < orderedPhases.count {
                let currentPhase = orderedPhases[currentCycleIndex]
                let nextIntervalForPhase = currentPhase.currentIntervals + 1
                message = "\(currentPhase.name) - Interval \(nextIntervalForPhase)"
            }
        }
        
        return message
    }
    
    private func playSound() {
        // Use mixWithOthers option to allow speech to play alongside other audio (like podcasts)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        
        var message = ""
        
        // Check if we're about to start a rest period and have custom rest text
        let hasRestPeriod = restMinutes > 0 || restSeconds > 0
        let hasCustomRestText = !restIntervalText.trimmingCharacters(in: .whitespaces).isEmpty
        let hasCustomWorkText = !workIntervalText.trimmingCharacters(in: .whitespaces).isEmpty
        
        if hasRestPeriod && hasCustomRestText {
            // Use custom rest text instead of default message
            message = restIntervalText
        } else if hasCustomWorkText {
            // Use custom work text for regular intervals
            message = workIntervalText
        } else {
            // Use default interval message
            message = "Interval \(counter)"
            
            if useCycles && !cyclePhases.isEmpty {
                let orderedPhases = orderedCyclePhases
                if currentCycleIndex < orderedPhases.count {
                    let currentPhase = orderedPhases[currentCycleIndex]
                    message = "\(currentPhase.name) - Interval \(currentPhase.currentIntervals)"
                }
            }
        }
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.5
        utterance.volume = 0.8  // Slightly lower volume to be less intrusive
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Set up speech synthesizer delegate to restore audio session after speech
        speechSynthesizer.delegate = self
        speechSynthesizer.speak(utterance)
    }
    
    private func playWorkIntervalSound() {
        // Only speak if custom work text is provided
        guard !workIntervalText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        // Use mixWithOthers option to allow speech to play alongside other audio (like podcasts)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        
        let message = workIntervalText
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.5
        utterance.volume = 0.8
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        speechSynthesizer.delegate = self
        speechSynthesizer.speak(utterance)
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Restore audio session to allow other apps to resume their audio
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
    
    func stopTimer() {
        // Store remaining time if we're pausing (not stopping completely)
        if isPaused && isPlaying {
            self.pausedTimeRemaining = max(0, nextAlertDate.timeIntervalSinceNow)
            self.pausedAt = Date()
            logger.info("Pausing timer with \(self.pausedTimeRemaining) seconds remaining")
        } else {
            // Clear pause state when stopping completely
            self.pausedTimeRemaining = 0
            self.pausedAt = nil
        }
        
        timer?.invalidate()
        timer = nil
        
        // End Live Activity
        if #available(iOS 16.1, *) {
            if intervalsComplete {
                liveActivityManager.endActivityWithCompletion()
            } else {
                liveActivityManager.endCurrentActivity()
            }
        }
    }
    
    @available(iOS 16.1, *)
    func handleLiveActivityEnded() {
        // Timer will continue to handle alerts
    }
    
    @available(iOS 16.1, *)
    private func refreshLiveActivityOnAppActive() {
        // Force refresh Live Activity when app becomes active
        if isPlaying && liveActivityManager.isActivityActive {
            logger.info("🔄 App became active - refreshing Live Activity")
            
            // Small delay to ensure app is fully active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.updateLiveActivity()
            }
        }
    }
    
    @available(iOS 16.1, *)
    func forceRefreshLiveActivity() {
        // Public method to force refresh Live Activity
        liveActivityManager.debugActivityState()
        
        if isPlaying {
            logger.info("🔄 Force refreshing Live Activity - Counter: \(self.counter)")
            
            // Always use restart strategy for force refresh
            logger.info("🔄 Using force restart strategy")
            forceRestartLiveActivity()
        } else {
            logger.info("⚠️ Cannot refresh - not playing")
        }
    }
    
    @available(iOS 16.1, *)
    func debugLiveActivityState() {
        logger.info("🔍 Live Activity Debug State:")
        logger.info("- Is Playing: \(self.isPlaying)")
        logger.info("- Counter: \(self.counter)")
        logger.info("- Target Intervals: \(String(describing: self.targetIntervals))")
        logger.info("- Next Alert: \(self.nextAlertDate)")
        logger.info("- Is Real Device: \(self.isRunningOnRealDevice)")
        
        liveActivityManager.debugActivityState()
        
        print("🔍 Debug Summary - Counter: \(self.counter), Playing: \(self.isPlaying), Active: \(self.liveActivityManager.isActivityActive)")
    }
    
    @available(iOS 16.1, *)
    private func forceRestartLiveActivity() {
        let intervalName = getCurrentIntervalName()
        let cycleInfo = getCurrentCycleInfo()
        
        // End current activity
        liveActivityManager.endCurrentActivity()
        
        // Restart after brief delay with current state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.liveActivityManager.startFocusActivity(
                intervalDuration: self.intervalMinutes,
                currentInterval: self.counter,
                totalIntervals: self.targetIntervals,
                intervalName: intervalName,
                nextAlertTime: self.nextAlertDate,
                isInCycleMode: self.useCycles,
                currentCycleName: cycleInfo.cycleName,
                cycleProgress: cycleInfo.progress
            )
            self.logger.info("🔄 Restarted Live Activity with current interval: \(self.counter)")
        }
    }
    
    // Helper method to detect if running on real device vs simulator
    private var isRunningOnRealDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
    
    // Method to check Live Activity availability for user feedback
    @available(iOS 16.1, *)
    func getLiveActivityStatus() -> String {
        let authInfo = ActivityAuthorizationInfo()
        
        if !authInfo.areActivitiesEnabled {
            if isRunningOnRealDevice {
                return "Live Activities not available on this device with free developer account. Using notifications instead."
            } else {
                return "Live Activities not enabled. Please enable in Settings."
            }
        }
        
        if liveActivityManager.isActivityActive {
            return "Live Activity is active and updating."
        } else {
            return "Live Activity ready to start."
        }
    }
    
    // MARK: - Cycles functionality
    
    func setupDefaultCycles() {
        cyclePhases = []
        for i in 1...numberOfCycles {
            let defaultMinutes = i == 1 ? 30 : (i % 2 == 0 ? 10 : 30)
            cyclePhases.append(CyclePhase(name: "Cycle \(i)", totalMinutes: defaultMinutes, order: i - 1))
        }
    }
    
    func updateCycleCount() {
        isUpdatingCycleCount = true
        numberOfCycles = cyclePhases.count
        isUpdatingCycleCount = false
    }
    
    func loadCycleConfiguration(_ configuration: CycleConfiguration) {
        // Use orderedCycles to maintain proper sequence
        cyclePhases = configuration.orderedCycles.map { phase in
            let newPhase = CyclePhase(name: phase.name, totalMinutes: phase.totalMinutes, order: phase.order ?? 0)
            newPhase.reset()
            return newPhase
        }
        updateCycleCount()
        resetAllCycles()
    }
    
    func createCycleConfiguration(name: String, context: ModelContext) {
        // Use orderedCyclePhases to preserve the current order
        let orderedPhases = orderedCyclePhases
        
        // Create new cycle phases for the configuration to avoid reference issues
        // Preserve the current order by using the ordered phases
        let configCycles = orderedPhases.enumerated().map { index, phase in
            CyclePhase(name: phase.name, totalMinutes: phase.totalMinutes, order: index)
        }
        
        let configuration = CycleConfiguration(name: name, cycles: configCycles)
        context.insert(configuration)
        try? context.save()
    }
    
    func resetAllCycles() {
        currentCycleIndex = 0
        for phase in cyclePhases {
            phase.reset()
        }
        // Clear pause state when resetting
        pausedTimeRemaining = 0
        pausedAt = nil
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
        // Migrate any phases without order values
        for (index, phase) in cyclePhases.enumerated() {
            if phase.order == nil {
                phase.order = index
            }
        }
        return cyclePhases.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
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
        if isPlaying {
            nextAlertDate = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))
            scheduleIntervalTimer()
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
        if isPlaying {
            nextAlertDate = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))
            scheduleIntervalTimer()
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
    
    func clearPauseState() {
        pausedTimeRemaining = 0
        pausedAt = nil
        logger.info("Pause state cleared")
    }
    
    // MARK: - Live Activity Integration
    
    @available(iOS 16.1, *)
    private func updateLiveActivity() {
        let intervalName = getCurrentIntervalName()
        let cycleInfo = getCurrentCycleInfo()
        
        logger.info("🔍 updateLiveActivity called - Counter: \(self.counter), isPlaying: \(self.isPlaying), isActivityActive: \(self.liveActivityManager.isActivityActive), currentActivity exists: \(self.liveActivityManager.currentActivity != nil)")
        
        if liveActivityManager.isActivityActive && liveActivityManager.currentActivity != nil {
            // Normal update with enhanced logging
            logger.info("📱 Updating Live Activity - Interval: \(self.counter), Device: \(self.isRunningOnRealDevice ? "Real" : "Simulator")")
            
            liveActivityManager.updateFocusActivity(
                currentInterval: counter,
                totalIntervals: targetIntervals,
                intervalName: intervalName,
                nextAlertTime: nextAlertDate,
                isInCycleMode: useCycles,
                currentCycleName: cycleInfo.cycleName,
                cycleProgress: cycleInfo.progress,
                isPaused: isPaused
            )
            
            logger.info("✅ Live Activity update requested - Counter: \(self.counter), Next Alert: \(self.nextAlertDate)")
        } else if isPlaying {
            // Try to start Live Activity, but continue even if it fails
            logger.info("🚀 Starting new Live Activity - Interval: \(self.counter)")
            
            liveActivityManager.startFocusActivity(
                intervalDuration: intervalMinutes,
                currentInterval: counter,
                totalIntervals: targetIntervals,
                intervalName: intervalName,
                nextAlertTime: nextAlertDate,
                isInCycleMode: useCycles,
                currentCycleName: cycleInfo.cycleName,
                cycleProgress: cycleInfo.progress
            )
            
            logger.info("🎯 Live Activity start requested - Counter: \(self.counter)")
        }
        
        // Always schedule notifications as backup for real devices
        scheduleBackupNotification()
    }
    
    /// Public entry point so views can force a Live Activity refresh after
    /// manually changing nextAlertDate / currentTaskName without a timer fire.
    @available(iOS 16.1, *)
    func refreshLiveActivity() {
        updateLiveActivity()
    }

    private func scheduleBackupNotification() {
        // Schedule enhanced notifications for real device reliability
        let remainingTime = nextAlertDate.timeIntervalSinceNow
        if remainingTime > 0 {
            let intervalName = getCurrentIntervalName()
            
            logger.info("Timer scheduled for real device - Interval \(self.counter + 1)")
        }
    }
    
    @available(iOS 16.1, *)
    func pauseLiveActivity() {
        liveActivityManager.pauseFocusActivity()
    }
    
    @available(iOS 16.1, *)
    func resumeLiveActivity() {
        liveActivityManager.resumeFocusActivity(nextAlertTime: nextAlertDate)
    }
    
    private func getCurrentIntervalName() -> String {
        if useCycles && !cyclePhases.isEmpty {
            let orderedPhases = orderedCyclePhases
            if currentCycleIndex < orderedPhases.count {
                let currentPhase = orderedPhases[currentCycleIndex]
                let intervalInPhase = currentPhase.currentIntervals + 1
                return "\(currentPhase.name) - Interval \(intervalInPhase)"
            }
        }
        return "Focus Interval \(counter + 1)"
    }
    
    private func getCurrentCycleInfo() -> (cycleName: String?, progress: String?) {
        guard useCycles && !cyclePhases.isEmpty else {
            return (nil, nil)
        }
        
        let orderedPhases = orderedCyclePhases
        guard currentCycleIndex < orderedPhases.count else {
            return (nil, nil)
        }
        
        let currentPhase = orderedPhases[currentCycleIndex]
        let totalProgress = getTotalCyclesProgress()
        
        return (
            cycleName: currentPhase.name,
            progress: "\(totalProgress.current)/\(totalProgress.total)"
        )
    }
}