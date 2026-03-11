import SwiftUI
import ActivityKit
import WidgetKit

@available(iOS 16.1, *)
struct FocusLiveActivityView: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    var taskName: String {
        context.state.currentCycleName ?? context.state.intervalName
    }

    var taskProgress: String? {
        if let total = context.state.totalIntervals {
            return "Task \(context.state.currentInterval) of \(total)"
        }
        return context.state.cycleProgress.map { "Task \($0)" }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.indigo)
                    .font(.headline)

                Text("Auto Schedule")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                if context.state.isPaused {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundColor(.orange)
                        Text("Paused")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            // Task name + progress
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(taskName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if let progress = taskProgress {
                        Text(progress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Time info
                VStack(alignment: .trailing, spacing: 4) {
                    if context.state.isPaused {
                        Text("Paused")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    } else {
                        Text("Ends")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(context.state.nextAlertTime, style: .time)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.indigo)
                    }

                    Text("Started \(context.attributes.startTime, style: .time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar
            if let total = context.state.totalIntervals, total > 0 {
                ProgressView(
                    value: Double(context.state.currentInterval),
                    total: Double(total)
                )
                .progressViewStyle(LinearProgressViewStyle(tint: .indigo))
                .scaleEffect(y: 0.8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}
