import SwiftUI
import ActivityKit
import WidgetKit

@available(iOS 16.1, *)
struct BackgroundCounterLiveActivityView: View {
    let context: ActivityViewContext<BackgroundCounterAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.blue)
                    .font(.headline)
                
                Text("Background Time")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if context.state.isCountingInBackground {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Counting")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            HStack(spacing: 20) {
                // Current Session - Live Timer
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let startTime = context.state.backgroundStartTime {
                        Text(startTime, style: .timer)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .monospacedDigit()
                    } else {
                        Text(formattedTime(context.state.currentSessionTime))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .monospacedDigit()
                    }
                }
                
                Divider()
                    .frame(height: 30)
                
                // Total Time
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formattedTime(context.state.totalBackgroundTime))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        .monospacedDigit()
                }
            }
            
            if let startTime = context.state.backgroundStartTime {
                Text("Started: \(startTime, style: .time)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
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
