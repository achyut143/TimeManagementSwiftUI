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
    
    private var backgroundStartTime: Date?
    private var timer: Timer?
    
    @available(iOS 16.1, *)
    private var currentActivity: Activity<BackgroundCounterAttributes>?
    
    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "backgroundCounterEnabled")
        self.totalBackgroundTime = UserDefaults.standard.double(forKey: "totalBackgroundTime")
        self.currentSessionTime = UserDefaults.standard.double(forKey: "currentSessionTime")
    }
    
    func handleAppDidEnterBackground() {
        guard isEnabled else { return }
        backgroundStartTime = Date()
        isCountingInBackground = true
        saveState()
        
        // Start Live Activity
        if #available(iOS 16.1, *) {
            startLiveActivity()
        }
    }
    
    func handleAppDidBecomeActive() {
        guard isEnabled, let startTime = backgroundStartTime else {
            isCountingInBackground = false
            if #available(iOS 16.1, *) {
                endLiveActivity()
            }
            return
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        currentSessionTime += elapsed
        totalBackgroundTime += elapsed
        
        backgroundStartTime = nil
        isCountingInBackground = false
        
        saveState()
        
        // End Live Activity
        if #available(iOS 16.1, *) {
            endLiveActivity()
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
