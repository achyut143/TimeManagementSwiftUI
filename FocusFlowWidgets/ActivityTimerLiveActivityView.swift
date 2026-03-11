import SwiftUI
import ActivityKit
import WidgetKit

@available(iOS 16.1, *)
struct ActivityTimerLiveActivityView: View {
    let context: ActivityViewContext<ActivityTimerAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.orange)
                    .font(.headline)
                
                Text(context.attributes.activityName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Spacer()
                
                if context.state.isPaused {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 8, height: 8)
                        Text("Paused")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Running")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            HStack(spacing: 20) {
                // Countdown Timer
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time Remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !context.state.isPaused {
                        Text(context.state.endTime, style: .timer)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                            .monospacedDigit()
                    } else {
                        Text(formattedTime(context.state.remainingSeconds))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                            .monospacedDigit()
                    }
                }
                
                Spacer()
                
                // Progress Circle
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .trim(from: 0, to: progressValue)
                        .stroke(
                            context.state.isPaused ? Color.yellow : Color.orange,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(Int(progressValue * 100))%")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(context.state.isPaused ? .yellow : .orange)
                }
            }
            
            // Total duration info
            Text("Total: \(formattedTime(context.attributes.totalDuration))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var progressValue: CGFloat {
        let remaining = context.state.remainingSeconds
        let total = context.attributes.totalDuration
        guard total > 0 else { return 0 }
        return CGFloat(max(0, min(1, remaining / total)))
    }
    
    private func formattedTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
