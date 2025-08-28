import SwiftUI
import ActivityKit
import WidgetKit

@available(iOS 16.1, *)
struct FocusLiveActivityView: View {
    let context: ActivityViewContext<FocusActivityAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            // Header with session info
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.blue)
                    .font(.headline)
                
                Text("Focus Session")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if context.state.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                }
            }
            
            // Main content
            HStack(spacing: 16) {
                // Left side - Interval info
                VStack(alignment: .leading, spacing: 4) {
                    if context.state.isInCycleMode {
                        Text(context.state.currentCycleName ?? "Cycle")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                        
                        if let cycleProgress = context.state.cycleProgress {
                            Text("Cycle \(cycleProgress)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Interval")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let total = context.state.totalIntervals {
                            Text("\(context.state.currentInterval)/\(total)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        } else {
                            Text("\(context.state.currentInterval)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }
                    }
                }
                
                Spacer()
                
                // Right side - Time info
                VStack(alignment: .trailing, spacing: 4) {
                    if !context.state.isPaused {
                        Text("Next Alert")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(context.state.nextAlertTime, style: .time)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    } else {
                        Text("Paused")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                    
                    Text("Started: \(context.attributes.startTime, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            // Progress bar (if applicable)
            if let total = context.state.totalIntervals, total > 0 {
                ProgressView(
                    value: Double(context.state.currentInterval),
                    total: Double(total)
                )
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .scaleEffect(y: 0.8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

