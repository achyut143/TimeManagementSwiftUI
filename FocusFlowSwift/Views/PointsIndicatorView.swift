import SwiftUI

struct PointsIndicatorView: View {
    let tasks: [Task]

    var body: some View {
        // Single pass over tasks — compute all metrics once per render
        var totalPoints = 0.0
        var completedPoints = 0.0
        var inProgress = 0
        var pending = 0
        var completed = 0
        for task in tasks {
            totalPoints += task.weight
            if task.completed {
                completedPoints += task.effectiveWeight
                completed += 1
            } else if !task.notCompleted {
                if (task.timeSpent ?? 0) > 0 { inProgress += 1 }
                else { pending += 1 }
            }
        }
        let percentage = totalPoints > 0 ? (completedPoints / totalPoints) * 100 : 0.0
        let color: Color = percentage >= 80 ? .green : (percentage >= 50 ? .orange : .red)

        return HStack(spacing: 16) {
            // Task metrics — pending, completed, total (left side)
            HStack(spacing: 12) {
                metricBadge(systemImage: "minus.circle", value: pending, color: .secondary)
                if inProgress > 0 {
                    metricBadge(systemImage: "clock.fill", value: inProgress, color: .orange)
                }
                metricBadge(systemImage: "checkmark.circle.fill", value: completed, color: .green)
                metricBadge(systemImage: "tray.full", value: tasks.count, color: .blue)
            }

            Divider()
                .frame(height: 24)

            // Points (right side)
            HStack(spacing: 4) {
                Text("\(String(format: "%.1f", completedPoints))/\(Int(totalPoints))")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                Text("(\(Int(percentage))%)")
                    .font(.subheadline)
                    .foregroundColor(color)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func metricBadge(systemImage: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundColor(color)
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
}
