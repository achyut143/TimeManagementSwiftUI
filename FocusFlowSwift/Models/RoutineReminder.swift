import Foundation
import UserNotifications

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
        RoutineStep(name: "Water", minutes: 2, icon: "drop.fill", colorName: "cyan"),
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
        steps.map { "\($0.minutes)" }.joined(separator: "/") + " min"
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

/// A repeating sequence of steps (default Sit 30 → Stand 30 → Stretch 5),
/// running from the moment it was switched on.
///
/// The current step is worked out from `startedAt` and the clock rather than
/// a running timer, so it stays correct across backgrounding and relaunches.
/// Step changes are also queued as local notifications so they arrive while
/// the app isn't open.
enum RoutineReminder {
    static let enabledKey = "routine.enabled"
    static let stepsKey = "routine.steps"
    static let startedAtKey = "routine.startedAt"
    /// When a snoozed step will start, so the pill can say it's snoozed.
    static let snoozedUntilKey = "routine.snoozedUntil"
    static let snoozedStepKey = "routine.snoozedStep"

    private static let notificationPrefix = "routine-reminder-"
    /// How many upcoming step changes to keep scheduled. Topped up each time
    /// the app becomes active; iOS caps pending notifications at 64 app-wide.
    private static let notificationsAhead = 24

    struct Status {
        let index: Int
        let step: RoutineStep
        let secondsRemaining: Int
        /// When this step began.
        let stepStart: Date
    }

    private static var defaults: UserDefaults { .standard }

    // MARK: - Settings

    static var isEnabled: Bool { defaults.bool(forKey: enabledKey) }

    /// Never empty. The default sequence is saved on first use so its step
    /// ids stay stable (acknowledgments are keyed by step id).
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

    static var startedAt: Date {
        let t = defaults.double(forKey: startedAtKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : Date()
    }

    private static func seconds(_ step: RoutineStep) -> Int { max(1, step.minutes) * 60 }

    /// Seconds from the start of a cycle to the start of step `index`.
    private static func offset(ofIndex index: Int, in list: [RoutineStep]) -> Int {
        list.prefix(index).reduce(0) { $0 + seconds($1) }
    }

    static func status(at now: Date = Date()) -> Status {
        let list = steps
        if let held = heldStatus(at: now, list: list) { return held }
        let cycle = list.reduce(0) { $0 + seconds($1) }
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        var pos = elapsed % cycle
        for (i, step) in list.enumerated() {
            let len = seconds(step)
            if pos < len {
                let remaining = len - pos
                return Status(index: i, step: step, secondsRemaining: remaining,
                              stepStart: now.addingTimeInterval(Double(remaining - len)))
            }
            pos -= len
        }
        // Not reachable: pos is always inside the cycle.
        return Status(index: 0, step: list[0], secondsRemaining: seconds(list[0]), stepStart: now)
    }

    static func nextStep(after index: Int) -> RoutineStep {
        let list = steps
        return list[(index + 1) % list.count]
    }

    // MARK: - Acknowledgment

    /// Stable id for the current step occurrence, for AcknowledgmentStore —
    /// same mechanism the calendar-task timer uses, so an acknowledged step
    /// stays acknowledged across view reloads and app relaunches.
    private static func key(for status: Status) -> String {
        "routine-\(status.step.id.uuidString)@\(Int(status.stepStart.timeIntervalSince1970 / 60))"
    }

    /// True when the current step wants acknowledging and hasn't been yet.
    static func needsAcknowledgment(at now: Date = Date()) -> Bool {
        let st = status(at: now)
        guard st.step.remind else { return false }
        return !AcknowledgmentStore.isAcknowledged(date: st.stepStart, identifier: key(for: st))
    }

    static func acknowledgeCurrentStep(at now: Date = Date()) {
        let st = status(at: now)
        AcknowledgmentStore.acknowledge(date: st.stepStart, identifier: key(for: st))
    }

    // MARK: - Actions

    /// Turns the routine on or off. Turning on starts the first step now.
    static func setEnabled(_ on: Bool) {
        defaults.set(on, forKey: enabledKey)
        if on { startStep(at: 0) }
        reschedule()
    }

    /// Holds a step past its normal end while a snooze runs.
    private static let holdIndexKey = "routine.holdIndex"
    private static let holdStartKey = "routine.holdStart"

    /// Delays the next step.
    /// - If the next step has just started and hasn't been acknowledged yet,
    ///   it goes back to the step before it until `minutes` from now.
    /// - Otherwise the current step is held `minutes` past its normal end.
    /// The snoozed step then starts with its full length, and every later
    /// step moves back by the same amount.
    static func snooze(minutes: Int, at now: Date = Date()) {
        let list = steps
        let n = list.count
        let st = status(at: now)
        let justStarted = needsAcknowledgment(at: now)
        let delay = Double(max(1, minutes) * 60)

        let heldIndex = justStarted ? (st.index - 1 + n) % n : st.index
        let nextIndex = (heldIndex + 1) % n
        let holdUntil = justStarted ? now.addingTimeInterval(delay)
                                    : now.addingTimeInterval(Double(st.secondsRemaining) + delay)
        let holdStart = justStarted ? now : st.stepStart

        // Line the sequence up so the next step starts exactly when the hold ends.
        let cycle = Double(list.reduce(0) { $0 + seconds($1) })
        var start = holdUntil.addingTimeInterval(-Double(offset(ofIndex: nextIndex, in: list)))
        while start > now { start = start.addingTimeInterval(-cycle) }
        defaults.set(start.timeIntervalSince1970, forKey: startedAtKey)

        defaults.set(heldIndex, forKey: holdIndexKey)
        defaults.set(holdStart.timeIntervalSince1970, forKey: holdStartKey)
        defaults.set(holdUntil.timeIntervalSince1970, forKey: snoozedUntilKey)
        defaults.set(list[nextIndex].name, forKey: snoozedStepKey)

        // The held step was already seen; don't ask to acknowledge it again.
        acknowledgeCurrentStep(at: now)
        reschedule()
    }

    /// The snoozed step's name and when it will start, while a snooze is running.
    static func activeSnooze(at now: Date = Date()) -> (step: String, until: Date)? {
        let until = defaults.double(forKey: snoozedUntilKey)
        guard until > now.timeIntervalSince1970 else { return nil }
        return (defaults.string(forKey: snoozedStepKey) ?? "Next step", Date(timeIntervalSince1970: until))
    }

    /// The held step while a snooze runs.
    private static func heldStatus(at now: Date, list: [RoutineStep]) -> Status? {
        let until = defaults.double(forKey: snoozedUntilKey)
        let index = defaults.integer(forKey: holdIndexKey)
        guard until > now.timeIntervalSince1970, index < list.count else { return nil }
        let remaining = Int((until - now.timeIntervalSince1970).rounded(.up))
        return Status(index: index, step: list[index], secondsRemaining: max(1, remaining),
                      stepStart: Date(timeIntervalSince1970: defaults.double(forKey: holdStartKey)))
    }

    private static func clearSnooze() {
        defaults.set(0.0, forKey: snoozedUntilKey)
    }

    /// Ends the current step now and moves to the next one.
    static func skipToNextStep() {
        let list = steps
        startStep(at: (status().index + 1) % list.count)
        reschedule()
    }

    /// Restarts the sequence from the first step.
    static func restart() {
        startStep(at: 0)
        reschedule()
    }

    /// Saves a new sequence without jumping to a different step: if the
    /// current step is still in the list, it keeps its start time and only
    /// its length (and the rest of the cycle) changes. If it was removed,
    /// the sequence restarts from the first step.
    static func updateSteps(_ newSteps: [RoutineStep]) {
        let now = Date()
        let before = status(at: now)
        clearSnooze()
        setSteps(newSteps.isEmpty ? RoutinePreset.defaultSteps : newSteps)
        guard isEnabled else { return }
        let list = steps
        if let i = list.firstIndex(where: { $0.id == before.step.id }) {
            let start = before.stepStart.addingTimeInterval(-Double(offset(ofIndex: i, in: list)))
            defaults.set(start.timeIntervalSince1970, forKey: startedAtKey)
        } else {
            startStep(at: 0)
        }
        reschedule()
    }

    /// Starts a step now. The user chose it, so it doesn't need acknowledging.
    private static func startStep(at index: Int) {
        clearSnooze()
        let now = Date()
        let start = now.addingTimeInterval(-Double(offset(ofIndex: index, in: steps)))
        defaults.set(start.timeIntervalSince1970, forKey: startedAtKey)
        acknowledgeCurrentStep(at: now)
    }

    // MARK: - Notifications

    static func title(for step: RoutineStep) -> String {
        "\(step.name) time"
    }

    /// Replaces all pending routine notifications with the next ones from now.
    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter {
                $0.hasPrefix(notificationPrefix) || $0.hasPrefix("stand-reminder-")
            }
            center.removePendingNotificationRequests(withIdentifiers: old)

            guard isEnabled else { return }

            let list = steps
            // Nothing to announce if no step asks for a reminder.
            guard list.contains(where: \.remind) else { return }

            let current = status()
            var index = current.index
            var fireIn = TimeInterval(current.secondsRemaining)
            var scheduled = 0
            var guardCount = 0

            while scheduled < notificationsAhead && guardCount < notificationsAhead * list.count {
                guardCount += 1
                index = (index + 1) % list.count
                let step = list[index]
                defer { fireIn += TimeInterval(seconds(step)) }
                guard step.remind else { continue }

                let content = UNMutableNotificationContent()
                content.title = title(for: step)
                content.body = "\(step.name) for \(step.minutes) min. Open the app to acknowledge."
                content.sound = .default
                content.interruptionLevel = .timeSensitive

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireIn), repeats: false)
                center.add(UNNotificationRequest(identifier: "\(notificationPrefix)\(scheduled)", content: content, trigger: trigger))
                scheduled += 1
            }
        }
    }
}
