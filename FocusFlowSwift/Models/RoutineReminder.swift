import Foundation
import UserNotifications
import UIKit

/// One step in the routine sequence, e.g. "Stand · 30 min".
struct RoutineStep: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var minutes: Int
    /// SF Symbol name.
    var icon: String
    /// Key into RoutineStep.palette.
    var colorName: String
    /// Notify + ask to acknowledge when this step starts. Off for steps like
    /// "Work" where you don't need a nudge when they begin.
    var remind: Bool = true
    /// Something you just do, like drinking water: no timer. It stays on
    /// screen until you tap Done, then the next step starts.
    var isEvent: Bool = false
}

extension RoutineStep {
    private enum CodingKeys: String, CodingKey {
        case id, name, minutes, icon, colorName, remind, isEvent
    }

    /// Fields added later are optional, so routines saved by older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 10
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "star.fill"
        colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? "pink"
        remind = try c.decodeIfPresent(Bool.self, forKey: .remind) ?? true
        isEvent = try c.decodeIfPresent(Bool.self, forKey: .isEvent) ?? false
    }

    /// "30 min", or "Event" for a step without a timer.
    var lengthLabel: String { isEvent ? "Event" : "\(minutes) min" }
}

extension RoutineStep {
    /// Starting points offered when adding a step. Name, minutes and
    /// everything else can be changed afterwards.
    static let templates: [RoutineStep] = [
        RoutineStep(name: "Sit", minutes: 30, icon: "chair.fill", colorName: "teal"),
        RoutineStep(name: "Stand", minutes: 30, icon: "figure.stand", colorName: "orange"),
        RoutineStep(name: "Stretch", minutes: 5, icon: "figure.flexibility", colorName: "purple"),
        RoutineStep(name: "Work", minutes: 60, icon: "laptopcomputer", colorName: "blue", remind: false),
        RoutineStep(name: "Meditate", minutes: 10, icon: "figure.mind.and.body", colorName: "indigo"),
        RoutineStep(name: "Call", minutes: 15, icon: "phone.fill", colorName: "green"),
        RoutineStep(name: "Walk", minutes: 10, icon: "figure.walk", colorName: "mint"),
        RoutineStep(name: "Water", minutes: 2, icon: "drop.fill", colorName: "cyan", isEvent: true),
        RoutineStep(name: "Break", minutes: 10, icon: "cup.and.saucer.fill", colorName: "brown"),
        RoutineStep(name: "Custom", minutes: 10, icon: "star.fill", colorName: "pink"),
    ]

    /// A fresh copy of a template (new id).
    static func from(template: RoutineStep) -> RoutineStep {
        var s = template
        s.id = UUID()
        return s
    }

    static func template(named name: String) -> RoutineStep {
        from(template: templates.first { $0.name == name } ?? templates[0])
    }
}

/// Ready-made sequences. The first one is the default.
struct RoutinePreset: Identifiable {
    let name: String
    let stepNames: [(String, Int)]
    var id: String { name }

    var steps: [RoutineStep] {
        stepNames.map { name, minutes in
            var s = RoutineStep.template(named: name)
            s.minutes = minutes
            return s
        }
    }

    static let all: [RoutinePreset] = [
        RoutinePreset(name: "Sit · Stand · Stretch", stepNames: [("Sit", 30), ("Stand", 30), ("Stretch", 5)]),
        RoutinePreset(name: "Work · Stretch", stepNames: [("Work", 60), ("Stretch", 5)]),
        RoutinePreset(name: "Sit · Stand", stepNames: [("Sit", 30), ("Stand", 30)]),
        RoutinePreset(name: "Work · Meditate", stepNames: [("Work", 50), ("Meditate", 10)]),
    ]

    static var defaultSteps: [RoutineStep] { all[0].steps }
}

/// A sequence the user saved under their own name.
struct SavedRoutinePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var steps: [RoutineStep]

    static let storageKey = "routine.savedPresets"

    /// Copies of the steps with fresh ids, ready to become the live sequence.
    var freshSteps: [RoutineStep] {
        steps.map { var s = $0; s.id = UUID(); return s }
    }

    var summary: String {
        steps.map { $0.isEvent ? "•" : "\($0.minutes)" }.joined(separator: "/") + " min"
    }

    static func load(_ raw: String) -> [SavedRoutinePreset] {
        guard let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([SavedRoutinePreset].self, from: data) else { return [] }
        return list
    }

    static func encode(_ list: [SavedRoutinePreset]) -> String {
        guard let data = try? JSONEncoder().encode(list) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// A repeating sequence of steps (default Sit 30 → Stand 30 → Stretch 5).
///
/// The timer only runs while the app is open: it pauses when the app goes to
/// the background and carries on from the same point when you come back.
///
/// A step with "remind" on doesn't start by itself. When the step before it
/// ends, the routine waits on it ("Stand time · tap to acknowledge") and its
/// timer starts only once you acknowledge it. Steps with "remind" off start
/// straight away.
///
/// An event step (e.g. "Water") has no timer: it waits until you tap Done,
/// and then the next step starts.
enum RoutineReminder {
    static let enabledKey = "routine.enabled"
    static let stepsKey = "routine.steps"

    private static let indexKey = "routine.index"
    /// Seconds run in the current step before the latest resume.
    private static let elapsedKey = "routine.elapsed"
    /// When the current step last resumed. 0 while paused or waiting.
    private static let runningSinceKey = "routine.runningSince"
    /// The current step is waiting to be acknowledged before its timer starts.
    private static let awaitingKey = "routine.awaitingAck"
    /// Length of the current step in seconds when a snooze changed it. 0 = normal.
    private static let lengthOverrideKey = "routine.lengthOverride"
    private static let snoozedStepKey = "routine.snoozedStep"
    /// Last moment the app was seen open, so a crash or force-quit doesn't
    /// count the time the app was closed.
    private static let lastSeenKey = "routine.lastSeen"

    private static let notificationPrefix = "routine-reminder-"

    struct Status {
        let index: Int
        let step: RoutineStep
        let secondsRemaining: Int
        /// The step's time hasn't started: it's waiting to be acknowledged.
        let waitingForAck: Bool
        /// An event: no timer, waits for Done.
        var isEvent: Bool { step.isEvent }
    }

    private static var defaults: UserDefaults { .standard }

    // MARK: - Settings

    static var isEnabled: Bool { defaults.bool(forKey: enabledKey) }

    /// Never empty. The default sequence is saved on first use so its step
    /// ids stay stable.
    static var steps: [RoutineStep] {
        if let list = decode(defaults.string(forKey: stepsKey) ?? "") { return list }
        let list = RoutinePreset.defaultSteps
        setSteps(list)
        return list
    }

    static func setSteps(_ steps: [RoutineStep]) {
        defaults.set(encode(steps), forKey: stepsKey)
    }

    /// nil when nothing valid is stored.
    private static func decode(_ raw: String) -> [RoutineStep]? {
        guard let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([RoutineStep].self, from: data),
              !list.isEmpty else { return nil }
        return list
    }

    static func encode(_ steps: [RoutineStep]) -> String {
        guard let data = try? JSONEncoder().encode(steps) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func seconds(_ step: RoutineStep) -> Double { Double(max(1, step.minutes) * 60) }

    // MARK: - Stored state

    private static var index: Int {
        get { defaults.integer(forKey: indexKey) }
        set { defaults.set(newValue, forKey: indexKey) }
    }
    private static var elapsed: Double {
        get { defaults.double(forKey: elapsedKey) }
        set { defaults.set(newValue, forKey: elapsedKey) }
    }
    private static var runningSince: Double {
        get { defaults.double(forKey: runningSinceKey) }
        set { defaults.set(newValue, forKey: runningSinceKey) }
    }
    private static var awaiting: Bool {
        get { defaults.bool(forKey: awaitingKey) }
        set { defaults.set(newValue, forKey: awaitingKey) }
    }
    private static var lengthOverride: Double {
        get { defaults.double(forKey: lengthOverrideKey) }
        set { defaults.set(newValue, forKey: lengthOverrideKey) }
    }

    private static var isRunning: Bool { runningSince > 0 }

    private static func length(of i: Int, in list: [RoutineStep]) -> Double {
        lengthOverride > 0 ? lengthOverride : seconds(list[i])
    }

    private static func runSeconds(at now: Date) -> Double {
        elapsed + (isRunning ? max(0, now.timeIntervalSince1970 - runningSince) : 0)
    }

    // MARK: - Status

    /// The current step. Moves on if this one's time is up: a reminder step
    /// then waits to be acknowledged, any other step starts right away.
    static func status(at now: Date = Date()) -> Status {
        let list = steps
        // Installs from before pausing existed have no index yet.
        if defaults.object(forKey: indexKey) == nil || index >= list.count {
            begin(at: 0, now: now)
        }
        advance(now: now, list: list)

        let i = index
        if list[i].isEvent {
            return Status(index: i, step: list[i], secondsRemaining: 0, waitingForAck: false)
        }
        let len = length(of: i, in: list)
        let remaining = awaiting ? len : len - runSeconds(at: now)
        return Status(index: i, step: list[i], secondsRemaining: max(1, Int(remaining.rounded(.up))),
                      waitingForAck: awaiting)
    }

    private static func advance(now: Date, list: [RoutineStep]) {
        // Bounded in case every step is short and the app froze a long time.
        for _ in 0..<(list.count * 2) {
            guard !awaiting, isRunning, !list[index].isEvent else { return }
            let over = runSeconds(at: now) - length(of: index, in: list)
            guard over >= 0 else { return }

            let next = (index + 1) % list.count
            index = next
            lengthOverride = 0
            defaults.removeObject(forKey: snoozedStepKey)
            if list[next].isEvent {
                // No timer: waits for Done.
                awaiting = false
                elapsed = 0
                runningSince = 0
            } else if list[next].remind {
                awaiting = true
                elapsed = 0
                runningSince = 0
            } else {
                // Starts the moment the last one ended.
                elapsed = over
                runningSince = now.timeIntervalSince1970
            }
        }
    }

    static func nextStep(after index: Int) -> RoutineStep {
        let list = steps
        return list[(index + 1) % list.count]
    }

    // MARK: - Acknowledgment

    /// True when a step is waiting to be acknowledged.
    static func needsAcknowledgment(at now: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        return status(at: now).waitingForAck
    }

    /// Starts the waiting step's timer.
    static func acknowledgeCurrentStep(at now: Date = Date()) {
        guard awaiting else { return }
        awaiting = false
        elapsed = 0
        runningSince = now.timeIntervalSince1970
    }

    // MARK: - Pause / resume with the app

    /// Pauses when the app leaves the screen and resumes when it's back.
    /// Call once at launch.
    static func installLifecycleObservers() {
        // A crash or force-quit while open never sent "background", so
        // count only up to the last time the app was seen.
        if isRunning {
            let lastSeen = defaults.double(forKey: lastSeenKey)
            pause(at: Date(timeIntervalSince1970: max(runningSince, lastSeen)))
        }
        // Clear step notifications queued by older versions.
        reschedule()

        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            pause(at: Date())
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            resume(at: Date())
        }
    }

    /// Called every second by the pill, so a crash loses at most a second.
    static func markSeen(_ now: Date = Date()) {
        defaults.set(now.timeIntervalSince1970, forKey: lastSeenKey)
    }

    private static func pause(at now: Date) {
        guard isRunning else { return }
        // Let a step that ended before now move on first.
        _ = status(at: now)
        guard isRunning else { return }
        elapsed = runSeconds(at: now)
        runningSince = 0
    }

    private static func resume(at now: Date) {
        markSeen(now)
        let list = steps
        guard isEnabled, !awaiting, !isRunning,
              list.indices.contains(index), !list[index].isEvent else { return }
        runningSince = now.timeIntervalSince1970
    }

    // MARK: - Actions

    /// Turns the routine on or off. Turning on starts the first step now.
    static func setEnabled(_ on: Bool) {
        defaults.set(on, forKey: enabledKey)
        if on { begin(at: 0, now: Date()) } else { runningSince = 0 }
    }

    /// Starts a step now. The user chose it, so it doesn't need acknowledging.
    private static func begin(at i: Int, now: Date) {
        index = i
        elapsed = 0
        awaiting = false
        lengthOverride = 0
        defaults.removeObject(forKey: snoozedStepKey)
        let list = steps
        runningSince = list.indices.contains(i) && list[i].isEvent ? 0 : now.timeIntervalSince1970
    }

    /// Marks the current event as done and starts the next step.
    static func completeEvent() {
        let st = status()
        guard st.isEvent else { return }
        begin(at: (st.index + 1) % steps.count, now: Date())
    }

    /// Delays the next step by `minutes`.
    /// - If a step is waiting to be acknowledged, the routine goes back to the
    ///   step before it for `minutes`, then asks again.
    /// - Otherwise the current step runs `minutes` longer.
    static func snooze(minutes: Int, at now: Date = Date()) {
        let list = steps
        let st = status(at: now)
        let delay = Double(max(1, minutes) * 60)
        let holding = st.waitingForAck || st.isEvent
        let delayed = holding ? st.index : (st.index + 1) % list.count

        if holding {
            index = (st.index - 1 + list.count) % list.count
            awaiting = false
            elapsed = 0
            lengthOverride = delay
        } else {
            lengthOverride = length(of: st.index, in: list) + delay
        }
        defaults.set(list[delayed].name, forKey: snoozedStepKey)
        if !isRunning { runningSince = now.timeIntervalSince1970 }
    }

    /// The snoozed step's name and when it will start (if the app stays open).
    static func activeSnooze(at now: Date = Date()) -> (step: String, until: Date)? {
        let st = status(at: now)
        guard lengthOverride > 0, !st.waitingForAck, !st.isEvent,
              let name = defaults.string(forKey: snoozedStepKey) else { return nil }
        return (name, now.addingTimeInterval(Double(st.secondsRemaining)))
    }

    /// Ends the current step now and moves to the next one.
    static func skipToNextStep() {
        begin(at: (status().index + 1) % steps.count, now: Date())
    }

    /// Restarts the sequence from the first step.
    static func restart() {
        begin(at: 0, now: Date())
    }

    /// Saves a new sequence without jumping to a different step: if the
    /// current step is still in the list, it keeps its progress. If it was
    /// removed, the sequence restarts from the first step.
    static func updateSteps(_ newSteps: [RoutineStep]) {
        let now = Date()
        let old = steps
        let currentID = old.indices.contains(index) ? old[index].id : nil
        setSteps(newSteps.isEmpty ? RoutinePreset.defaultSteps : newSteps)
        guard isEnabled else { return }
        if let i = steps.firstIndex(where: { $0.id == currentID }) {
            index = i
            lengthOverride = 0
            if steps[i].isEvent {
                awaiting = false
                elapsed = 0
                runningSince = 0
            } else if !awaiting && !isRunning {
                runningSince = now.timeIntervalSince1970
            }
        } else {
            begin(at: 0, now: now)
        }
    }

    // MARK: - Notifications

    static func title(for step: RoutineStep) -> String {
        "\(step.name) time"
    }

    /// The routine only moves while the app is open, so it no longer queues
    /// step-change notifications. This clears any left by older versions.
    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter {
                $0.hasPrefix(notificationPrefix) || $0.hasPrefix("stand-reminder-")
            }
            center.removePendingNotificationRequests(withIdentifiers: old)
        }
    }
}
