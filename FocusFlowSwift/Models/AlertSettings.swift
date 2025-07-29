import Foundation
import os.log
import AVFoundation

class AlertSettings: ObservableObject {
    static let shared = AlertSettings()
    private let logger = Logger(subsystem: "FocusFlowSwift", category: "AlertSettings")
    
    @Published var isPlaying: Bool = false {
        didSet { logger.info("isPlaying changed: \(oldValue) -> \(self.isPlaying)") }
    }
    @Published var isSimple: Bool = false {
        didSet { logger.info("isSimple changed: \(oldValue) -> \(self.isSimple)") }
    }
    @Published var isPaused: Bool = false {
        didSet { logger.info("isPaused changed: \(oldValue) -> \(self.isPaused)") }
    }
    @Published var intervalMinutes: Int = 5 {
        didSet { logger.info("intervalMinutes changed: \(oldValue) -> \(self.intervalMinutes)") }
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
    
    private var timer: Timer?
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    private init() {
        logger.info("AlertSettings initialized")
    }
    
    func scheduleIntervalTimer() {
        timer?.invalidate()
        guard isPlaying else { return }
        
        // Set start time when timer begins
        if startTime.isEmpty {
            updateStartTime()
        }
        
        let interval = nextAlertDate.timeIntervalSinceNow
        if interval <= 0 {
            nextAlertDate = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))
        }
        updateNextAlertTime()
        
        let nextInterval = nextAlertDate.timeIntervalSinceNow
        timer = Timer.scheduledTimer(withTimeInterval: nextInterval, repeats: false) { _ in
            self.handleAlertFire()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    private func handleAlertFire() {
        counter += 1
        
        // Play speech sound
        playSound()
        
        // Trigger notification for any listening views
        NotificationCenter.default.post(name: .intervalAlert, object: nil)
        
        if let target = targetIntervals, counter >= target {
            intervalsComplete = true
            isPlaying = false
            timer?.invalidate()
            timer = nil
        } else {
            nextAlertDate = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))
            updateNextAlertTime()
            scheduleIntervalTimer()
        }
    }
    
    private func playSound() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        
        let utterance = AVSpeechUtterance(string: "Interval \(counter)")
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
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}