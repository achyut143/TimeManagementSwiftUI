import WidgetKit
import SwiftUI
import ActivityKit
import Foundation

@main
struct FocusFlowWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Control Widget (existing)
        FocusFlowWidgetsControl()
        
        // Live Activity Widget (new)
        if #available(iOS 16.1, *) {
            FocusActivityWidget()
        }
    }
}

@available(iOS 16.1, *)
struct FocusActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            // Lock screen/banner UI
            FocusLiveActivityView(context: context)
        } dynamicIsland: { (context: ActivityViewContext<FocusActivityAttributes>) in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .foregroundColor(.blue)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Interval")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if let total = context.state.totalIntervals {
                                    Text("\(context.state.currentInterval)/\(total)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                } else {
                                    Text("\(context.state.currentInterval)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        
                        // Countdown timer
                        if !context.state.isPaused {
                            HStack(spacing: 2) {
                                Image(systemName: "clock")
                                    .foregroundColor(.orange)
                                    .font(.caption2)
                                Text(context.state.nextAlertTime, style: .timer)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .id("expanded-\(context.state.updateCounter)") // Force refresh
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if context.state.isPaused {
                            HStack(spacing: 2) {
                                Image(systemName: "pause.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption2)
                                Text("Paused")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        } else {
                            Text("Next Alert")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(context.state.nextAlertTime, style: .time)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if context.state.isInCycleMode {
                                Text(context.state.currentCycleName ?? "Focus Cycle")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                if let cycleProgress = context.state.cycleProgress {
                                    Text("Cycle \(cycleProgress)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Focus Session")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        Spacer()
                        
                        Text("Started: \(context.attributes.startTime, style: .time)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundColor(.blue)
                    .font(.caption)
            } compactTrailing: {
                if context.state.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                } else {
                    // Show countdown timer
                    Text(context.state.nextAlertTime, style: .timer)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .monospacedDigit()
                        .id("timer-\(context.state.updateCounter)")
                }
            } minimal: {
                // Show interval count and countdown in minimal view
                if context.state.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                } else {
                    VStack(spacing: 0) {
                        Text("\(context.state.currentInterval)")
                            .font(.system(size: 8))
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        Text(context.state.nextAlertTime, style: .timer)
                            .font(.system(size: 7))
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                            .monospacedDigit()
                    }
                    .id("minimal-timer-\(context.state.updateCounter)")
                }
            }
        }
    }
}