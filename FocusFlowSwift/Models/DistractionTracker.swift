import Foundation

/// Tracks how many times the user left the app / closed Daily Notes while a task was active,
/// and the total time they spent away from each task — correctly split across task boundaries.
class DistractionTracker: ObservableObject {
    static let shared = DistractionTracker()

    private let countKey       = "DistractionTracker.counts"
    private let durationKey    = "DistractionTracker.durations"
    private let exitTimeKey    = "DistractionTracker.pendingExitTime"
    private let exitKeyKey     = "DistractionTracker.pendingExitKey"
    private let exitScheduleKey = "DistractionTracker.pendingExitSchedule"
    private let whitelistKey   = "DistractionTracker.taskWhitelist"

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Private storage

    private var counts: [String: Int] {
        get { UserDefaults.standard.object(forKey: countKey) as? [String: Int] ?? [:] }
        set {
            UserDefaults.standard.set(newValue, forKey: countKey)
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    private var durations: [String: Double] {
        get { UserDefaults.standard.object(forKey: durationKey) as? [String: Double] ?? [:] }
        set {
            UserDefaults.standard.set(newValue, forKey: durationKey)
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    private var pendingExitTime: Date? {
        get { UserDefaults.standard.object(forKey: exitTimeKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: exitTimeKey) }
    }
    private var pendingExitKey: String? {
        get { UserDefaults.standard.string(forKey: exitKeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: exitKeyKey) }
    }
    /// Stored as [[String: Any]] with keys "s" (startMin), "e" (endMin), "d" (desc).
    private var pendingExitSchedule: [(startMin: Int, endMin: Int, desc: String)] {
        get {
            guard let raw = UserDefaults.standard.array(forKey: exitScheduleKey) as? [[String: Any]]
            else { return [] }
            return raw.compactMap {
                guard let s = $0["s"] as? Int,
                      let e = $0["e"] as? Int,
                      let d = $0["d"] as? String
                else { return nil }
                return (s, e, d)
            }
        }
        set {
            let raw = newValue.map { ["s": $0.startMin, "e": $0.endMin, "d": $0.desc] as [String: Any] }
            UserDefaults.standard.set(raw, forKey: exitScheduleKey)
        }
    }

    // MARK: - Key

    func makeKey(date: Date, startMin: Int, desc: String) -> String {
        "\(dateFormatter.string(from: date))|\(startMin)|\(desc)"
    }

    // MARK: - Whitelist
    // Comma-separated task names. Empty means "track everything" (the original,
    // unfiltered behavior). Centralized here — rather than in any one view — so every
    // consumer of this tracker (Daily Notes, Focus Mode, the schedule generator, etc.)
    // is automatically consistent about which tasks get tracked.

    var whitelistRaw: String {
        get { UserDefaults.standard.string(forKey: whitelistKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: whitelistKey)
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    private var whitelist: Set<String> {
        Set(whitelistRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }

    /// Strips parenthetical detail so "work (office)" is treated as "work".
    private func baseTaskName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\([^()]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    func isTracked(_ taskName: String) -> Bool {
        let list = whitelist
        guard !list.isEmpty else { return true }
        return list.contains(baseTaskName(taskName).lowercased())
    }

    // MARK: - Count API

    func increment(date: Date, startMin: Int, desc: String) {
        var c = counts
        let k = makeKey(date: date, startMin: startMin, desc: desc)
        c[k] = (c[k] ?? 0) + 1
        counts = c
    }

    func count(date: Date, startMin: Int, desc: String) -> Int {
        counts[makeKey(date: date, startMin: startMin, desc: desc)] ?? 0
    }

    func countByTitle(date: Date, title: String) -> Int {
        guard !title.isEmpty else { return 0 }
        let prefix = "\(dateFormatter.string(from: date))|"
        return counts
            .filter { key, _ in
                guard key.hasPrefix(prefix) else { return false }
                let parts = key.components(separatedBy: "|")
                return parts.count >= 3 && parts[2] == title
            }
            .values.reduce(0, +)
    }

    // MARK: - Duration API

    func duration(date: Date, startMin: Int, desc: String) -> TimeInterval {
        durations[makeKey(date: date, startMin: startMin, desc: desc)] ?? 0
    }

    /// Directly overwrites the stored duration for a slot (manual edit from the task
    /// sheet), leaving its distraction count untouched.
    func setDuration(date: Date, startMin: Int, desc: String, seconds: TimeInterval) {
        var d = durations
        let k = makeKey(date: date, startMin: startMin, desc: desc)
        if seconds > 0 {
            d[k] = seconds
        } else {
            d.removeValue(forKey: k)
        }
        durations = d
    }

    func durationByTitle(date: Date, title: String) -> TimeInterval {
        guard !title.isEmpty else { return 0 }
        let prefix = "\(dateFormatter.string(from: date))|"
        return durations
            .filter { key, _ in
                guard key.hasPrefix(prefix) else { return false }
                let parts = key.components(separatedBy: "|")
                return parts.count >= 3 && parts[2] == title
            }
            .values.reduce(0, +)
    }

    private func addDuration(_ interval: TimeInterval, forKey k: String) {
        guard interval > 0 else { return }
        var d = durations
        d[k] = (d[k] ?? 0) + interval
        durations = d
    }

    // MARK: - Exit / Return tracking

    var hasPendingExit: Bool { pendingExitTime != nil }

    var pendingAbsenceSeconds: TimeInterval {
        guard let t = pendingExitTime else { return 0 }
        return Date().timeIntervalSince(t)
    }

    func cancelPendingExit() {
        pendingExitTime     = nil
        pendingExitKey      = nil
        pendingExitSchedule = []
    }

    /// Call when the user leaves DailyNotes or backgrounds the app.
    /// `schedule` is the full non-struck task list so that on return we can split time across boundaries.
    /// No-ops entirely if `desc` isn't whitelisted; non-whitelisted entries are also
    /// dropped from `schedule` so they can never get swept in as a "subsequent task"
    /// during a long absence either.
    func recordExit(date: Date, startMin: Int, desc: String,
                    schedule: [(startMin: Int, endMin: Int, desc: String)]) {
        guard isTracked(desc) else { return }
        pendingExitTime     = Date()
        pendingExitKey      = makeKey(date: date, startMin: startMin, desc: desc)
        pendingExitSchedule = schedule.filter { isTracked($0.desc) }
    }

    /// Call when the user returns to DailyNotes or the app comes to foreground.
    ///
    /// Splits the elapsed absence time across every task whose window was active during the absence.
    /// Returns one entry per affected task so the caller can refresh their notes lines.
    /// Returns an empty array if no exit was pending.
    ///
    /// - Parameter selectedDate: Used to convert startMin/endMin integers to wall-clock Dates.
    func settleReturn(selectedDate: Date) -> [(date: Date, startMin: Int, desc: String)] {
        guard let exitTime = pendingExitTime, let key = pendingExitKey else { return [] }

        let returnTime = Date()
        let schedule   = pendingExitSchedule

        // Clear persisted state immediately
        pendingExitTime     = nil
        pendingExitKey      = nil
        pendingExitSchedule = []

        // Parse the exit key back into components
        let parts = key.components(separatedBy: "|")
        guard parts.count >= 3,
              let exitStartMin = Int(parts[1]),
              let exitDate     = dateFormatter.date(from: parts[0])
        else { return [] }
        let exitDesc = parts[2]

        // Find the exit task in the schedule to get its endMin
        let exitTask = schedule.first { $0.startMin == exitStartMin && $0.desc == exitDesc }

        // Helper: convert a minute-of-day integer to a wall-clock Date on selectedDate.
        // Minutes >= 1440 are treated as crossing midnight into the next day.
        func wallDate(_ minutes: Int) -> Date {
            let base = Calendar.current.startOfDay(for: selectedDate)
            return base.addingTimeInterval(TimeInterval(minutes * 60))
        }

        var results: [(date: Date, startMin: Int, desc: String)] = []

        // --- Attribute the exit task ---
        let exitEndWall: Date
        if let et = exitTask {
            exitEndWall = wallDate(et.endMin)
        } else {
            // Unknown end — cap at return time
            exitEndWall = returnTime
        }
        let exitSliceEnd = min(exitEndWall, returnTime)
        let exitElapsed  = exitSliceEnd.timeIntervalSince(exitTime)
        addDuration(exitElapsed, forKey: key)
        results.append((date: exitDate, startMin: exitStartMin, desc: exitDesc))

        // --- Attribute subsequent tasks whose windows overlapped the absence ---
        // Walk tasks that start after the exit task, in order.
        var cursor = exitSliceEnd
        let subsequentTasks = schedule
            .filter { $0.startMin > exitStartMin }
            .sorted { $0.startMin < $1.startMin }

        for task in subsequentTasks {
            guard cursor < returnTime else { break }
            let taskStartWall = wallDate(task.startMin)
            let taskEndWall   = wallDate(task.endMin)
            guard taskEndWall > cursor else { continue }   // window already passed

            // Move cursor to the task's start if there was a gap
            let sliceStart = max(cursor, taskStartWall)
            guard sliceStart < returnTime else { break }

            let sliceEnd  = min(taskEndWall, returnTime)
            let elapsed   = sliceEnd.timeIntervalSince(sliceStart)
            let taskKey   = makeKey(date: exitDate, startMin: task.startMin, desc: task.desc)

            // Increment count — the user was absent during this task's window
            var c = counts
            c[taskKey] = (c[taskKey] ?? 0) + 1
            counts = c

            addDuration(elapsed, forKey: taskKey)
            results.append((date: exitDate, startMin: task.startMin, desc: task.desc))
            cursor = sliceEnd
        }

        DispatchQueue.main.async { self.objectWillChange.send() }
        return results
    }

    // MARK: - Day totals

    /// Returns (totalCount, totalSeconds) summed across every WHITELISTED task on the
    /// given date (or every task, if the whitelist is empty). Filtering here — not just
    /// at recordExit — also protects against stale data left over from before a
    /// whitelist was set, or from recalculateFromNotes re-syncing straight off markers
    /// already embedded in the notes text.
    func dayTotals(date: Date) -> (count: Int, seconds: TimeInterval) {
        let prefix = "\(dateFormatter.string(from: date))|"
        func matches(_ key: String) -> Bool {
            guard key.hasPrefix(prefix) else { return false }
            let parts = key.components(separatedBy: "|")
            guard parts.count >= 3 else { return false }
            return isTracked(parts[2])
        }
        let totalCount = counts.filter { matches($0.key) }.values.reduce(0, +)
        let totalSecs  = durations.filter { matches($0.key) }.values.reduce(0, +)
        return (totalCount, totalSecs)
    }

    // MARK: - Badge text helpers

    /// Returns formatted badge string e.g. "↗2 ~8m", nil if count == 0.
    func badgeText(date: Date, startMin: Int, desc: String) -> String? {
        let c = count(date: date, startMin: startMin, desc: desc)
        guard c > 0 else { return nil }
        return formatted(count: c, seconds: duration(date: date, startMin: startMin, desc: desc))
    }

    /// Same as badgeText but matches by title across all time slots on the given date.
    func badgeTextByTitle(date: Date, title: String) -> String? {
        let c = countByTitle(date: date, title: title)
        guard c > 0 else { return nil }
        return formatted(count: c, seconds: durationByTitle(date: date, title: title))
    }

    private func formatted(count: Int, seconds: TimeInterval) -> String {
        let totalSec = Int(seconds)
        guard totalSec > 0 else { return "↗\(count)" }
        let totalMin = totalSec / 60
        let remSec   = totalSec % 60
        if totalMin == 0 { return "↗\(count) ~\(remSec)s" }
        if totalMin < 60 {
            return remSec > 0 ? "↗\(count) ~\(totalMin)m \(remSec)s" : "↗\(count) ~\(totalMin)m"
        }
        let h = totalMin / 60, m = totalMin % 60
        return m > 0 ? "↗\(count) ~\(h)h \(m)m" : "↗\(count) ~\(h)h"
    }

    // MARK: - Notes suffix helpers

    static let metricsSuffixPattern = #"\s*/\d+(\s*~\d+h\s*\d+m|\s*~\d+h|\s*~\d+m\s*\d+s|\s*~\d+m|\s*~\d+s)?$"#

    func metricsSuffix(count: Int, seconds: TimeInterval) -> String {
        guard count > 0 else { return "" }
        var s = " /\(count)"
        let totalSec = Int(seconds)
        if totalSec > 0 {
            let totalMin = totalSec / 60
            let remSec   = totalSec % 60
            if totalMin == 0 { s += " ~\(remSec)s" }
            else if totalMin < 60 {
                s += remSec > 0 ? " ~\(totalMin)m \(remSec)s" : " ~\(totalMin)m"
            } else {
                let h = totalMin / 60, m = totalMin % 60
                s += m > 0 ? " ~\(h)h \(m)m" : " ~\(h)h"
            }
        }
        return s
    }

    // MARK: - Reset

    /// Rebuilds counts and durations for a given date from parsed note task entries.
    /// Each entry should carry the count and seconds already extracted from the "/N ~Xm" suffix.
    func recalculateFromNotes(date: Date, entries: [(startMin: Int, desc: String, count: Int, seconds: TimeInterval)]) {
        let prefix = "\(dateFormatter.string(from: date))|"
        var c = counts
        var d = durations
        // Remove existing data for this date
        c = c.filter { !$0.key.hasPrefix(prefix) }
        d = d.filter { !$0.key.hasPrefix(prefix) }
        // Rebuild from parsed entries
        for entry in entries where entry.count > 0 {
            let k = makeKey(date: date, startMin: entry.startMin, desc: entry.desc)
            c[k] = entry.count
            if entry.seconds > 0 { d[k] = entry.seconds }
        }
        counts    = c
        durations = d
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    /// Removes all distraction counts and durations for a given date.
    func clearDay(date: Date) {
        let prefix = "\(dateFormatter.string(from: date))|"
        var c = counts
        var d = durations
        c = c.filter { !$0.key.hasPrefix(prefix) }
        d = d.filter { !$0.key.hasPrefix(prefix) }
        counts    = c
        durations = d
        // Also clear any pending exit for this date
        if let key = pendingExitKey, key.hasPrefix(prefix) {
            pendingExitTime     = nil
            pendingExitKey      = nil
            pendingExitSchedule = []
        }
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    func reset(date: Date, startMin: Int, desc: String) {
        var c = counts
        var d = durations
        let k = makeKey(date: date, startMin: startMin, desc: desc)
        c.removeValue(forKey: k)
        d.removeValue(forKey: k)
        counts = c
        durations = d
    }
}
