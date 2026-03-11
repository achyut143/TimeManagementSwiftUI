import SwiftUI

@available(iOS 16.1, *)
struct ActiveTimerButton: View {
    @StateObject private var timerManager = ActivityTimerManager.shared
    @State private var showTimerControl = false
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                if timerManager.isTimerRunning {
                    Button {
                        showTimerControl = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 50, height: 50)
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            
                            VStack(spacing: 2) {
                                Image(systemName: "timer")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                
                                Text("Active")
                                    .font(.system(size: 6, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 160) // Above quick activity button
        }
        .sheet(isPresented: $showTimerControl) {
            TimerControlView()
        }
    }
}

@available(iOS 16.1, *)
struct TimerControlView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var timerManager = ActivityTimerManager.shared
    @State private var currentTime = Date()
    @State private var showCancelConfirmation = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var remainingTime: TimeInterval {
        guard let activity = timerManager.currentActivity else { return 0 }
        return max(0, activity.contentState.endTime.timeIntervalSince(currentTime))
    }
    
    var progress: Double {
        guard let activity = timerManager.currentActivity else { return 0 }
        let total = activity.attributes.totalDuration
        guard total > 0 else { return 0 }
        return remainingTime / total
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let activity = timerManager.currentActivity {
                    // Activity name
                    Text(activity.attributes.activityName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Large countdown display
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                            .frame(width: 200, height: 200)
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                activity.contentState.isPaused ? Color.yellow : Color.orange,
                                style: StrokeStyle(lineWidth: 20, lineCap: .round)
                            )
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: progress)
                        
                        VStack(spacing: 8) {
                            Text(timeString(from: remainingTime))
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(activity.contentState.isPaused ? .yellow : .orange)
                                .monospacedDigit()
                            
                            Text("\(Int(progress * 100))%")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 32)
                    
                    // Timer info
                    VStack(spacing: 12) {
                        HStack {
                            Text("Total Duration:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(timeString(from: activity.attributes.totalDuration))
                                .fontWeight(.semibold)
                        }
                        
                        HStack {
                            Text("End Time:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(activity.contentState.endTime, style: .time)
                                .fontWeight(.semibold)
                        }
                        
                        HStack {
                            Text("Status:")
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(activity.contentState.isPaused ? Color.yellow : Color.green)
                                    .frame(width: 8, height: 8)
                                Text(activity.contentState.isPaused ? "Paused" : "Running")
                                    .fontWeight(.semibold)
                                    .foregroundColor(activity.contentState.isPaused ? .yellow : .green)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    Spacer()
                    
                    // Control buttons
                    VStack(spacing: 12) {
                        // Pause/Resume button
                        if activity.contentState.isPaused {
                            Button {
                                timerManager.resumeTimer()
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Resume Timer")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                            }
                        } else {
                            Button {
                                timerManager.pauseTimer()
                            } label: {
                                HStack {
                                    Image(systemName: "pause.fill")
                                    Text("Pause Timer")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.yellow)
                                .cornerRadius(12)
                            }
                        }
                        
                        // Cancel button
                        Button {
                            showCancelConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Cancel Timer")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                        }
                    }
                } else {
                    Text("No active timer")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle("Activity Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
            
            // Auto-dismiss if timer ended
            if !timerManager.isTimerRunning {
                dismiss()
            }
        }
        .alert("Cancel Timer?", isPresented: $showCancelConfirmation) {
            Button("Yes, Cancel", role: .destructive) {
                timerManager.endTimer()
                dismiss()
            }
            Button("No, Keep Running", role: .cancel) {}
        } message: {
            Text("Are you sure you want to cancel the timer? This cannot be undone.")
        }
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    if #available(iOS 16.1, *) {
        ActiveTimerButton()
    }
}
