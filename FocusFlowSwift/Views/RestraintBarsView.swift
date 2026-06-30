import SwiftUI
import SwiftData

struct RestraintBarsView: View {
    @Query(filter: #Predicate<Restraint> { $0.isActive }) private var restraints: [Restraint]
    let isDark: Bool

    private var todayRestraints: [Restraint] {
        restraints.filter { !$0.timeWindows.isEmpty }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 12) {
                if todayRestraints.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption)
                            .foregroundColor(isDark ? .cyan.opacity(0.5) : .secondary)
                        Text("No restraints scheduled today")
                            .font(.caption)
                            .foregroundColor(isDark ? .cyan.opacity(0.7) : .secondary)
                            .italic()
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(todayRestraints) { r in
                        restraintBar(r, at: now)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func restraintBar(_ r: Restraint, at now: Date) -> some View {
        let progress   = r.holdProgress(at: now)
        let held       = r.timeHeld(at: now)
        let remaining  = r.timeUntilRelease(at: now)
        let nextWindow = r.nextReleaseWindow(at: now)
        let barColor   = r.displayColor

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: r.iconName)
                    .font(.caption2)
                    .foregroundColor(barColor)
                Text(r.name.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(isDark ? .white : .primary)
                Spacer()
                if let next = nextWindow {
                    Text("next: \(timeString(next))")
                        .font(.caption2)
                        .foregroundColor(isDark ? .white.opacity(0.5) : .secondary)
                }
            }

            RoundedRectangle(cornerRadius: 4)
                .fill(isDark ? Color.white.opacity(0.12) : Color(.systemGray5))
                .frame(height: 7)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor)
                            .frame(width: geo.size.width * progress)
                    }
                }

            HStack {
                Image(systemName: r.iconName)
                    .font(.caption2)
                    .foregroundColor(barColor)
                Text(formatInterval(held) + " held")
                    .font(.caption2)
                    .foregroundColor(barColor)
                Spacer()
                Text(formatIntervalWithSeconds(remaining) + " left")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let disp = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        let ampm = h < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", disp, m, ampm)
    }

    private func formatInterval(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private func formatIntervalWithSeconds(_ t: TimeInterval) -> String {
        let total = Int(max(t, 0))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
