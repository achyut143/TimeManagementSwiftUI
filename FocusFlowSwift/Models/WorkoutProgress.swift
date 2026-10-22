import Foundation
import SwiftData

/// One exercise's best effort in one workout session.
struct ExerciseSessionBest: Identifiable {
    let id: UUID          // session id
    let date: Date
    let workoutName: String
    /// Heaviest weight lifted that session, if any.
    let topWeight: Double?
    /// Reps (or seconds) done at that weight; most reps when no weight.
    let reps: Int
    let timed: Bool
    /// Total weight × reps that session (0 without weights).
    let volume: Double
    let isPR: Bool
}

/// Summary row for the Progress list.
struct ExerciseSummary: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let sessions: Int
    let lastDate: Date
    let best: ExerciseSessionBest
}

/// Reads the rep-workout history to chart exercises and find personal records.
enum WorkoutProgress {
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Completed and stopped rep sessions, oldest first.
    static func repSessions(context: ModelContext) -> [WorkoutSession] {
        let repsRaw = WorkoutKind.reps.rawValue
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.kindRaw == repsRaw },
                                                         sortBy: [SortDescriptor(\.startedAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The best entry for one exercise in one session's log.
    static func best(of entries: [RepLogEntry]) -> RepLogEntry? {
        entries.max { a, b in
            let wa = a.actualWeight ?? 0, wb = b.actualWeight ?? 0
            return wa != wb ? wa < wb : a.actualReps < b.actualReps
        }
    }

    /// Every session where this exercise was logged, oldest first.
    static func history(of name: String, context: ModelContext) -> [ExerciseSessionBest] {
        let k = key(name)
        return repSessions(context: context).compactMap { session in
            let entries = session.log.filter { key($0.name) == k }
            guard let top = best(of: entries) else { return nil }
            let volume = entries.reduce(0.0) { $0 + ($1.actualWeight ?? 0) * Double($1.actualReps) }
            let isPR = session.prNames.contains { key($0) == k }
            return ExerciseSessionBest(id: session.id, date: session.startedAt, workoutName: session.name,
                                       topWeight: (top.actualWeight ?? 0) > 0 ? top.actualWeight : nil,
                                       reps: top.actualReps, timed: top.isTimed, volume: volume, isPR: isPR)
        }
    }

    /// All exercises ever logged, most recently done first.
    static func allExercises(context: ModelContext) -> [ExerciseSummary] {
        var grouped: [String: (name: String, items: [ExerciseSessionBest])] = [:]
        for session in repSessions(context: context) {
            var byKey: [String: [RepLogEntry]] = [:]
            for entry in session.log { byKey[key(entry.name), default: []].append(entry) }
            for (k, entries) in byKey {
                guard let top = best(of: entries) else { continue }
                let item = ExerciseSessionBest(id: session.id, date: session.startedAt, workoutName: session.name,
                                               topWeight: (top.actualWeight ?? 0) > 0 ? top.actualWeight : nil,
                                               reps: top.actualReps, timed: top.isTimed, volume: 0,
                                               isPR: session.prNames.contains { key($0) == k })
                grouped[k, default: (top.name, [])].items.append(item)
            }
        }
        return grouped.map { k, value in
            let bestItem = value.items.max { a, b in
                let wa = a.topWeight ?? 0, wb = b.topWeight ?? 0
                return wa != wb ? wa < wb : a.reps < b.reps
            }!
            return ExerciseSummary(key: k, name: value.name, sessions: value.items.count,
                                   lastDate: value.items.map(\.date).max() ?? .distantPast, best: bestItem)
        }
        .sorted { $0.lastDate > $1.lastDate }
    }

    /// Exercises in `log` that beat every earlier session:
    /// a heavier weight, or more reps/seconds when done without weight.
    /// The first time an exercise is done is not counted as a record.
    /// Returns "Deadlift" → "185 lb (was 175 lb)".
    static func newRecords(in log: [RepLogEntry], context: ModelContext, unit: String) -> [(name: String, detail: String)] {
        var previous: [String: (weight: Double, reps: Int)] = [:]
        for session in repSessions(context: context) {
            for entry in session.log {
                let k = key(entry.name)
                var best = previous[k] ?? (0, 0)
                best.weight = max(best.weight, entry.actualWeight ?? 0)
                if (entry.actualWeight ?? 0) == 0 { best.reps = max(best.reps, entry.actualReps) }
                previous[k] = best
            }
        }

        var byKey: [String: [RepLogEntry]] = [:]
        var order: [String] = []
        for entry in log {
            let k = key(entry.name)
            if byKey[k] == nil { order.append(k) }
            byKey[k, default: []].append(entry)
        }

        var records: [(String, String)] = []
        for k in order {
            guard let old = previous[k], let top = best(of: byKey[k]!) else { continue }
            let weight = top.actualWeight ?? 0
            if weight > 0, old.weight > 0, weight > old.weight {
                records.append((top.name, "\(WorkoutFormat.weight(weight, unit: unit)!) (was \(WorkoutFormat.weight(old.weight, unit: unit)!))"))
            } else if weight == 0, old.weight == 0, old.reps > 0, top.actualReps > old.reps {
                let u = top.isTimed ? "sec" : "reps"
                records.append((top.name, "\(top.actualReps) \(u) (was \(old.reps) \(u))"))
            }
        }
        return records
    }
}
