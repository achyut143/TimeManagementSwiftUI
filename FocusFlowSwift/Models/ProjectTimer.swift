import SwiftData
import Foundation

// One live timer per project: either a stopwatch (counts up) or a countdown
// (counts down to a target and then keeps counting up as overtime).
// Persisted to SwiftData so it survives an app relaunch; the app pauses any
// running timer when it goes to the background (see MigrationWrapper in
// FocusFlowSwiftApp.swift) so elapsed time never silently includes time the
// app wasn't actually running.
@Model
class ProjectTimer {
    var project: Project?
    var isCountdown: Bool = false
    var targetMinutes: Double?
    // Time banked from previous run segments. The live elapsed time is this
    // plus whatever has accrued since `runningSince`, if currently running.
    var accumulatedSeconds: Double = 0
    var runningSince: Date?
    var createdAt: Date

    init(project: Project) {
        self.project = project
        self.createdAt = Date()
    }

    var isRunning: Bool { runningSince != nil }

    var elapsedSeconds: Double {
        accumulatedSeconds + (runningSince.map { max(0, Date().timeIntervalSince($0)) } ?? 0)
    }

    // nil when this isn't a countdown timer; 0 once the target has been reached
    // (elapsed keeps growing as overtime past that point).
    var remainingSeconds: Double? {
        guard isCountdown, let targetMinutes else { return nil }
        return max(0, targetMinutes * 60 - elapsedSeconds)
    }

    func start() {
        guard runningSince == nil else { return }
        runningSince = Date()
    }

    // Banks whatever accrued in the current run segment and stops the clock.
    // Safe to call on an already-paused timer (no-op).
    func pause() {
        guard let since = runningSince else { return }
        accumulatedSeconds += max(0, Date().timeIntervalSince(since))
        runningSince = nil
    }

    // Clears banked/running time so the timer is ready for a fresh session.
    // Called after a session's time has been logged as a ProjectTimeEntry.
    func reset() {
        accumulatedSeconds = 0
        runningSince = nil
    }
}
