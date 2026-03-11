import SwiftUI

struct PointsIndicatorView: View {
    let tasks: [Task]

    private var totalPoints: Double { tasks.reduce(0) { $0 + $1.weight } }
    private var completedPoints: Double { tasks.filter { $0.completed }.reduce(0) { $0 + $1.effectiveWeight } }
    private var percentage: Double { totalPoints > 0 ? (completedPoints / totalPoints) * 100 : 0 }

    private var pendingCount: Int { tasks.filter { !$0.completed && !$0.notCompleted }.count }
    private var completedCount: Int { tasks.filter { $0.completed }.count }
    private var totalCount: Int { tasks.count }

    private var color: Color {
        if percentage >= 80 { return .green }
        if percentage >= 50 { return .orange }
        return .red
    }

    var body: some View {
        HStack(spacing: 16) {
            // Task metrics — pending, completed, total (left side)
            HStack(spacing: 12) {
                metricBadge(systemImage: "minus.circle", value: pendingCount, color: .orange)
                metricBadge(systemImage: "checkmark.circle.fill", value: completedCount, color: .green)
                metricBadge(systemImage: "tray.full", value: totalCount, color: .secondary)
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
