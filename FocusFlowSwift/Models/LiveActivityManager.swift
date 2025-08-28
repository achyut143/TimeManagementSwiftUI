import ActivityKit
import Foundation
import os.log
import WidgetKit

typealias ConcurrencyTask = _Concurrency.Task

@available(iOS 16.1, *)
class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    private let logger = Logger(subsystem: "FocusFlowSwift", category: "LiveActivityManager")
    
    @Published var currentActivity: Activity<FocusActivityAttributes>? {
        didSet {
            // Notify when activity state changes
            if oldValue != nil && currentActivity == nil {
                // Activity ended
                NotificationCenter.default.post(name: .liveActivityEnded, object: nil)
            } else if oldValue == nil && currentActivity != nil {
                // Activity started
                NotificationCenter.default.post(name: .liveActivityStarted, object: nil)
            }
        }
    }
    
    private init() {}
    
    func startFocusActivity(
        intervalDuration: Int,
        currentInterval: Int = 0,
        totalIntervals: Int? = nil,
        intervalName: String = "Focus Interval",
        nextAlertTime: Date,
        isInCycleMode: Bool = false,
        currentCycleName: String? = nil,
        cycleProgress: String? = nil
    ) {
        // Check if Live Activities are supported and enabled
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            logger.warning("⚠️ Live Activities not enabled - Status: \(authInfo.frequentPushesEnabled)")
            print("⚠️ Live Activities not available on this device/account")
            print("📱 Free developer accounts have limited Live Activity support on real devices")
            return
        }
        
        // End any existing activity first
        endCurrentActivity()
        
        let attributes = FocusActivityAttributes(
            intervalDuration: intervalDuration,
            startTime: Date(),
            sessionId: UUID().uuidString
        )
        
        // Enhanced state with better uniqueness for free accounts
        let uniqueTimestamp = Date().timeIntervalSince1970
        let randomComponent = Int.random(in: 1000...9999)
        let uniqueCounter = (currentInterval * 100000) + Int(uniqueTimestamp.truncatingRemainder(dividingBy: 10000)) + randomComponent
        
        let contentState = FocusActivityAttributes.ContentState(
            currentInterval: currentInterval,
            totalIntervals: totalIntervals,
            intervalName: intervalName,
            nextAlertTime: nextAlertTime,
            isInCycleMode: isInCycleMode,
            currentCycleName: currentCycleName,
            cycleProgress: cycleProgress,
            timeRemaining: nextAlertTime.timeIntervalSinceNow,
            isPaused: false,
            updateTimestamp: uniqueTimestamp,
            updateCounter: uniqueCounter
        )
        
        do {
            let activity = try Activity<FocusActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            
            currentActivity = activity
            logger.info("✅ Started Live Activity: \(activity.id) - Interval: \(currentInterval), Counter: \(uniqueCounter)")
            print("🟢 Live Activity started! Interval: \(currentInterval), Unique Counter: \(uniqueCounter)")
            print("📱 Dynamic Island should now show interval counter")
            
            // Enhanced refresh strategy for free developer accounts
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
                print("🔄 Initial widget refresh")
            }
            
            // Multiple staggered refreshes for better reliability on real devices
            let refreshDelays: [Double] = [0.2, 0.5, 1.0, 2.0]
            for delay in refreshDelays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    WidgetCenter.shared.reloadAllTimelines()
                    print("🔄 Delayed widget refresh at \(delay)s")
                }
            }
            
        } catch {
            logger.error("❌ Failed to start Live Activity: \(error.localizedDescription)")
            print("🔴 Live Activity failed: \(error.localizedDescription)")
            print("📱 This is expected with free developer accounts on physical devices")
            print("💡 The app will use notifications instead for interval tracking")
        }
    }
    
    func updateFocusActivity(
        currentInterval: Int,
        totalIntervals: Int? = nil,
        intervalName: String = "Focus Interval",
        nextAlertTime: Date,
        isInCycleMode: Bool = false,
        currentCycleName: String? = nil,
        cycleProgress: String? = nil,
        isPaused: Bool = false
    ) {
        guard let activity = currentActivity else {
            logger.warning("No active Live Activity to update")
            // Try to start a new activity if we don't have one
            startFocusActivity(
                intervalDuration: 5, // Default duration
                currentInterval: currentInterval,
                totalIntervals: totalIntervals,
                intervalName: intervalName,
                nextAlertTime: nextAlertTime,
                isInCycleMode: isInCycleMode,
                currentCycleName: currentCycleName,
                cycleProgress: cycleProgress
            )
            return
        }
        
        // Create unique state to force Dynamic Island refresh - enhanced for free accounts
        let uniqueTimestamp = Date().timeIntervalSince1970
        let randomComponent = Int.random(in: 1...999)
        let uniqueCounter = (currentInterval * 10000) + Int(uniqueTimestamp.truncatingRemainder(dividingBy: 1000)) + randomComponent
        
        let contentState = FocusActivityAttributes.ContentState(
            currentInterval: currentInterval,
            totalIntervals: totalIntervals,
            intervalName: intervalName,
            nextAlertTime: nextAlertTime,
            isInCycleMode: isInCycleMode,
            currentCycleName: currentCycleName,
            cycleProgress: cycleProgress,
            timeRemaining: isPaused ? 0 : nextAlertTime.timeIntervalSinceNow,
            isPaused: isPaused,
            updateTimestamp: uniqueTimestamp,
            updateCounter: uniqueCounter
        )
        
        logger.info("🔄 Updating Live Activity - Interval: \(currentInterval), Counter: \(uniqueCounter)")
        print("📱 Updating Dynamic Island - Interval: \(currentInterval), Unique Counter: \(uniqueCounter)")
        
        // Enhanced update strategy for free developer accounts
        ConcurrencyTask {
            var updateSuccessful = false
            
            // Strategy 1: Standard update
            do {
                await activity.update(.init(state: contentState, staleDate: nil))
                self.logger.info("✅ Live Activity updated successfully - Interval: \(currentInterval)")
                print("✅ Dynamic Island updated: Interval \(currentInterval)")
                updateSuccessful = true
                
            } catch {
                self.logger.error("❌ Primary update failed: \(error.localizedDescription)")
                print("❌ Primary update failed: \(error.localizedDescription)")
                
                // Strategy 2: Retry with different timestamp
                do {
                    let retryState = FocusActivityAttributes.ContentState(
                        currentInterval: currentInterval,
                        totalIntervals: totalIntervals,
                        intervalName: intervalName,
                        nextAlertTime: nextAlertTime,
                        isInCycleMode: isInCycleMode,
                        currentCycleName: currentCycleName,
                        cycleProgress: cycleProgress,
                        timeRemaining: isPaused ? 0 : nextAlertTime.timeIntervalSinceNow,
                        isPaused: isPaused,
                        updateTimestamp: Date().timeIntervalSince1970 + 0.5,
                        updateCounter: uniqueCounter + 1000
                    )
                    
                    await activity.update(.init(state: retryState, staleDate: nil))
                    self.logger.info("✅ Live Activity updated on retry - Interval: \(currentInterval)")
                    print("✅ Dynamic Island updated on retry: Interval \(currentInterval)")
                    updateSuccessful = true
                    
                } catch {
                    self.logger.error("❌ Retry failed: \(error.localizedDescription)")
                    print("❌ Retry failed: \(error.localizedDescription)")
                }
            }
            
            // Strategy 3: Force restart if updates keep failing (for free accounts)
            if !updateSuccessful {
                self.logger.info("🔄 All updates failed, forcing restart for free account compatibility")
                print("🔄 Forcing restart for free developer account")
                
                await MainActor.run {
                    self.restartActivityWithNewState(
                        currentInterval: currentInterval,
                        totalIntervals: totalIntervals,
                        intervalName: intervalName,
                        nextAlertTime: nextAlertTime,
                        isInCycleMode: isInCycleMode,
                        currentCycleName: currentCycleName,
                        cycleProgress: cycleProgress,
                        isPaused: isPaused
                    )
                }
            }
            
            // Force multiple widget refreshes for better reliability
            await MainActor.run {
                WidgetCenter.shared.reloadAllTimelines()
                print("🔄 Forced widget timeline reload")
            }
            
            // Staggered refreshes for free accounts
            for delay in [100, 300, 500] {
                try? await ConcurrencyTask.sleep(for: .milliseconds(delay))
                await MainActor.run {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }
    
    // Helper method to restart activity when updates fail
    private func restartActivityWithNewState(
        currentInterval: Int,
        totalIntervals: Int?,
        intervalName: String,
        nextAlertTime: Date,
        isInCycleMode: Bool,
        currentCycleName: String?,
        cycleProgress: String?,
        isPaused: Bool
    ) {
        logger.info("🔄 Restarting Live Activity due to update failure - Interval: \(currentInterval)")
        print("🔄 Restarting Dynamic Island for free account compatibility")
        
        // End current activity
        endCurrentActivity()
        
        // Longer delay for free accounts to ensure clean restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.startFocusActivity(
                intervalDuration: 5, // Default, will be overridden
                currentInterval: currentInterval,
                totalIntervals: totalIntervals,
                intervalName: intervalName,
                nextAlertTime: nextAlertTime,
                isInCycleMode: isInCycleMode,
                currentCycleName: currentCycleName,
                cycleProgress: cycleProgress
            )
            
            print("✅ Live Activity restarted with interval \(currentInterval)")
        }
    }
    
    func pauseFocusActivity() {
        guard let activity = currentActivity else { return }
        
        let currentState = activity.content.state
        let pausedState = FocusActivityAttributes.ContentState(
            currentInterval: currentState.currentInterval,
            totalIntervals: currentState.totalIntervals,
            intervalName: currentState.intervalName,
            nextAlertTime: currentState.nextAlertTime,
            isInCycleMode: currentState.isInCycleMode,
            currentCycleName: currentState.currentCycleName,
            cycleProgress: currentState.cycleProgress,
            timeRemaining: 0,
            isPaused: true,
            updateTimestamp: Date().timeIntervalSince1970,
            updateCounter: currentState.updateCounter + 1000 // Force different value
        )
        
        ConcurrencyTask {
            await activity.update(.init(state: pausedState, staleDate: nil))
            logger.info("⏸️ Paused Live Activity")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    func resumeFocusActivity(nextAlertTime: Date) {
        guard let activity = currentActivity else { return }
        
        let currentState = activity.content.state
        let resumedState = FocusActivityAttributes.ContentState(
            currentInterval: currentState.currentInterval,
            totalIntervals: currentState.totalIntervals,
            intervalName: currentState.intervalName,
            nextAlertTime: nextAlertTime,
            isInCycleMode: currentState.isInCycleMode,
            currentCycleName: currentState.currentCycleName,
            cycleProgress: currentState.cycleProgress,
            timeRemaining: nextAlertTime.timeIntervalSinceNow,
            isPaused: false,
            updateTimestamp: Date().timeIntervalSince1970,
            updateCounter: currentState.updateCounter + 2000 // Force different value
        )
        
        ConcurrencyTask {
            await activity.update(.init(state: resumedState, staleDate: nil))
            logger.info("▶️ Resumed Live Activity")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    func endCurrentActivity() {
        guard let activity = currentActivity else { return }
        
        ConcurrencyTask {
            await activity.end(nil, dismissalPolicy: .immediate)
            logger.info("Ended Live Activity: \(activity.id)")
        }
        
        currentActivity = nil
    }
    
    func forceEndAndClearActivity() {
        if let activity = currentActivity {
            ConcurrencyTask {
                await activity.end(nil, dismissalPolicy: .immediate)
                logger.info("Force ended Live Activity: \(activity.id)")
            }
        }
        
        // Force clear the activity reference
        currentActivity = nil
        logger.info("🔄 Live Activity forcefully cleared for reset")
    }
    
    // Force refresh method specifically for free developer accounts
    func forceRefreshForFreeAccount(currentInterval: Int, nextAlertTime: Date) {
        logger.info("🔄 Force refresh for free developer account - Interval: \(currentInterval)")
        print("🔄 Force refreshing Dynamic Island for free account")
        
        // End current activity and restart with new state
        endCurrentActivity()
        
        // Wait a moment then restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.startFocusActivity(
                intervalDuration: 5, // Default
                currentInterval: currentInterval,
                totalIntervals: nil,
                intervalName: "Focus Interval \(currentInterval)",
                nextAlertTime: nextAlertTime,
                isInCycleMode: false,
                currentCycleName: nil,
                cycleProgress: nil
            )
            
            print("🔄 Restarted Live Activity for interval \(currentInterval)")
        }
    }
    
    func endActivityWithCompletion() {
        guard let activity = currentActivity else { return }
        
        // Update with completion state first
        let completionState = FocusActivityAttributes.ContentState(
            currentInterval: activity.content.state.currentInterval,
            totalIntervals: activity.content.state.totalIntervals,
            intervalName: "Session Complete!",
            nextAlertTime: Date(),
            isInCycleMode: activity.content.state.isInCycleMode,
            currentCycleName: activity.content.state.currentCycleName,
            cycleProgress: activity.content.state.cycleProgress,
            timeRemaining: 0,
            isPaused: false,
            updateTimestamp: Date().timeIntervalSince1970,
            updateCounter: 9999 // Final completion value
        )
        
        ConcurrencyTask {
            await activity.update(.init(state: completionState, staleDate: nil))
            
            // End after a brief delay to show completion
            try? await ConcurrencyTask.sleep(for: .seconds(2))
            await activity.end(nil, dismissalPolicy: .default)
            logger.info("Ended Live Activity with completion: \(activity.id)")
        }
        
        currentActivity = nil
    }
    
    var isActivityActive: Bool {
        return currentActivity != nil
    }
    
    func debugActivityState() {
        let authInfo = ActivityAuthorizationInfo()
        logger.info("🔍 Live Activity Debug Info:")
        logger.info("- Activities enabled: \(authInfo.areActivitiesEnabled)")
        logger.info("- Frequent pushes enabled: \(authInfo.frequentPushesEnabled)")
        logger.info("- Current activity exists: \(self.currentActivity != nil)")
        logger.info("- Is real device: \(self.isRunningOnRealDevice)")
        
        if let activity = currentActivity {
            logger.info("- Activity ID: \(activity.id)")
            logger.info("- Activity state: \(String(describing: activity.activityState))")
            logger.info("- Current interval: \(activity.content.state.currentInterval)")
            logger.info("- Update counter: \(activity.content.state.updateCounter)")
            logger.info("- Update timestamp: \(activity.content.state.updateTimestamp)")
            logger.info("- Next alert: \(activity.content.state.nextAlertTime)")
            logger.info("- Is paused: \(activity.content.state.isPaused)")
        }
        
        print("🔍 Live Activity Debug Summary:")
        print("   - Active: \(isActivityActive)")
        print("   - Enabled: \(authInfo.areActivitiesEnabled)")
        print("   - Real Device: \(isRunningOnRealDevice)")
        print("   - Free Account Limitations: \(isRunningOnRealDevice && !authInfo.frequentPushesEnabled)")
        
        if let activity = currentActivity {
            print("   - Current Interval: \(activity.content.state.currentInterval)")
            print("   - Update Counter: \(activity.content.state.updateCounter)")
        }
    }
    
    private var isRunningOnRealDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
}