import WidgetKit
import SwiftUI
import ActivityKit
import Foundation

@main
struct FocusFlowWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Control Widget (existing)
        FocusFlowWidgetsControl()
        
        // Live Activity Widgets
        if #available(iOS 16.1, *) {
            FocusActivityWidget()
            BackgroundCounterActivityWidget()
            ActivityTimerWidget()
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
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.currentCycleName ?? context.state.intervalName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text("Interval \(context.state.currentInterval)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPaused {
                        Text("Paused")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    } else if context.state.nextAlertTime.timeIntervalSinceNow > 0 {
                        Text(context.state.nextAlertTime, style: .timer)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.indigo)
                            .monospacedDigit()
                    } else {
                        Text("Done")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                }
            } compactLeading: {
                Text("\(context.state.currentInterval)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.indigo)
            } compactTrailing: {
                if context.state.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                } else if context.state.nextAlertTime.timeIntervalSinceNow > 0 {
                    Text(context.state.nextAlertTime, style: .timer)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.indigo)
                        .monospacedDigit()
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            } minimal: {
                Text("\(context.state.currentInterval)")
                    .font(.system(size: 12))
                    .fontWeight(.bold)
                    .foregroundColor(.indigo)
            }
        }
    }
}


@available(iOS 16.1, *)
struct BackgroundCounterActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BackgroundCounterAttributes.self) { context in
            // Lock screen/banner UI
            BackgroundCounterLiveActivityView(context: context)
        } dynamicIsland: { (context: ActivityViewContext<BackgroundCounterAttributes>) in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("Session")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // Live counting timer
                        if let startTime = context.state.backgroundStartTime {
                            Text(startTime, style: .timer)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .monospacedDigit()
                        } else {
                            Text(formattedTime(context.state.currentSessionTime))
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .monospacedDigit()
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Total")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(formattedTime(context.state.totalBackgroundTime))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                            .monospacedDigit()
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.isCountingInBackground {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("Counting in background")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("Background time tracker")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if let startTime = context.state.backgroundStartTime {
                            Text("Started: \(startTime, style: .time)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.blue)
                    .font(.caption)
            } compactTrailing: {
                // Live counting timer in compact view
                if let startTime = context.state.backgroundStartTime {
                    Text(startTime, style: .timer)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .monospacedDigit()
                } else {
                    Text(formattedTime(context.state.currentSessionTime))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.blue)
                    .font(.caption2)
            }
        }
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


@available(iOS 16.1, *)
struct ActivityTimerWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActivityTimerAttributes.self) { context in
            // Lock screen/banner UI
            ActivityTimerLiveActivityView(context: context)
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { (context: ActivityViewContext<ActivityTimerAttributes>) in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(context.attributes.activityName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        
                        // Countdown timer
                        if !context.state.isPaused && context.state.endTime.timeIntervalSinceNow > 0 {
                            Text(context.state.endTime, style: .timer)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .monospacedDigit()
                        } else if context.state.isPaused {
                            Text(formattedTime(context.state.remainingSeconds))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.yellow)
                                .monospacedDigit()
                        } else {
                            Text("Done")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if context.state.isPaused {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 6, height: 6)
                                Text("Paused")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("Running")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        // Progress percentage
                        let progress = context.state.remainingSeconds / context.attributes.totalDuration
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(context.state.isPaused ? .yellow : .orange)
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Total: \(formattedTime(context.attributes.totalDuration))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if !context.state.isPaused {
                            Text("Ends: \(context.state.endTime, style: .time)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundColor(.orange)
                    .font(.caption)
            } compactTrailing: {
                if context.state.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                } else {
                    Text(context.state.endTime, style: .timer)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .monospacedDigit()
                }
            } minimal: {
                if context.state.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.yellow)
                        .font(.caption2)
                } else {
                    Image(systemName: "timer")
                        .foregroundColor(.orange)
                        .font(.caption2)
                }
            }
        }
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
