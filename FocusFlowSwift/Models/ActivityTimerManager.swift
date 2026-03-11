import Foundation
import ActivityKit
import SwiftUI

@available(iOS 16.1, *)
class ActivityTimerManager: ObservableObject {
    static let shared = ActivityTimerManager()
    
    @Published var currentActivity: Activity<ActivityTimerAttributes>?
    private var timer: Timer?
    
    private init() {}
    
    // Start a new timer
    func startTimer(activityName: String, durationMinutes: Double) {
        // End any existing timer
        endTimer()
        
        let totalSeconds = durationMinutes * 60
        let endTime = Date().addingTimeInterval(totalSeconds)
        
        let attributes = ActivityTimerAttributes(
            timerId: UUID().uuidString,
            totalDuration: totalSeconds,
            activityName: activityName
        )
        
        let initialState = ActivityTimerAttributes.ContentState(
            endTime: endTime,
            remainingSeconds: totalSeconds,
            activityName: activityName,
            isPaused: false,
            updateTimestamp: Date().timeIntervalSince1970
        )
        
        do {
            // Request with high priority to appear on top in Dynamic Island
            let activity = try Activity<ActivityTimerAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil, relevanceScore: 100.0),
                pushType: nil
            )
            
            currentActivity = activity
            print("✅ Started timer Live Activity for '\(activityName)' - Duration: \(durationMinutes) minutes with HIGH PRIORITY")
            
            // Start update timer
            startUpdateTimer()
            
        } catch {
            print("❌ Failed to start timer Live Activity: \(error.localizedDescription)")
        }
    }
    
    // Update timer every second
    private func startUpdateTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }
    
    private func updateTimer() {
        guard let activity = currentActivity else {
            timer?.invalidate()
            return
        }
        
        let now = Date()
        let remaining = activity.contentState.endTime.timeIntervalSince(now)
        
        if remaining <= 0 {
            // Timer finished - send notification
            sendTimerCompletionNotification(activityName: activity.contentState.activityName)
            endTimer()
            return
        }
        
        let newState = ActivityTimerAttributes.ContentState(
            endTime: activity.contentState.endTime,
            remainingSeconds: remaining,
            activityName: activity.contentState.activityName,
            isPaused: activity.contentState.isPaused,
            updateTimestamp: Date().timeIntervalSince1970
        )
        
        _Concurrency.Task {
            // Update with high relevance score to keep priority
            await activity.update(
                .init(state: newState, staleDate: nil, relevanceScore: 100.0)
            )
        }
    }
    
    // Send notification when timer completes
    private func sendTimerCompletionNotification(activityName: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("ActivityTimerCompleted"),
            object: nil,
            userInfo: ["activityName": activityName]
        )
        print("⏰ Timer completed for '\(activityName)'")
    }
    
    // Pause timer
    func pauseTimer() {
        guard let activity = currentActivity else { return }
        
        timer?.invalidate()
        
        let remaining = activity.contentState.endTime.timeIntervalSince(Date())
        
        let newState = ActivityTimerAttributes.ContentState(
            endTime: activity.contentState.endTime,
            remainingSeconds: remaining,
            activityName: activity.contentState.activityName,
            isPaused: true,
            updateTimestamp: Date().timeIntervalSince1970
        )
        
        _Concurrency.Task {
            await activity.update(
                .init(state: newState, staleDate: nil, relevanceScore: 100.0)
            )
        }
        
        print("⏸️ Timer paused")
    }
    
    // Resume timer
    func resumeTimer() {
        guard let activity = currentActivity else { return }
        
        let newEndTime = Date().addingTimeInterval(activity.contentState.remainingSeconds)
        
        let newState = ActivityTimerAttributes.ContentState(
            endTime: newEndTime,
            remainingSeconds: activity.contentState.remainingSeconds,
            activityName: activity.contentState.activityName,
            isPaused: false,
            updateTimestamp: Date().timeIntervalSince1970
        )
        
        _Concurrency.Task {
            await activity.update(
                .init(state: newState, staleDate: nil, relevanceScore: 100.0)
            )
        }
        
        startUpdateTimer()
        print("▶️ Timer resumed")
    }
    
    // End timer
    func endTimer() {
        timer?.invalidate()
        timer = nil
        
        guard let activity = currentActivity else { return }
        
        _Concurrency.Task {
            await activity.end(dismissalPolicy: .immediate)
        }
        
        currentActivity = nil
        print("⏹️ Timer ended")
    }
    
    // Check if timer is running
    var isTimerRunning: Bool {
        return currentActivity != nil
    }
}
