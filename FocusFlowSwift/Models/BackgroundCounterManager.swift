import SwiftUI
import Combine
import ActivityKit
import os.log

typealias BackgroundTask = _Concurrency.Task

class BackgroundCounterManager: ObservableObject {
    static let shared = BackgroundCounterManager()
    private let logger = Logger(subsystem: "FocusFlowSwift", category: "BackgroundCounter")
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "backgroundCounterEnabled")
            if !isEnabled {
                stopCounting()
                if #available(iOS 16.1, *) {
                    endLiveActivity()
                }
            }
        }
    }
    
    @Published var totalBackgroundTime: TimeInterval = 0
    @Published var currentSessionTime: TimeInterval = 0
    @Published var isCountingInBackground: Bool = false
    @Published var isDeviceLocked: Bool = false
    
    private var backgroundStartTime: Date?
    private var lockStartTime: Date?
    private var timer: Timer?
    private var isAppInBackground: Bool = false
    
    @available(iOS 16.1, *)
    private var currentActivity: Activity<BackgroundCounterAttributes>?
    
    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "backgroundCounterEnabled")
        self.totalBackgroundTime = UserDefaults.standard.double(forKey: "totalBackgroundTime")
        self.currentSessionTime = UserDefaults.standard.double(forKey: "currentSessionTime")
        
        // Register for device lock/unlock notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceLocked),
            name: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceUnlocked),
            name: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func handleAppDidEnterBackground() {
        guard isEnabled else { return }
        
        isAppInBackground = true
        
        // Only start counting if device is not locked
        if !isDeviceLocked {
            backgroundStartTime = Date()
            isCountingInBackground = true
            saveState()
            
            // Start Live Activity
            if #available(iOS 16.1, *) {
                startLiveActivity()
            }
        }
    }
    
    func handleAppDidBecomeActive() {
        guard isEnabled else {
            isCountingInBackground = false
            isAppInBackground = false
            if #available(iOS 16.1, *) {
                endLiveActivity()
            }
            return
        }
        
        isAppInBackground = false
        
        // If we were counting background time, add it
        if let startTime = backgroundStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            currentSessionTime += elapsed
            totalBackgroundTime += elapsed
            
            backgroundStartTime = nil
        }
        
        isCountingInBackground = false
        
        saveState()
        
        // End Live Activity
        if #available(iOS 16.1, *) {
            endLiveActivity()
        }
    }
    
    @objc private func handleDeviceLocked() {
        guard isEnabled else { return }
        
        logger.info("🔒 Device locked")
        isDeviceLocked = true
        
        // If we're currently counting background time, pause it
        if let startTime = backgroundStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            currentSessionTime += elapsed
            totalBackgroundTime += elapsed
            
            // Store when we paused due to lock
            lockStartTime = Date()
            backgroundStartTime = nil
            
            saveState()
            
            if #available(iOS 16.1, *) {
                updateLiveActivity()
            }
        }
    }
    
    @objc private func handleDeviceUnlocked() {
        guard isEnabled else { return }
        
        logger.info("🔓 Device unlocked")
        isDeviceLocked = false
        lockStartTime = nil
        
        // Resume counting if app is still in background
        if isAppInBackground {
            logger.info("📱 App still in background, resuming counter")
            backgroundStartTime = Date()
            isCountingInBackground = true
            
            // Update existing Live Activity (can't start new one from background)
            if #available(iOS 16.1, *) {
                updateLiveActivity()
            }
        }
    }
    
    func resetCurrentSession() {
        currentSessionTime = 0
        saveState()
        
        if #available(iOS 16.1, *), isCountingInBackground {
            updateLiveActivity()
        }
    }
    
    func resetTotal() {
        totalBackgroundTime = 0
        currentSessionTime = 0
        saveState()
        
        if #available(iOS 16.1, *), isCountingInBackground {
            updateLiveActivity()
        }
    }
    
    private func stopCounting() {
        backgroundStartTime = nil
        isCountingInBackground = false
    }
    
    private func saveState() {
        UserDefaults.standard.set(totalBackgroundTime, forKey: "totalBackgroundTime")
        UserDefaults.standard.set(currentSessionTime, forKey: "currentSessionTime")
    }
    
    func formattedTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - Live Activity Methods
    
    @available(iOS 16.1, *)
    private func startLiveActivity() {
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            logger.warning("Live Activities not enabled")
            return
        }
        
        // End any existing activity
        endLiveActivity()
        
        let attributes = BackgroundCounterAttributes(
            sessionId: UUID().uuidString,
            startTime: Date()
        )
        
        let contentState = BackgroundCounterAttributes.ContentState(
            currentSessionTime: currentSessionTime,
            totalBackgroundTime: totalBackgroundTime,
            isCountingInBackground: true,
            backgroundStartTime: backgroundStartTime,
            updateTimestamp: Date().timeIntervalSince1970,
            updateCounter: 0
        )
        
        do {
            let activity = try Activity<BackgroundCounterAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            
            currentActivity = activity
            logger.info("✅ Started Background Counter Live Activity")
            print("🟢 Background Counter Live Activity started!")
            
        } catch {
            logger.error("❌ Failed to start Background Counter Live Activity: \(error.localizedDescription)")
            print("🔴 Background Counter Live Activity failed: \(error.localizedDescription)")
        }
    }
    
    @available(iOS 16.1, *)
    private func updateLiveActivity() {
        guard let activity = currentActivity else { return }
        
        let elapsed = backgroundStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let currentTime = currentSessionTime + elapsed
        let totalTime = totalBackgroundTime + elapsed
        
        let contentState = BackgroundCounterAttributes.ContentState(
            currentSessionTime: currentTime,
            totalBackgroundTime: totalTime,
            isCountingInBackground: isCountingInBackground,
            backgroundStartTime: backgroundStartTime,
            updateTimestamp: Date().timeIntervalSince1970,
            updateCounter: Int.random(in: 1000...9999)
        )
        
        BackgroundTask {
            await activity.update(.init(state: contentState, staleDate: nil))
            self.logger.info("🔄 Updated Background Counter Live Activity")
        }
    }
    
    @available(iOS 16.1, *)
    private func endLiveActivity() {
        guard let activity = currentActivity else { return }
        
        BackgroundTask {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.logger.info("Ended Background Counter Live Activity")
        }
        
        currentActivity = nil
    }
}
