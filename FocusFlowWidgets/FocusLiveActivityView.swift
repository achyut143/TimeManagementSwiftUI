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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(taskName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("Interval \(context.state.currentInterval)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if context.state.isPaused {
                Text("Paused")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            } else {
                Text(context.state.nextAlertTime, style: .timer)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.indigo)
                    .monospacedDigit()
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}
