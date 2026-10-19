import SwiftUI
import SwiftData

/// Live "what's currently running" indicator shown at the end of the points
/// row on the calendar. Priority: Start/End (main schedule), then Begin/Stop,
/// then whichever calendar task is active right now — falls back to a plain
/// "open Focus Mode" button when none of the three are active. Always
/// reflects the actual current moment (today, now), independent of whatever
/// day is being browsed on the calendar.
///
/// All three mechanics are read directly from source data (note text /
/// SwiftData `Task` rows) rather than from `AlertSettings`, which only
/// advances while Daily Notes/Focus Mode is actually mounted — so this stays
/// correct even when the user is sitting on the Task Calendar the whole time
/// a task starts. It runs its own acknowledgment nag (speech + persisted via
/// `AcknowledgmentStore`, the same store Daily Notes/Focus Mode use — see
/// `AcknowledgmentStore.startEndIdentifier` for how the Start/End key is kept
/// in agreement with `DailyNotesView`'s own `AlertSettings`-driven copy) and
/// reports pending/acknowledged state up via `onPendingChange` so the caller
/// can show a full-width "tap to acknowledge" banner, matching Focus Mode's.
///
/// Deliberately its own view with its own 1-second timer and its own
/// `@Query`s, rather than state living on `TasksCalendarView` itself: a
/// ticking `@State` there would re-evaluate that entire view's body every
/// second, including every `.sheet` it presents — which was resetting the
/// Edit Task date picker's displayed month on every tick while browsing.
/// Isolating the ticker here keeps that per-second churn local to this view;
/// `onPendingChange` only fires on the rare occasions the pending state
/// actually flips, not every tick.
struct FocusTimerIndicatorView: View {
    let onOpenFocusMode: () -> Void
    var onPendingChange: (_ isPending: Bool, _ taskName: String, _ color: Color, _ acknowledge: @escaping () -> Void) -> Void = { _, _, _, _ in }

    @Query private var dailyNotesForFocusWidget: [DailyNote]
    @Query private var allTasksForFocusWidget: [Task]
    @State private var now = Date()
    @State private var tickTimer: Timer?

    @State private var isPendingAck = false
    @State private var pendingName = ""
    @State private var pendingColor: Color = .indigo
    @State private var ackTimer: Timer?
    @State private var lastAnnouncedKey: String?

    private struct Occurrence {
        let key: String
        let name: String
        let remaining: TimeInterval
        let color: Color
        let icon: String
    }

    private var current: Occurrence? {
        // 1) Start/End (main schedule) — parsed live from today's note text.
        if let entry = activeEntry(startTag: "START", endTag: "END"), let endMin = entry.endMinutes {
            let end = date(forMinutes: endMin)
            let name = entry.task ?? "Task"
            return Occurrence(
                key: AcknowledgmentStore.startEndIdentifier(taskName: name, endDate: end),
                name: name,
                remaining: max(0, end.timeIntervalSince(now)),
                color: .indigo,
                icon: "sparkles"
            )
        }

        // 2) Begin/Stop (second schedule).
        if let entry = activeEntry(startTag: "BEGIN", endTag: "STOP"), let endMin = entry.endMinutes {
            return Occurrence(
                key: "beginstop:\(entry.raw)",
                name: entry.task ?? "Session",
                remaining: max(0, date(forMinutes: endMin).timeIntervalSince(now)),
                color: .green,
                icon: "hourglass"
            )
        }

        // 3) Whichever calendar task is active right now.
        if let task = activeCalendarTask {
            return Occurrence(
                key: "task:\(task.id.uuidString)",
                name: task.title,
                remaining: max(0, date(forMinutes: timeToMinutes(task.endTime)).timeIntervalSince(now)),
                color: .blue,
                icon: "calendar"
            )
        }

        return nil
    }

    private func date(forMinutes minutes: Int) -> Date {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        return cal.date(byAdding: .minute, value: minutes, to: base) ?? base
    }

    private var todayNoteContent: String {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return dailyNotesForFocusWidget.first { Calendar.current.isDate($0.date, inSameDayAs: startOfDay) }?.content ?? ""
    }

    private func activeEntry(startTag: String, endTag: String) -> ScheduleEntry? {
        let entries = ScheduleEntry.parse(from: todayNoteContent, startTag: startTag, endTag: endTag)
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        return entries.first { e in
            guard !e.isStruck, let sm = e.startMinutes, let em = e.endMinutes else { return false }
            return nowMin >= sm && nowMin < em
        }
    }

    private var activeCalendarTask: Task? {
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        return allTasksForFocusWidget.first { t in
            guard !t.startTime.isEmpty, !t.endTime.isEmpty,
                  let d = t.date, cal.isDateInToday(d) else { return false }
            let s = timeToMinutes(t.startTime)
            let e = timeToMinutes(t.endTime)
            return nowMin >= s && nowMin < e
        }
    }

    private func timeToMinutes(_ timeStr: String) -> Int {
        let clean = timeStr.trimmingCharacters(in: .whitespaces)
        let parts = clean.components(separatedBy: ":")
        guard parts.count >= 2,
              let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return 0 }
        return h * 60 + m
    }

    private func formatRemaining(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Acknowledgment

    private func checkAcknowledgment() {
        guard let occurrence = current else {
            lastAnnouncedKey = nil
            if isPendingAck { silenceLocally() }
            return
        }

        // Re-checked every tick (not just when the key first changes) so that
        // if this same occurrence gets acknowledged from elsewhere — Daily
        // Notes/Focus Mode can be open as a sheet on top of this tab at the
        // same time, both still ticking — this surface's own nag notices and
        // stops within about a second, instead of continuing independently.
        if AcknowledgmentStore.isAcknowledged(date: Date(), identifier: occurrence.key) {
            if isPendingAck && lastAnnouncedKey == occurrence.key { silenceLocally() }
            lastAnnouncedKey = occurrence.key
            return
        }

        guard occurrence.key != lastAnnouncedKey else { return }
        lastAnnouncedKey = occurrence.key
        pendingName = occurrence.name
        pendingColor = occurrence.color
        beginAckLoop()
    }

    private func beginAckLoop() {
        ackTimer?.invalidate()
        isPendingAck = true
        SpeechManager.shared.speak("\(pendingName) started. Please acknowledge.")
        onPendingChange(true, pendingName, pendingColor, acknowledge)
        ackTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { _ in
            guard isPendingAck else { return }
            SpeechManager.shared.speak("\(pendingName) started. Please acknowledge.")
        }
    }

    /// Stops this surface's own nag without writing to the store — used when
    /// the occurrence was acknowledged elsewhere, so there's nothing new to
    /// persist here.
    private func silenceLocally() {
        isPendingAck = false
        ackTimer?.invalidate()
        ackTimer = nil
        SpeechManager.shared.stopSpeaking()
        onPendingChange(false, "", pendingColor, {})
    }

    /// User tapped this surface's own acknowledge banner/button.
    private func acknowledge() {
        guard isPendingAck else { return }
        if let key = lastAnnouncedKey {
            AcknowledgmentStore.acknowledge(date: Date(), identifier: key)
        }
        silenceLocally()
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isPendingAck {
                // The parent shows the full-width banner (see onPendingChange)
                // — nothing to render in this compact trailing slot while pending.
                EmptyView()
            } else if let current {
                Button(action: onOpenFocusMode) {
                    HStack(spacing: 4) {
                        Image(systemName: current.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(formatRemaining(current.remaining))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(current.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(current.color.opacity(0.15))
                    .clipShape(Capsule())
                }
            } else {
                Button(action: onOpenFocusMode) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.indigo)
                }
            }
        }
        .onAppear {
            tickTimer?.invalidate()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                now = Date()
                checkAcknowledgment()
            }
            RunLoop.current.add(tickTimer!, forMode: .common)
            checkAcknowledgment()
        }
        .onDisappear {
            tickTimer?.invalidate()
            tickTimer = nil
            ackTimer?.invalidate()
            ackTimer = nil
        }
    }
}
