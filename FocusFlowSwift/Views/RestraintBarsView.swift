import SwiftUI
import SwiftData

struct RestraintBarsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Restraint> { $0.isActive }) private var restraints: [Restraint]
    let isDark: Bool
    var onSelect: ((Restraint) -> Void)? = nil

    private var todayRestraints: [Restraint] {
        restraints.filter { $0.showInFocusWidget }
    }

    // Today's release windows for one restraint whose time has already passed but
    // haven't been marked pass/fail yet — same "pending" definition RestraintInstancesView
    // uses (no record, or an explicit "pending" record).
    private func pendingCount(for r: Restraint) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let now = Date()
        guard r.isScheduledOn(date: today) else { return 0 }

        if r.isAbstinence {
            let record = r.instances.first { cal.isDate($0.date, inSameDayAs: today) }
            return (record?.isPending ?? true) ? 1 : 0
        }

        var count = 0
        for window in r.timeWindows {
            var comps = cal.dateComponents([.year, .month, .day], from: today)
            comps.hour = window.hour
            comps.minute = window.minute
            guard let windowDate = cal.date(from: comps), windowDate <= now else { continue }
            let record = r.instances.first { inst in
                cal.isDate(inst.date, inSameDayAs: today)
                    && inst.windowHour == window.hour
                    && inst.windowMinute == window.minute
            }
            if record?.isPending ?? true { count += 1 }
        }
        return count
    }

    private var pendingCount: Int {
        todayRestraints.reduce(0) { $0 + pendingCount(for: $1) }
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
                    if pendingCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("\(pendingCount) pending")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                    }
                    ForEach(todayRestraints) { r in
                        Group {
                            if r.isAbstinence {
                                abstinenceBar(r, at: now)
                            } else {
                                restraintBar(r, at: now)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect?(r) }
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
                streakBadge(r)
                let restraintPending = pendingCount(for: r)
                if restraintPending > 0 {
                    Text("\(restraintPending)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                }
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

            if let target = quickLogTarget(for: r, at: now) {
                quickLogButtons(r, target: target)
            }
        }
    }

    // Zero-tolerance restraints have no release window/progress concept —
    // just a daily Pass/Fail with a streak, and a quick way to log today.
    @ViewBuilder
    private func abstinenceBar(_ r: Restraint, at now: Date) -> some View {
        let barColor = r.displayColor
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let record = r.instances.first { cal.isDate($0.date, inSameDayAs: today) }
        let status = record?.status ?? "pending"

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: r.iconName)
                    .font(.caption2)
                    .foregroundColor(barColor)
                Text(r.name.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(isDark ? .white : .primary)
                streakBadge(r)
                Text("ZERO-TOLERANCE")
                    .font(.system(size: 8))
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                Spacer()
                Text(status == "pass" ? "Passed today" : status == "fail" ? "Failed today" : "Pending")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(status == "pass" ? .green : status == "fail" ? .red : .orange)
            }

            if status == "pending" {
                quickLogButtons(r, target: (RestraintInstanceRow.abstinenceHour, RestraintInstanceRow.abstinenceMinute, today))
            }
        }
    }

    @ViewBuilder
    private func streakBadge(_ r: Restraint) -> some View {
        let streak = r.currentPassStreak()
        if streak > 0 {
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                Text("\(streak)")
            }
            .font(.system(size: 9))
            .fontWeight(.bold)
            .foregroundColor(.orange)
        }
    }

    // MARK: - Quick logging (#9): act on the current pending window/day right
    // from the widget instead of always opening the full Log Instance sheet.

    private func quickLogTarget(for r: Restraint, at now: Date) -> (hour: Int, minute: Int, date: Date)? {
        guard let last = r.lastReleaseWindow(at: now) else { return nil }
        let cal = Calendar.current
        let day = cal.startOfDay(for: last)
        let hour = cal.component(.hour, from: last)
        let minute = cal.component(.minute, from: last)
        let record = r.instances.first { inst in
            cal.isDate(inst.date, inSameDayAs: day) && inst.windowHour == hour && inst.windowMinute == minute
        }
        guard record?.isPending ?? true else { return nil }
        return (hour, minute, day)
    }

    private func quickLogButtons(_ r: Restraint, target: (hour: Int, minute: Int, date: Date)) -> some View {
        HStack(spacing: 8) {
            Button {
                quickLog(r, status: "pass", target: target)
            } label: {
                Label("Pass", systemImage: "checkmark")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .tint(.green)

            Button {
                quickLog(r, status: "fail", target: target)
            } label: {
                Label("Fail", systemImage: "xmark")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .controlSize(.mini)
    }

    private func quickLog(_ r: Restraint, status: String, target: (hour: Int, minute: Int, date: Date)) {
        let cal = Calendar.current
        let existing = r.instances.first { inst in
            cal.isDate(inst.date, inSameDayAs: target.date) && inst.windowHour == target.hour && inst.windowMinute == target.minute
        }
        let rec: RestraintInstance
        if let existing {
            rec = existing
        } else {
            rec = RestraintInstance(restraint: r, date: target.date, windowHour: target.hour, windowMinute: target.minute)
            modelContext.insert(rec)
        }
        rec.status = status
        try? modelContext.save()
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
