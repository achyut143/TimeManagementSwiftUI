import SwiftUI
import SwiftData

struct RestraintBarsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Restraint> { $0.isActive }) private var restraints: [Restraint]
    let isDark: Bool
    var onSelect: ((Restraint) -> Void)? = nil

    // lastReleaseWindow/nextReleaseWindow (Calendar-heavy: scans a 15-day
    // window per call) and currentPassStreak (walks day-by-day through
    // history) are all expensive and barely ever change — they only need
    // recomputing when a window boundary is crossed or new data is logged,
    // not every second. Cached here and refreshed at most once a minute;
    // the per-second TimelineView tick below only does cheap arithmetic
    // against these cached anchors, not full recomputation.
    private struct BarAnchor {
        let lastWindow: Date?
        let nextWindow: Date?
        let streak: Int
        let pending: Int
        // Precomputed here too — both used to involve their own
        // r.instances.first { ... } linear scan run every single tick.
        let quickLogTarget: (hour: Int, minute: Int, date: Date)?
        let abstinenceStatus: String // only meaningful when r.isAbstinence
    }
    @State private var cachedAnchors: [UUID: BarAnchor] = [:]
    @State private var anchorsRefreshedAt: Date = .distantPast

    // Fail prompt: asks "how much" before logging, then computes
    // awardedUsed/overusedAmount from what's entered against the item's
    // effective award — instead of logging a bare Fail with no numbers.
    private struct FailPromptTarget: Identifiable {
        let id = UUID()
        let restraint: Restraint
        let target: (hour: Int, minute: Int, date: Date)
    }
    @State private var failPrompt: FailPromptTarget?
    @State private var failAmountText: String = ""

    private var todayRestraints: [Restraint] {
        restraints.filter { $0.showInFocusWidget }
    }

    private var todayRestraintItems: [Restraint] { todayRestraints.filter { $0.kind == .restraint } }
    private var todayPracticeItems: [Restraint] { todayRestraints.filter { $0.kind == .practice } }

    private func refreshedAnchors(now: Date) -> [UUID: BarAnchor] {
        guard cachedAnchors.isEmpty || now.timeIntervalSince(anchorsRefreshedAt) >= 60 else {
            return cachedAnchors
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var next: [UUID: BarAnchor] = [:]
        for r in todayRestraints {
            let lastWindow = r.isAbstinence ? nil : r.lastReleaseWindow(at: now)
            let nextWindow = r.isAbstinence ? nil : r.nextReleaseWindow(at: now)

            var quickTarget: (hour: Int, minute: Int, date: Date)? = nil
            if let last = lastWindow {
                let day = cal.startOfDay(for: last)
                let hour = cal.component(.hour, from: last)
                let minute = cal.component(.minute, from: last)
                let record = r.instances.first { inst in
                    cal.isDate(inst.date, inSameDayAs: day) && inst.windowHour == hour && inst.windowMinute == minute
                }
                if record?.isPending ?? true { quickTarget = (hour, minute, day) }
            }

            let abstinenceStatus: String
            if r.isAbstinence {
                abstinenceStatus = r.instances.first { cal.isDate($0.date, inSameDayAs: today) }?.status ?? "pending"
            } else {
                abstinenceStatus = "pending"
            }

            next[r.id] = BarAnchor(
                lastWindow: lastWindow,
                nextWindow: nextWindow,
                streak: r.currentPassStreak(asOf: now),
                pending: pendingCount(for: r),
                quickLogTarget: quickTarget,
                abstinenceStatus: abstinenceStatus
            )
        }
        // Deferred so this pure-looking read doesn't mutate state mid-render;
        // the freshly computed values are still used immediately below.
        DispatchQueue.main.async {
            self.cachedAnchors = next
            self.anchorsRefreshedAt = now
        }
        return next
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let anchors = refreshedAnchors(now: now)
            let totalPending = todayRestraints.reduce(0) { $0 + (anchors[$1.id]?.pending ?? 0) }

            VStack(alignment: .leading, spacing: 12) {
                if todayRestraints.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption)
                            .foregroundColor(isDark ? .cyan.opacity(0.5) : .secondary)
                        Text("No rules scheduled today")
                            .font(.caption)
                            .foregroundColor(isDark ? .cyan.opacity(0.7) : .secondary)
                            .italic()
                    }
                    .padding(.vertical, 4)
                } else {
                    if totalPending > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("\(totalPending) pending")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                    }
                    kindGroup(.restraint, items: todayRestraintItems, anchors: anchors, now: now)
                    kindGroup(.practice, items: todayPracticeItems, anchors: anchors, now: now)
                }
            }
        }
        .alert(
            "How much?",
            isPresented: Binding(
                get: { failPrompt != nil },
                set: { if !$0 { failPrompt = nil; failAmountText = "" } }
            ),
            presenting: failPrompt
        ) { prompt in
            TextField("Amount (\(unit(for: prompt.restraint)))", text: $failAmountText)
                .keyboardType(.decimalPad)
            Button(prompt.restraint.kind.failWord) { commitFail(prompt) }
            Button("Cancel", role: .cancel) { failPrompt = nil; failAmountText = "" }
        } message: { prompt in
            Text("How much did you use? This is logged against \(prompt.restraint.name)'s \(fmt(effectiveAward(for: prompt))) \(unit(for: prompt.restraint)) award — anything over that counts as overused.")
        }
    }

    // Restraints and Practices are opposite mechanics (restrained-until-release
    // vs free-until-prompted), so they're grouped under their own labeled
    // sub-header instead of interleaved — the whole point of this widget being
    // able to tell at a glance which bars are which.
    @ViewBuilder
    private func kindGroup(_ kind: RestraintKind, items: [Restraint], anchors: [UUID: BarAnchor], now: Date) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(kind.pluralName.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(isDark ? .white.opacity(0.4) : .secondary)
                    .tracking(0.5)

                ForEach(items) { r in
                    let anchor = anchors[r.id] ?? BarAnchor(lastWindow: nil, nextWindow: nil, streak: 0, pending: 0, quickLogTarget: nil, abstinenceStatus: "pending")
                    Group {
                        if r.isAbstinence {
                            abstinenceBar(r, anchor: anchor, at: now)
                        } else {
                            restraintBar(r, anchor: anchor, at: now)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect?(r) }
                }
            }
        }
    }

    @ViewBuilder
    private func restraintBar(_ r: Restraint, anchor: BarAnchor, at now: Date) -> some View {
        // Cheap per-tick arithmetic against the cached anchor — no Calendar
        // rescans here, unlike calling r.holdProgress/timeHeld/timeUntilRelease
        // directly (each of which redoes the expensive window lookup itself).
        let held: TimeInterval = anchor.lastWindow.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let remaining: TimeInterval = anchor.nextWindow.map { max(0, $0.timeIntervalSince(now)) } ?? 0
        let progress: Double = {
            guard let last = anchor.lastWindow, let next = anchor.nextWindow else { return 0 }
            let total = next.timeIntervalSince(last)
            guard total > 0 else { return 0 }
            return min(max(now.timeIntervalSince(last) / total, 0), 1)
        }()
        let barColor = r.displayColor

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                kindIcon(r.kind)
                Image(systemName: r.iconName)
                    .font(.caption2)
                    .foregroundColor(barColor)
                Text(r.name.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(isDark ? .white : .primary)
                streakBadge(anchor.streak)
                if anchor.pending > 0 {
                    Text("\(anchor.pending)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                }
                Spacer()
                if let next = anchor.nextWindow {
                    Text("next: \(timeString(next))")
                        .font(.caption2)
                        .foregroundColor(isDark ? .white.opacity(0.5) : .secondary)
                }
            }

            // Native ProgressView instead of a GeometryReader-based custom bar —
            // GeometryReader forces an extra layout pass on every tick, which
            // adds up when it's re-solved once per second per restraint.
            ProgressView(value: progress)
                .tint(barColor)
                .frame(height: 7)

            HStack {
                Image(systemName: r.iconName)
                    .font(.caption2)
                    .foregroundColor(barColor)
                Text(formatInterval(held) + (r.kind == .restraint ? " held" : " since last"))
                    .font(.caption2)
                    .foregroundColor(barColor)
                Spacer()
                Text(formatIntervalWithSeconds(remaining) + (r.kind == .restraint ? " left" : " until next"))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            }

            if let target = anchor.quickLogTarget {
                quickLogButtons(r, target: target)
            }
        }
    }

    // Zero-tolerance restraints have no release window/progress concept —
    // just a daily Pass/Fail with a streak, and a quick way to log today.
    @ViewBuilder
    private func abstinenceBar(_ r: Restraint, anchor: BarAnchor, at now: Date) -> some View {
        let barColor = r.displayColor
        let today = Calendar.current.startOfDay(for: now)
        let status = anchor.abstinenceStatus

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                kindIcon(r.kind)
                Image(systemName: r.iconName)
                    .font(.caption2)
                    .foregroundColor(barColor)
                Text(r.name.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(isDark ? .white : .primary)
                streakBadge(anchor.streak)
                Text("ZERO-TOLERANCE")
                    .font(.system(size: 8))
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                Spacer()
                Text(status == "pass" ? "\(r.kind.passWord) today" : status == "fail" ? "\(r.kind.failWord) today" : "Pending")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(status == "pass" ? .green : status == "fail" ? .red : .orange)
            }

            if status == "pending" {
                quickLogButtons(r, target: (RestraintInstanceRow.abstinenceHour, RestraintInstanceRow.abstinenceMinute, today))
            }
        }
    }

    // Fixed semantic color/icon so which kind a bar is stays obvious even
    // though the item's own accent color (barColor) is fully user-chosen and
    // can't be relied on to signal that by itself.
    @ViewBuilder
    private func kindIcon(_ kind: RestraintKind) -> some View {
        Image(systemName: kind == .restraint ? "nosign" : "arrow.triangle.2.circlepath")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(kind == .restraint ? .red : .green)
    }

    @ViewBuilder
    private func streakBadge(_ streak: Int) -> some View {
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
    //
    // Pass/Done logs automatically — the full award is assumed used, nothing
    // to ask. Fail/Skipped prompts for how much was actually used so
    // awardedUsed/overusedAmount get computed instead of left at 0.
    // Zero-tolerance (abstinence) items have no award concept at all, so
    // both buttons log directly with no prompt either way.

    private func quickLogButtons(_ r: Restraint, target: (hour: Int, minute: Int, date: Date)) -> some View {
        HStack(spacing: 8) {
            Button {
                quickLogPass(r, target: target)
            } label: {
                Label(r.kind.passWord, systemImage: "checkmark")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .tint(.green)

            Button {
                if r.isAbstinence {
                    quickLogFailDirect(r, target: target)
                } else {
                    failAmountText = ""
                    failPrompt = FailPromptTarget(restraint: r, target: target)
                }
            } label: {
                Label(r.kind.failWord, systemImage: "xmark")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .controlSize(.mini)
    }

    private func findOrCreateInstance(_ r: Restraint, target: (hour: Int, minute: Int, date: Date)) -> RestraintInstance {
        let cal = Calendar.current
        if let existing = r.instances.first(where: { inst in
            cal.isDate(inst.date, inSameDayAs: target.date) && inst.windowHour == target.hour && inst.windowMinute == target.minute
        }) {
            return existing
        }
        let created = RestraintInstance(restraint: r, date: target.date, windowHour: target.hour, windowMinute: target.minute)
        modelContext.insert(created)
        return created
    }

    // Read-only lookup for the alert message — must NOT insert a model object
    // as a side effect of rendering (unlike commitFail, which is a genuine
    // user-initiated commit and is fine to create the instance then).
    private func effectiveAward(for prompt: FailPromptTarget) -> Double {
        let r = prompt.restraint
        let cal = Calendar.current
        if let existing = r.instances.first(where: { inst in
            cal.isDate(inst.date, inSameDayAs: prompt.target.date) && inst.windowHour == prompt.target.hour && inst.windowMinute == prompt.target.minute
        }) {
            return r.effectiveAward(for: existing)
        }
        if let window = r.timeWindows.first(where: { $0.hour == prompt.target.hour && $0.minute == prompt.target.minute }) {
            return r.effectiveAward(for: window)
        }
        return r.effectiveLimitType == .duration ? Double(r.awardedMinutes) : r.quantityLimit
    }

    private func unit(for r: Restraint) -> String {
        r.effectiveLimitType == .duration ? "min" : r.quantityUnit
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }

    private func quickLogPass(_ r: Restraint, target: (hour: Int, minute: Int, date: Date)) {
        let rec = findOrCreateInstance(r, target: target)
        rec.status = "pass"
        if !r.isAbstinence {
            // Auto-log the full award as used — a clean Pass means the
            // allowance was used as intended, nothing over.
            rec.awardedUsed = r.effectiveAward(for: rec)
            rec.overusedAmount = 0
        }
        try? modelContext.save()
        anchorsRefreshedAt = .distantPast
    }

    private func quickLogFailDirect(_ r: Restraint, target: (hour: Int, minute: Int, date: Date)) {
        let rec = findOrCreateInstance(r, target: target)
        rec.status = "fail"
        try? modelContext.save()
        anchorsRefreshedAt = .distantPast
    }

    private func commitFail(_ prompt: FailPromptTarget) {
        let r = prompt.restraint
        let rec = findOrCreateInstance(r, target: prompt.target)
        rec.status = "fail"
        // Blank/invalid entry falls back to 0/0 — same as just logging a
        // bare Fail — rather than blocking the log entirely.
        let entered = Double(failAmountText.trimmingCharacters(in: .whitespaces)) ?? 0
        let award = r.effectiveAward(for: rec)
        rec.awardedUsed = min(entered, award)
        rec.overusedAmount = max(0, entered - award)
        try? modelContext.save()
        anchorsRefreshedAt = .distantPast
        failPrompt = nil
        failAmountText = ""
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
