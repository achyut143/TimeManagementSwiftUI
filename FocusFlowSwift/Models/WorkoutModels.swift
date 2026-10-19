import Foundation
import SwiftData
import UIKit

// MARK: - Shared helpers

enum WorkoutKind: String, Codable, CaseIterable, Identifiable {
    case tabata, reps

    var id: String { rawValue }
    var title: String { self == .tabata ? "Tabata" : "Reps" }
    var icon: String { self == .tabata ? "timer" : "dumbbell.fill" }
}

enum WorkoutFormat {
    /// 40 -> "0:40", 754 -> "12:34", 3725 -> "1:02:05"
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// Rounded minutes for list summaries, e.g. "14 min".
    static func minutes(_ seconds: Int) -> String {
        let m = Int((Double(seconds) / 60).rounded())
        return seconds < 60 && seconds > 0 ? "\(seconds) sec" : "\(m) min"
    }

    static func weight(_ value: Double?, unit: String) -> String? {
        guard let value, value > 0 else { return nil }
        let text = value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
        return "\(text) \(unit)"
    }
}

/// Stores Codable value arrays as JSON so nested structures persist reliably.
enum WorkoutJSON {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, fallback: T) -> T {
        (try? JSONDecoder().decode(type, from: data)) ?? fallback
    }

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}

// MARK: - Tabata

@Model
final class TabataWorkout {
    var id: UUID = UUID()
    var name: String = ""
    var prepareSeconds: Int = 10
    var workSeconds: Int = 40
    var restSeconds: Int = 0
    var cycles: Int = 7
    var rounds: Int = 3
    var restBetweenRoundsSeconds: Int = 30
    var cycleNames: [String] = []
    /// WorkoutPicture id per cycle as a string; "" means no picture.
    var cycleImageIDs: [String] = []
    var createdAt: Date = Date()

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    var draft: TabataDraft {
        TabataDraft(name: name, prepareSeconds: prepareSeconds, workSeconds: workSeconds, restSeconds: restSeconds,
                    cycles: cycles, rounds: rounds, restBetweenRoundsSeconds: restBetweenRoundsSeconds,
                    cycleNames: cycleNames, cycleImageIDs: cycleImageIDs)
    }

    func apply(_ d: TabataDraft) {
        name = d.name.trimmingCharacters(in: .whitespaces)
        prepareSeconds = d.prepareSeconds
        workSeconds = d.workSeconds
        restSeconds = d.restSeconds
        cycles = d.cycles
        rounds = d.rounds
        restBetweenRoundsSeconds = d.restBetweenRoundsSeconds
        cycleNames = Array(d.cycleNames.prefix(d.cycles))
        cycleImageIDs = Array(d.cycleImageIDs.prefix(d.cycles))
    }

    var summary: String { draft.summary }
}

/// Editable copy of a Tabata; also builds the interval timeline.
struct TabataDraft: Equatable {
    var name = ""
    var prepareSeconds = 10
    var workSeconds = 40
    var restSeconds = 0
    var cycles = 7
    var rounds = 3
    var restBetweenRoundsSeconds = 30
    var cycleNames: [String] = Array(repeating: "", count: 7)
    var cycleImageIDs: [String] = Array(repeating: "", count: 7)

    /// Name spoken and shown for a cycle; blank means "Work".
    func exerciseName(cycle index: Int) -> String {
        let raw = index < cycleNames.count ? cycleNames[index].trimmingCharacters(in: .whitespaces) : ""
        return raw.isEmpty ? "Work" : raw
    }

    func imageID(cycle index: Int) -> UUID? {
        index < cycleImageIDs.count ? UUID(uuidString: cycleImageIDs[index]) : nil
    }

    var intervals: [TabataInterval] {
        var list: [TabataInterval] = []
        if prepareSeconds > 0 {
            list.append(TabataInterval(phase: .prepare, seconds: prepareSeconds, exercise: exerciseName(cycle: 0), cycle: 1, round: 1, imageID: imageID(cycle: 0)))
        }
        for round in 1...max(1, rounds) {
            for cycle in 1...max(1, cycles) {
                let name = exerciseName(cycle: cycle - 1)
                list.append(TabataInterval(phase: .work, seconds: max(1, workSeconds), exercise: name, cycle: cycle, round: round, imageID: imageID(cycle: cycle - 1)))
                let lastCycle = cycle == cycles
                let lastRound = round == rounds
                if lastCycle && lastRound { continue }
                if lastCycle {
                    // Rest between rounds replaces the normal rest after the last cycle.
                    let pause = restBetweenRoundsSeconds > 0 ? restBetweenRoundsSeconds : restSeconds
                    if pause > 0 {
                        list.append(TabataInterval(phase: .rest, seconds: pause, exercise: exerciseName(cycle: 0), cycle: cycle, round: round, isRoundBreak: true, imageID: imageID(cycle: 0)))
                    }
                } else if restSeconds > 0 {
                    list.append(TabataInterval(phase: .rest, seconds: restSeconds, exercise: exerciseName(cycle: cycle), cycle: cycle, round: round, imageID: imageID(cycle: cycle)))
                }
            }
        }
        return list
    }

    /// Workout time excluding the prepare countdown.
    var workoutSeconds: Int { intervals.filter { $0.phase != .prepare }.reduce(0) { $0 + $1.seconds } }
    var totalSeconds: Int { intervals.reduce(0) { $0 + $1.seconds } }

    var summary: String { "\(cycles) cycles × \(rounds) rounds · \(WorkoutFormat.minutes(workoutSeconds))" }
}

enum TabataPhase: String {
    case prepare, work, rest

    var title: String {
        switch self {
        case .prepare: return "Get ready"
        case .work: return "Work"
        case .rest: return "Rest"
        }
    }
}

struct TabataInterval: Equatable {
    let phase: TabataPhase
    let seconds: Int
    /// For work: this exercise. For prepare and rest: the exercise coming next.
    let exercise: String
    let cycle: Int
    let round: Int
    var isRoundBreak = false
    /// Picture of `exercise`, if any.
    var imageID: UUID? = nil
}

// MARK: - Rep workouts

struct RepExercise: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name = ""
    var reps = 10
    var weight: Double? = nil
    var note = ""
    /// Optional WorkoutPicture shown while this exercise runs.
    var imageID: UUID? = nil
}

struct RepSet: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var repeats = 1
    var exercises: [RepExercise] = []
}

@Model
final class RepWorkout {
    var id: UUID = UUID()
    var name: String = ""
    var setsData: Data = Data()
    /// Optional rest between rounds and sets; 0 means none.
    var restBetweenSetsSeconds: Int = 0
    var createdAt: Date = Date()

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    var sets: [RepSet] {
        get { WorkoutJSON.decode([RepSet].self, from: setsData, fallback: []) }
        set { setsData = WorkoutJSON.encode(newValue) }
    }

    var summary: String {
        let s = sets
        let exercises = s.reduce(0) { $0 + $1.exercises.count }
        return "\(s.count) set\(s.count == 1 ? "" : "s") · \(exercises) exercise\(exercises == 1 ? "" : "s")"
    }
}

/// One exercise occurrence while running a rep workout.
struct RepStep: Equatable {
    let setIndex: Int
    let round: Int
    let rounds: Int
    let exerciseIndex: Int
    let exerciseCount: Int
    let exercise: RepExercise

    var position: String {
        let setText = rounds > 1 ? "Set \(setIndex + 1), round \(round) of \(rounds)" : "Set \(setIndex + 1)"
        return "\(setText) · Exercise \(exerciseIndex + 1) of \(exerciseCount)"
    }

    static func steps(for sets: [RepSet]) -> [RepStep] {
        var list: [RepStep] = []
        for (si, set) in sets.enumerated() where !set.exercises.isEmpty {
            let rounds = max(1, set.repeats)
            for round in 1...rounds {
                for (ei, ex) in set.exercises.enumerated() {
                    list.append(RepStep(setIndex: si, round: round, rounds: rounds, exerciseIndex: ei, exerciseCount: set.exercises.count, exercise: ex))
                }
            }
        }
        return list
    }
}

/// Planned vs actual numbers for one finished exercise.
struct RepLogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var setIndex: Int
    var round: Int
    var plannedReps: Int
    var plannedWeight: Double?
    var actualReps: Int
    var actualWeight: Double?
}

// MARK: - History

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var workoutID: UUID?
    var kindRaw: String = WorkoutKind.tabata.rawValue
    var name: String = ""
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var completed: Bool = false
    var logData: Data = Data()

    init(workoutID: UUID?, kind: WorkoutKind, name: String, startedAt: Date, endedAt: Date, completed: Bool, log: [RepLogEntry] = []) {
        self.id = UUID()
        self.workoutID = workoutID
        self.kindRaw = kind.rawValue
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.completed = completed
        self.logData = WorkoutJSON.encode(log)
    }

    var kind: WorkoutKind { WorkoutKind(rawValue: kindRaw) ?? .tabata }
    var durationSeconds: Int { max(0, Int(endedAt.timeIntervalSince(startedAt))) }
    var log: [RepLogEntry] { WorkoutJSON.decode([RepLogEntry].self, from: logData, fallback: []) }
}

// MARK: - Pictures

/// A picture for one Tabata cycle or rep exercise, referenced by id.
@Model
final class WorkoutPicture {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data = Data()

    init(imageData: Data) {
        self.id = UUID()
        self.imageData = imageData
    }
}

enum WorkoutPictureStore {
    static func image(_ id: UUID?, context: ModelContext) -> UIImage? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<WorkoutPicture>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first.flatMap { UIImage(data: $0.imageData) }
    }

    /// Loads all pictures up front so a running workout never waits on disk.
    static func images(_ ids: [UUID?], context: ModelContext) -> [UUID: UIImage] {
        var result: [UUID: UIImage] = [:]
        for id in Set(ids.compactMap { $0 }) {
            if let image = image(id, context: context) { result[id] = image }
        }
        return result
    }

    /// Deletes pictures no workout uses any more (removed, replaced, or
    /// picked in an editor that was cancelled).
    static func removeUnused(context: ModelContext) {
        var used = Set<UUID>()
        for w in (try? context.fetch(FetchDescriptor<TabataWorkout>())) ?? [] {
            used.formUnion(w.cycleImageIDs.compactMap(UUID.init(uuidString:)))
        }
        for w in (try? context.fetch(FetchDescriptor<RepWorkout>())) ?? [] {
            used.formUnion(w.sets.flatMap(\.exercises).compactMap(\.imageID))
        }
        let all = (try? context.fetch(FetchDescriptor<WorkoutPicture>())) ?? []
        for picture in all where !used.contains(picture.id) {
            context.delete(picture)
        }
        try? context.save()
    }
}
