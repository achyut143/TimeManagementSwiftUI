import Foundation

/// Tracks continuous "in the app" (foreground) sessions — the inverse of
/// AwayTimeTracker. A session runs from the moment the app becomes active
/// until it's backgrounded. Unlike AwayTimeTracker (which only needs a daily
/// total), individual sessions are kept per day so a chart can show one bar
/// per "iteration" (session) within a day, in addition to day/week/month
/// aggregates.
class FocusSessionTracker: ObservableObject {
    static let shared = FocusSessionTracker()

    struct Session: Codable, Identifiable {
        var id = UUID()
        let start: Date
        let end: Date
        var seconds: Double { end.timeIntervalSince(start) }
    }

    private let sessionsKey    = "FocusSessionTracker.sessionsByDay"
    private let currentKey     = "FocusSessionTracker.currentSessionStart"
    // Session detail older than this is dropped on write so storage stays
    // bounded — day/week/month charts only ever look back a few months anyway.
    private let retentionDays  = 120

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // Decoding the whole dictionary from UserDefaults on every read adds up
    // once a few months of sessions pile up — cache it and invalidate on write.
    private var cachedSessions: [String: [Session]]?

    private init() {}

    // MARK: - Live session

    /// Start (or end) time of the session currently in progress, or nil when
    /// the app isn't foregrounded. Drives the live count-up in the UI.
    var currentSessionStart: Date? {
        get { UserDefaults.standard.object(forKey: currentKey) as? Date }
        set {
            UserDefaults.standard.set(newValue, forKey: currentKey)
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    // MARK: - Storage

    private var sessionsByDay: [String: [Session]] {
        get {
            if let cached = cachedSessions { return cached }
            guard let data = UserDefaults.standard.data(forKey: sessionsKey),
                  let decoded = try? JSONDecoder().decode([String: [Session]].self, from: data) else {
                cachedSessions = [:]
                return [:]
            }
            cachedSessions = decoded
            return decoded
        }
        set {
            cachedSessions = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: sessionsKey)
            }
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    // MARK: - Lifecycle hooks (called from MigrationWrapper)

    /// Call when the app becomes active / foregrounded. Any session left
    /// open from before (e.g. a force-quit while foregrounded, so `recordExit`
    /// never ran) is discarded rather than guessed at — a fresh session just
    /// starts now.
    func recordEnter() {
        currentSessionStart = Date()
    }

    /// Call when the app is backgrounded.
    func recordExit() {
        guard let start = currentSessionStart else { return }
        currentSessionStart = nil
        let end = Date()
        guard end > start else { return }
        accumulate(start: start, end: end)
    }

    // MARK: - Query

    func sessions(on date: Date) -> [Session] {
        (sessionsByDay[dateFormatter.string(from: Calendar.current.startOfDay(for: date))] ?? [])
            .sorted { $0.start < $1.start }
    }

    func totalSeconds(on date: Date) -> Double {
        sessions(on: date).reduce(0) { $0 + $1.seconds }
    }

    /// Sum across [start, end] inclusive of both boundary days.
    func totalSeconds(from start: Date, to end: Date) -> Double {
        let cal = Calendar.current
        var total = 0.0
        var day = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        while day <= last {
            total += totalSeconds(on: day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    var todaySeconds: Double { totalSeconds(on: Date()) }

    static func formatted(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    // MARK: - Splitting

    /// Splits [start, end) day-by-day — a session spanning midnight becomes
    /// one Session per affected day — same approach as
    /// AwayTimeTracker/DistractionTracker use for absence spans.
    private func accumulate(start: Date, end: Date) {
        let cal = Calendar.current
        var cursorDay = cal.startOfDay(for: start)
        let lastDay = cal.startOfDay(for: end)
        var cursor = start

        var stored = sessionsByDay
        while cursorDay <= lastDay {
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: cursorDay) else { break }
            let sliceEnd = min(end, dayEnd)
            if sliceEnd > cursor {
                let key = dateFormatter.string(from: cursorDay)
                stored[key, default: []].append(Session(start: cursor, end: sliceEnd))
            }
            cursor = sliceEnd
            cursorDay = dayEnd
        }

        if let cutoff = cal.date(byAdding: .day, value: -retentionDays, to: cal.startOfDay(for: Date())) {
            let cutoffKey = dateFormatter.string(from: cutoff)
            stored = stored.filter { $0.key >= cutoffKey }
        }

        sessionsByDay = stored
    }
}
