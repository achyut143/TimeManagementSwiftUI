import Foundation

/// Persists "the user has already acknowledged this task/session starting"
/// across view teardown/recreation — closing and reopening Daily Notes or
/// Focus Mode — and across app relaunches, so the same still-in-progress
/// occurrence doesn't re-trigger the "please acknowledge" nag every time
/// those views reappear.
///
/// Backed by UserDefaults rather than embedded in the note text: a Task-row
/// occurrence (the Calendar Task widget) has no note line to embed a marker
/// into at all, and a schedule gap-filler ("Rest up") isn't a real note line
/// either, so a single uniform mechanism keyed by day + a caller-supplied
/// stable identifier covers all three acknowledgment mechanics without any
/// regex/parsing risk to the schedule text itself.
enum AcknowledgmentStore {
    private static let defaultsKey = "AcknowledgmentStore.acknowledged"
    // Entries older than this are pruned on every write so the set doesn't
    // grow unbounded over the life of the app.
    private static let retentionDays = 14

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private static func entryKey(date: Date, identifier: String) -> String {
        "\(dayKey(date))|\(identifier)"
    }

    static func isAcknowledged(date: Date, identifier: String) -> Bool {
        let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        return stored.contains(entryKey(date: date, identifier: identifier))
    }

    static func acknowledge(date: Date, identifier: String) {
        var stored = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
        stored.insert(entryKey(date: date, identifier: identifier))
        UserDefaults.standard.set(Array(prune(stored)), forKey: defaultsKey)
    }

    private static func prune(_ set: Set<String>) -> Set<String> {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return set }
        let cutoffKey = dayKey(cutoff)
        return set.filter { entry in
            guard let day = entry.components(separatedBy: "|").first else { return true }
            return day >= cutoffKey
        }
    }

    /// Identifier for a Start/End (main smart-cycle) occurrence, derivable
    /// from either side that needs it: DailyNotesView's `AlertSettings`-driven
    /// engine (`activeTaskName` + `nextAlertDate`), or a passive reader that
    /// independently parses the same START...END block from note text
    /// (`TasksCalendarView`'s Focus timer indicator, via `ScheduleEntry`).
    /// Both ultimately describe the same real end-of-occurrence clock time,
    /// just computed by different code paths — rounding to the minute
    /// absorbs any sub-minute jitter between the two so they agree on the
    /// same key for the same real occurrence.
    static func startEndIdentifier(taskName: String, endDate: Date) -> String {
        "\(taskName)@\(Int(endDate.timeIntervalSince1970 / 60))"
    }
}
