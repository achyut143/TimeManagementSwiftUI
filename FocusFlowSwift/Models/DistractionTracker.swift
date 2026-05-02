import Foundation

/// Tracks how many times the user left the app / closed Daily Notes while a task was active,
/// and the total time they spent away from each task.
class DistractionTracker: ObservableObject {
    static let shared = DistractionTracker()

    private let countKey    = "DistractionTracker.counts"
    private let durationKey = "DistractionTracker.durations"
    // Pending exit state — persisted so view dismissal doesn't lose it
    private let exitTimeKey = "DistractionTracker.pendingExitTime"
    private let exitKeyKey  = "DistractionTracker.pendingExitKey"

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Private storage helpers

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

    // MARK: - Key

    func makeKey(date: Date, startMin: Int, desc: String) -> String {
        "\(dateFormatter.string(from: date))|\(startMin)|\(desc)"
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
        var d = durations
        d[k] = (d[k] ?? 0) + interval
        durations = d
    }

    // MARK: - Exit / Return tracking

    /// Call when the user leaves DailyNotes or backgrounds the app.
    func recordExit(date: Date, startMin: Int, desc: String) {
        pendingExitTime = Date()
        pendingExitKey  = makeKey(date: date, startMin: startMin, desc: desc)
    }

    /// Call when the user returns to DailyNotes or the app comes to foreground.
    /// Adds the elapsed time to accumulated duration and returns (date, startMin, desc) so the
    /// caller can refresh notes text. Returns nil if no exit was pending.
    func settleReturn() -> (date: Date, startMin: Int, desc: String)? {
        guard let exitTime = pendingExitTime, let key = pendingExitKey else { return nil }
        let elapsed = Date().timeIntervalSince(exitTime)
        pendingExitTime = nil
        pendingExitKey  = nil
        if elapsed > 0 { addDuration(elapsed, forKey: key) }
        DispatchQueue.main.async { self.objectWillChange.send() }
        let parts = key.components(separatedBy: "|")
        guard parts.count >= 3,
              let startMin = Int(parts[1]),
              let date = dateFormatter.date(from: parts[0])
        else { return nil }
        return (date: date, startMin: startMin, desc: parts[2])
    }

    // MARK: - Badge text helpers

    /// Returns formatted badge string "↗N ~Xm" (or "↗N" if no duration yet), nil if count == 0.
    func badgeText(date: Date, startMin: Int, desc: String) -> String? {
        let c = count(date: date, startMin: startMin, desc: desc)
        guard c > 0 else { return nil }
        let secs = duration(date: date, startMin: startMin, desc: desc)
        return formatted(count: c, seconds: secs)
    }

    /// Same as badgeText but matches by title across all time slots on the given date.
    func badgeTextByTitle(date: Date, title: String) -> String? {
        let c = countByTitle(date: date, title: title)
        guard c > 0 else { return nil }
        let secs = durationByTitle(date: date, title: title)
        return formatted(count: c, seconds: secs)
    }

    private func formatted(count: Int, seconds: TimeInterval) -> String {
        let totalMin = Int(seconds / 60)
        guard totalMin > 0 else { return "↗\(count)" }
        if totalMin < 60 { return "↗\(count) ~\(totalMin)m" }
        let h = totalMin / 60, m = totalMin % 60
        let durStr = m > 0 ? "~\(h)h \(m)m" : "~\(h)h"
        return "↗\(count) \(durStr)"
    }

    // MARK: - Notes suffix helpers

    /// The regex pattern that matches the metrics suffix appended to task lines, e.g. " /2 ~8m".
    static let metricsSuffixPattern = #"\s*/\d+(\s*~\d+h\s*\d+m|\s*~\d+h|\s*~\d+m)?$"#

    /// Builds the suffix string to append to a task line.
    func metricsSuffix(count: Int, seconds: TimeInterval) -> String {
        guard count > 0 else { return "" }
        var s = " /\(count)"
        let totalMin = Int(seconds / 60)
        if totalMin > 0 {
            if totalMin < 60 { s += " ~\(totalMin)m" }
            else {
                let h = totalMin / 60, m = totalMin % 60
                s += m > 0 ? " ~\(h)h \(m)m" : " ~\(h)h"
            }
        }
        return s
    }

    // MARK: - Reset

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
