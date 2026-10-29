import Foundation

/// A folder that can sit inside another folder (workout and backlog folders).
protocol TreeFolder: AnyObject {
    var id: UUID { get }
    var name: String { get }
    var parentID: UUID? { get }
}

/// Walking a folder tree. Every walk stops on a repeat, so a bad parent
/// link can never loop forever.
enum FolderTree {
    /// The folder with `id`, then its parent, grandparent… up to the top.
    static func chain<F: TreeFolder>(from id: UUID?, in folders: [F]) -> [F] {
        var result: [F] = []
        var seen = Set<UUID>()
        var current = id
        while let cid = current, seen.insert(cid).inserted, let folder = folders.first(where: { $0.id == cid }) {
            result.append(folder)
            current = folder.parentID
        }
        return result
    }

    /// "Work › Q4 › Ideas"
    static func path<F: TreeFolder>(_ folder: F, in folders: [F]) -> String {
        chain(from: folder.id, in: folders).reversed().map(\.name).joined(separator: " › ")
    }

    /// Ids of every folder inside `id`, at any depth (not including `id`).
    static func descendants<F: TreeFolder>(of id: UUID, in folders: [F]) -> Set<UUID> {
        var result = Set<UUID>()
        var queue = [id]
        while let next = queue.popLast() {
            for child in folders where child.parentID == next && child.id != id && !result.contains(child.id) {
                result.insert(child.id)
                queue.append(child.id)
            }
        }
        return result
    }

    /// Folders directly inside `id` (unsorted). For nil: top-level folders,
    /// plus any whose parent no longer exists.
    static func children<F: TreeFolder>(of id: UUID?, in folders: [F]) -> [F] {
        let ids = Set(folders.map(\.id))
        return folders.filter { f in
            if let id { return f.parentID == id }
            guard let parent = f.parentID else { return true }
            return !ids.contains(parent)
        }
    }

    /// Folders that `folder` may move into: not itself or anything inside it.
    static func moveTargets<F: TreeFolder>(for folder: F, in folders: [F]) -> [F] {
        let blocked = descendants(of: folder.id, in: folders).union([folder.id])
        return folders.filter { !blocked.contains($0.id) }
    }

    /// All folders sorted by full path, for pickers and menus.
    static func sortedByPath<F: TreeFolder>(_ folders: [F]) -> [(folder: F, path: String)] {
        folders.map { ($0, path($0, in: folders)) }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }
}

extension WorkoutFolder: TreeFolder {}
extension BacklogFolder: TreeFolder {}
