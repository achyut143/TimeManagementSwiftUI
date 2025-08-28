import SwiftUI
import ActivityKit

@available(iOS 16.1, *)
struct DynamicIslandDebugView: View {
    @StateObject private var settings = AlertSettings.shared
    @State private var testCounter = 1
    @State private var debugMessage = "Ready to test"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Dynamic Island Debug")
                .font(.title2)
                .fontWeight(.bold)
            
            // Status display
            VStack(alignment: .leading, spacing: 8) {
                Text("Status:")
                    .font(.headline)
                
                Text("Counter: \(settings.counter)")
                    .font(.subheadline)
                
                Text("Live Activity Active: \(settings.liveActivityManager.isActivityActive ? "Yes" : "No")")
                    .font(.subheadline)
                
                Text("Activities Enabled: \(ActivityAuthorizationInfo().areActivitiesEnabled ? "Yes" : "No")")
                    .font(.subheadline)
                
                Text("Free Account: \(isRunningOnRealDevice && !ActivityAuthorizationInfo().frequentPushesEnabled ? "Yes" : "No")")
                    .font(.subheadline)
                
                Text(debugMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding()
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            
            // Test buttons
            VStack(spacing: 12) {
                Button("Start Test Activity") {
                    startTestActivity()
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.liveActivityManager.isActivityActive)
                
                Button("Update Counter: \(testCounter)") {
                    updateTestCounter()
                }
                .buttonStyle(.bordered)
                .disabled(!settings.liveActivityManager.isActivityActive)
                
                Button("Force Refresh") {
                    forceRefresh()
                }
                .buttonStyle(.bordered)
                .disabled(!settings.liveActivityManager.isActivityActive)
                
                Button("Debug State") {
                    debugState()
                }
                .buttonStyle(.bordered)
                
                Button("End Activity") {
                    endTestActivity()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .disabled(!settings.liveActivityManager.isActivityActive)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("DI Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func startTestActivity() {
        debugMessage = "Starting test activity..."
        testCounter = 1
        
        settings.liveActivityManager.startFocusActivity(
            intervalDuration: 5,
            currentInterval: testCounter,
            totalIntervals: 10,
            intervalName: "Test Interval \(testCounter)",
            nextAlertTime: Date().addingTimeInterval(300), // 5 minutes from now
            isInCycleMode: false,
            currentCycleName: nil,
            cycleProgress: nil
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if settings.liveActivityManager.isActivityActive {
                debugMessage = "✅ Test activity started successfully"
            } else {
                debugMessage = "❌ Test activity failed to start (normal for free accounts)"
            }
        }
    }
    
    private func updateTestCounter() {
        testCounter += 1
        debugMessage = "Updating to counter \(testCounter)..."
        
        settings.liveActivityManager.updateFocusActivity(
            currentInterval: testCounter,
            totalIntervals: 10,
            intervalName: "Test Interval \(testCounter)",
            nextAlertTime: Date().addingTimeInterval(300),
            isInCycleMode: false,
            currentCycleName: nil,
            cycleProgress: nil,
            isPaused: false
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            debugMessage = "✅ Updated to counter \(testCounter)"
        }
    }
    
    private func forceRefresh() {
        debugMessage = "Force refreshing..."
        
        settings.liveActivityManager.forceRefreshForFreeAccount(
            currentInterval: testCounter,
            nextAlertTime: Date().addingTimeInterval(300)
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            debugMessage = "✅ Force refresh completed"
        }
    }
    
    private func debugState() {
        debugMessage = "Checking debug state..."
        settings.liveActivityManager.debugActivityState()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            debugMessage = "✅ Debug info printed to console"
        }
    }
    
    private func endTestActivity() {
        debugMessage = "Ending test activity..."
        settings.liveActivityManager.endCurrentActivity()
        testCounter = 1
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            debugMessage = "✅ Test activity ended"
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

#Preview {
    if #available(iOS 16.1, *) {
        NavigationView {
            DynamicIslandDebugView()
        }
    } else {
        Text("iOS 16.1+ Required")
    }
}