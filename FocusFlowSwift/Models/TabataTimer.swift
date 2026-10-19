import Foundation
import Observation

/// Runs a Tabata: steps through its intervals by wall-clock time (so it stays
/// correct after the phone locks), with 3-2-1 beeps and spoken cues.
@Observable
final class TabataTimer {
    let draft: TabataDraft
    let intervals: [TabataInterval]

    private(set) var index = 0
    private(set) var remaining: Double = 0
    private(set) var isPaused = false
    private(set) var isFinished = false
    private(set) var startedAt: Date?

    @ObservationIgnored private var phaseEnd = Date()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastBeepSecond: Int?
    @ObservationIgnored private let audio = WorkoutAudio.shared
    @ObservationIgnored var onFinish: (() -> Void)?

    init(draft: TabataDraft) {
        self.draft = draft
        self.intervals = draft.intervals
        self.remaining = Double(intervals.first?.seconds ?? 0)
    }

    var current: TabataInterval? { intervals.indices.contains(index) ? intervals[index] : nil }

    /// The next exercise after this one, for the "Next:" line.
    var nextExercise: String? {
        guard let current else { return nil }
        if current.phase != .work { return current.exercise }
        return intervals[(index + 1)...].first(where: { $0.phase == .work })?.exercise
    }

    var totalRemaining: Int {
        let later = intervals.dropFirst(index + 1).reduce(0) { $0 + $1.seconds }
        return Int(remaining.rounded(.up)) + later
    }

    var progress: Double {
        guard let current, current.seconds > 0 else { return 0 }
        return 1 - remaining / Double(current.seconds)
    }

    // MARK: Controls

    func start() {
        guard startedAt == nil, !intervals.isEmpty else { return }
        startedAt = Date()
        audio.begin()
        enter(0)
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func togglePause() {
        guard !isFinished else { return }
        if isPaused {
            phaseEnd = Date().addingTimeInterval(remaining)
            isPaused = false
            audio.speak("Resume")
        } else {
            isPaused = true
            audio.speak("Paused")
        }
    }

    func skipForward() {
        guard !isFinished else { return }
        if index + 1 < intervals.count { enter(index + 1) } else { finish() }
    }

    /// Restarts this interval, or goes to the previous one if it barely started.
    func goBack() {
        guard !isFinished, let current else { return }
        let elapsed = Double(current.seconds) - remaining
        enter(elapsed < 2 && index > 0 ? index - 1 : index)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if !isFinished { audio.end() }
    }

    // MARK: Engine

    private func enter(_ newIndex: Int) {
        index = newIndex
        let interval = intervals[newIndex]
        remaining = Double(interval.seconds)
        phaseEnd = Date().addingTimeInterval(remaining)
        lastBeepSecond = nil
        if isPaused { isPaused = false }
        announce(interval)
    }

    private func announce(_ interval: TabataInterval) {
        switch interval.phase {
        case .prepare:
            let part = interval.partCount > 1 ? " \(interval.partName)." : ""
            audio.speak("Get ready.\(part) First: \(interval.exercise).")
        case .work:
            // A part with no prepare time still announces itself.
            if interval.isPartStart && interval.partCount > 1 {
                audio.speak("\(interval.partName). \(interval.exercise).")
            } else {
                audio.speak("\(interval.exercise).")
            }
        case .rest:
            let lead = interval.isRoundBreak ? "Round \(interval.round) done. Rest." : "Rest."
            audio.speak("\(lead) Next: \(interval.exercise).")
        }
    }

    private func tick() {
        audio.ensureRunning()
        guard !isPaused, !isFinished else { return }
        remaining = max(0, phaseEnd.timeIntervalSinceNow)

        // 3-2-1 countdown beeps before each change of phase.
        let whole = Int(remaining.rounded(.up))
        if (1...3).contains(whole), whole != lastBeepSecond, (current?.seconds ?? 0) > 3 {
            lastBeepSecond = whole
            audio.beep()
        }

        if remaining <= 0 {
            // Catch up if several intervals passed (e.g. app was suspended).
            var overshoot = -phaseEnd.timeIntervalSinceNow
            var next = index + 1
            while next < intervals.count, overshoot > Double(intervals[next].seconds) {
                overshoot -= Double(intervals[next].seconds)
                next += 1
            }
            if next < intervals.count {
                audio.beep(final: true)
                enter(next)
                phaseEnd = phaseEnd.addingTimeInterval(-overshoot)
            } else {
                finish()
            }
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        remaining = 0
        index = intervals.count - 1
        audio.beep(final: true)
        audio.speak("Workout complete.")
        timer?.invalidate()
        timer = nil
        onFinish?()
        audio.endSoon()
    }
}
