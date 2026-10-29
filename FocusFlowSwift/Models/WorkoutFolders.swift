import Foundation
import SwiftData

/// A folder of workouts, e.g. "Insanity". Holds Tabatas, rep workouts and
/// other folders. Its tags count for everything inside it, at any depth.
@Model
final class WorkoutFolder {
    var id: UUID = UUID()
    var name: String = ""
    var tags: [String] = []
    var createdAt: Date = Date()
    /// The folder it's inside; nil = top level. (Added later; older folders are top level.)
    var parentID: UUID? = nil

    init(name: String, tags: [String] = [], parentID: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.tags = WorkoutTags.clean(tags)
        self.parentID = parentID
        self.createdAt = Date()
    }
}

/// Workout-folder helpers on top of the shared FolderTree.
enum WorkoutFolderTree {
    static func chain(from id: UUID?, in folders: [WorkoutFolder]) -> [WorkoutFolder] {
        FolderTree.chain(from: id, in: folders)
    }

    /// "Insanity › Month 1"
    static func path(_ folder: WorkoutFolder, in folders: [WorkoutFolder]) -> String {
        FolderTree.path(folder, in: folders)
    }

    static func descendants(of id: UUID, in folders: [WorkoutFolder]) -> Set<UUID> {
        FolderTree.descendants(of: id, in: folders)
    }

    /// Folders directly inside `id`, by name. nil = top level.
    static func children(of id: UUID?, in folders: [WorkoutFolder]) -> [WorkoutFolder] {
        FolderTree.children(of: id, in: folders)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Tags of the folder and every folder above it.
    static func inheritedTags(_ id: UUID?, in folders: [WorkoutFolder]) -> [String] {
        WorkoutTags.clean(chain(from: id, in: folders).flatMap(\.tags))
    }

    static func sortedByPath(_ folders: [WorkoutFolder]) -> [(folder: WorkoutFolder, path: String)] {
        FolderTree.sortedByPath(folders)
    }
}

enum WorkoutTags {
    /// Offered before the user has made their own.
    static let suggested = ["Cardio", "Circuit training", "Strength", "HIIT", "Warm up", "Cool down",
                            "Core", "Upper body", "Lower body", "Mobility"]

    /// Trimmed, no blanks, no case-insensitive duplicates, original order kept.
    static func clean(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let t = tag.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { return nil }
            return t
        }
    }

    /// Every tag in use plus the suggestions, sorted.
    static func all(items: [WorkoutItem], folders: [WorkoutFolder]) -> [String] {
        clean(items.flatMap(\.tags) + folders.flatMap(\.tags) + suggested)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Only tags actually used on workouts or folders.
    static func used(items: [WorkoutItem], folders: [WorkoutFolder]) -> [String] {
        clean(items.flatMap(\.tags) + folders.flatMap(\.tags))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func contains(_ tags: [String], _ tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }
}

/// A Tabata or a rep workout, so lists, folders and search treat both alike.
enum WorkoutItem: Identifiable, Hashable {
    case tabata(TabataWorkout)
    case reps(RepWorkout)

    var id: UUID {
        switch self {
        case .tabata(let w): return w.id
        case .reps(let w): return w.id
        }
    }

    var kind: WorkoutKind {
        if case .tabata = self { return .tabata }
        return .reps
    }

    var name: String {
        switch self {
        case .tabata(let w): return w.name
        case .reps(let w): return w.name
        }
    }

    var summary: String {
        switch self {
        case .tabata(let w): return w.summary
        case .reps(let w): return w.summary + (PausedRunStore.load(w.id) != nil ? " · Paused" : "")
        }
    }

    var createdAt: Date {
        switch self {
        case .tabata(let w): return w.createdAt
        case .reps(let w): return w.createdAt
        }
    }

    var tags: [String] {
        switch self {
        case .tabata(let w): return w.tags
        case .reps(let w): return w.tags
        }
    }

    var folderID: UUID? {
        switch self {
        case .tabata(let w): return w.folderID
        case .reps(let w): return w.folderID
        }
    }

    func setTags(_ tags: [String]) {
        switch self {
        case .tabata(let w): w.tags = WorkoutTags.clean(tags)
        case .reps(let w): w.tags = WorkoutTags.clean(tags)
        }
    }

    func setFolder(_ id: UUID?) {
        switch self {
        case .tabata(let w): w.folderID = id
        case .reps(let w): w.folderID = id
        }
    }

    /// Its own tags plus those of its folder and every folder above it.
    func effectiveTags(folders: [WorkoutFolder]) -> [String] {
        WorkoutTags.clean(tags + WorkoutFolderTree.inheritedTags(folderID, in: folders))
    }

    func folder(in folders: [WorkoutFolder]) -> WorkoutFolder? {
        guard let folderID else { return nil }
        return folders.first { $0.id == folderID }
    }

    /// Everything search looks at: name, kind, exercises, parts, notes, tags and folder.
    func searchFields(folders: [WorkoutFolder]) -> [String] {
        var fields = [name, kind.title, kind == .tabata ? "tabata" : "reps rep"]
        switch self {
        case .tabata(let w):
            let d = w.draft
            fields += d.parts.map(\.name) + d.parts.flatMap(\.cycleNames)
        case .reps(let w):
            let exercises = w.sets.flatMap(\.exercises)
            fields += exercises.map(\.name) + exercises.map(\.note)
        }
        fields += WorkoutFolderTree.chain(from: folderID, in: folders).map(\.name)
        return fields + effectiveTags(folders: folders)
    }

    static func all(_ tabatas: [TabataWorkout], _ reps: [RepWorkout]) -> [WorkoutItem] {
        tabatas.map(WorkoutItem.tabata) + reps.map(WorkoutItem.reps)
    }
}

/// Search terms and tag filters shared by the Workouts list and folders.
struct WorkoutFilter {
    var text: String = ""
    var tags: Set<String> = []

    var terms: [String] { text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init) }
    var isActive: Bool { !terms.isEmpty || !tags.isEmpty }

    func matches(_ fields: [String], tags itemTags: [String]) -> Bool {
        let haystack = fields.joined(separator: " ").lowercased()
        guard terms.allSatisfy({ haystack.contains($0) }) else { return false }
        return tags.allSatisfy { WorkoutTags.contains(itemTags, $0) }
    }

    func matches(_ item: WorkoutItem, folders: [WorkoutFolder]) -> Bool {
        matches(item.searchFields(folders: folders), tags: item.effectiveTags(folders: folders))
    }

    /// Matches the folder's name, the folders above it, and inherited tags.
    func matches(_ folder: WorkoutFolder, folders: [WorkoutFolder]) -> Bool {
        let chain = WorkoutFolderTree.chain(from: folder.id, in: folders)
        let tags = WorkoutFolderTree.inheritedTags(folder.id, in: folders)
        return matches(chain.map(\.name) + ["folder"] + tags, tags: tags)
    }
}
