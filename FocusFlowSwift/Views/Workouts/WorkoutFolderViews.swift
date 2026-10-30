import SwiftUI
import SwiftData

// MARK: - Shared actions

/// Duplicate / delete / move, used by the Workouts list and folders.
enum WorkoutActions {
    static func duplicate(_ item: WorkoutItem, context: ModelContext) {
        switch item {
        case .tabata(let w):
            let copy = TabataWorkout(name: w.name + " copy")
            copy.apply(w.draft)
            copy.name = w.name + " copy"
            copy.folderID = w.folderID
            copy.tags = w.tags
            context.insert(copy)
        case .reps(let w):
            let copy = RepWorkout(name: w.name + " copy")
            copy.sets = w.sets.map { set in
                var s = set
                s.id = UUID()
                s.exercises = set.exercises.map { var e = $0; e.id = UUID(); return e }
                return s
            }
            copy.restBetweenSetsSeconds = w.restBetweenSetsSeconds
            copy.folderID = w.folderID
            copy.tags = w.tags
            context.insert(copy)
        }
        try? context.save()
    }

    static func delete(_ item: WorkoutItem, context: ModelContext) {
        switch item {
        case .tabata(let w): context.delete(w)
        case .reps(let w): context.delete(w)
        }
        try? context.save()
        WorkoutPictureStore.removeUnused(context: context)
    }

    static func move(_ item: WorkoutItem, to folder: WorkoutFolder?, context: ModelContext) {
        item.setFolder(folder?.id)
        try? context.save()
    }

    /// Deletes the folder only. Its workouts and subfolders move up into
    /// the folder it was in (or the top level).
    static func deleteFolder(_ folder: WorkoutFolder, items: [WorkoutItem], folders: [WorkoutFolder], context: ModelContext) {
        let parent = folder.parentID
        for item in items where item.folderID == folder.id { item.setFolder(parent) }
        for child in folders where child.parentID == folder.id { child.parentID = parent }
        context.delete(folder)
        try? context.save()
    }
}

// MARK: - Rows & chips

struct WorkoutItemRow: View {
    let item: WorkoutItem
    let folders: [WorkoutFolder]
    var showFolder = true
    var guides: [ExerciseGuide] = []

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name).font(.headline)
                    GuideCoverageBadge(coverage: GuideCoverage.of(item, folders: folders, guides: guides))
                }
                Text(item.summary).font(.subheadline).foregroundStyle(.secondary)
                if showFolder, let folder = item.folder(in: folders) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                        Text(WorkoutFolderTree.path(folder, in: folders))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if !item.tags.isEmpty { WorkoutTagChips(tags: item.tags) }
            }
        }
        .padding(.vertical, 2)
    }
}

struct WorkoutFolderRow: View {
    let folder: WorkoutFolder
    let items: [WorkoutItem]
    let folders: [WorkoutFolder]
    /// Show where the folder lives (for search results).
    var showPath = false
    var guides: [ExerciseGuide] = []

    var body: some View {
        // Counts include everything in subfolders too.
        let subtree = WorkoutFolderTree.descendants(of: folder.id, in: folders).union([folder.id])
        let inside = items.filter { $0.folderID.map(subtree.contains) ?? false }
        let tabatas = inside.filter { $0.kind == .tabata }.count
        let reps = inside.count - tabatas
        let subfolders = WorkoutFolderTree.children(of: folder.id, in: folders).count
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 48, height: 48)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(folder.name).font(.headline)
                    GuideCoverageBadge(coverage: GuideCoverage.of(folder, items: items, folders: folders, guides: guides))
                }
                if showPath, folder.parentID != nil {
                    Text(WorkoutFolderTree.path(folder, in: folders)).font(.caption).foregroundStyle(.secondary)
                }
                Text([subfolders > 0 ? "\(subfolders) folder\(subfolders == 1 ? "" : "s")" : nil,
                      tabatas > 0 ? "\(tabatas) Tabata\(tabatas == 1 ? "" : "s")" : nil,
                      reps > 0 ? "\(reps) rep workout\(reps == 1 ? "" : "s")" : nil]
                        .compactMap { $0 }.joined(separator: " · ").nilIfEmpty ?? "Empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !folder.tags.isEmpty { WorkoutTagChips(tags: folder.tags) }
            }
        }
        .padding(.vertical, 2)
    }
}

struct WorkoutTagChips: View {
    let tags: [String]

    var body: some View {
        VocabFlowLayout(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(WorkoutTagChips.color(tag).opacity(0.15)))
                    .foregroundStyle(WorkoutTagChips.color(tag))
            }
        }
    }

    /// Same tag, same colour everywhere.
    static func color(_ tag: String) -> Color {
        let palette: [Color] = [.red, .orange, .green, .blue, .purple, .pink, .teal, .indigo, .brown, .mint]
        let sum = tag.lowercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

/// Horizontal tag chips; tap to filter (all selected tags must match).
struct WorkoutTagFilterBar: View {
    let tags: [String]
    @Binding var selected: Set<String>

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if !selected.isEmpty {
                        Button { selected = [] } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark")
                                Text("Clear")
                            }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(tags, id: \.self) { tag in
                        let on = selected.contains(tag)
                        Button {
                            if on { selected.remove(tag) } else { selected.insert(tag) }
                        } label: {
                            Text(tag)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(on ? WorkoutTagChips.color(tag) : WorkoutTagChips.color(tag).opacity(0.12)))
                                .foregroundStyle(on ? Color.white : WorkoutTagChips.color(tag))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
        }
    }
}

/// "Move to folder" submenu for a workout's context menu.
struct WorkoutMoveMenu: View {
    let item: WorkoutItem
    let folders: [WorkoutFolder]
    let onNewFolder: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Menu {
            if item.folderID != nil {
                Button("Remove from folder", systemImage: "folder.badge.minus") {
                    WorkoutActions.move(item, to: nil, context: modelContext)
                }
            }
            ForEach(WorkoutFolderTree.sortedByPath(folders), id: \.folder.id) { entry in
                Button(entry.path, systemImage: item.folderID == entry.folder.id ? "checkmark" : "folder") {
                    WorkoutActions.move(item, to: entry.folder, context: modelContext)
                }
            }
            Divider()
            Button("New folder…", systemImage: "folder.badge.plus", action: onNewFolder)
        } label: {
            Label("Move to folder", systemImage: "folder")
        }
    }
}

// MARK: - Tag editor

/// Current tags as removable chips, a field to type a new one, and
/// suggestions to tap.
struct WorkoutTagEditor: View {
    @Binding var tags: [String]
    let suggestions: [String]
    @State private var newTag = ""

    var body: some View {
        if !tags.isEmpty {
            VocabFlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        tags.removeAll { $0 == tag }
                    } label: {
                        HStack(spacing: 4) {
                            Text(tag).fixedSize()
                            Image(systemName: "xmark.circle.fill").font(.caption2)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(WorkoutTagChips.color(tag).opacity(0.18)))
                        .foregroundStyle(WorkoutTagChips.color(tag))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        HStack {
            TextField("Add a tag", text: $newTag)
                .submitLabel(.done)
                .onSubmit(add)
            Button("Add", action: add)
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        let remaining = suggestions.filter { !WorkoutTags.contains(tags, $0) }
        if !remaining.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested tags (tap to add)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VocabFlowLayout(spacing: 6) {
                    ForEach(remaining, id: \.self) { tag in
                        Button {
                            tags = WorkoutTags.clean(tags + [tag])
                        } label: {
                            // Icon and text drawn separately so the name always shows.
                            HStack(spacing: 3) {
                                Image(systemName: "plus").font(.caption2.bold())
                                Text(tag).font(.caption).fixedSize()
                            }
                            .foregroundStyle(WorkoutTagChips.color(tag))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(WorkoutTagChips.color(tag).opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func add() {
        tags = WorkoutTags.clean(tags + [newTag])
        newTag = ""
    }
}

/// Folder picker + tag editor, used inside the workout editors.
struct WorkoutFolderAndTagsSection: View {
    @Binding var folderID: UUID?
    @Binding var tags: [String]
    @Query(sort: \WorkoutFolder.name) private var folders: [WorkoutFolder]
    @Query private var tabatas: [TabataWorkout]
    @Query private var reps: [RepWorkout]

    var body: some View {
        Section {
            Picker("Folder", selection: $folderID) {
                Text("None").tag(UUID?.none)
                ForEach(WorkoutFolderTree.sortedByPath(folders), id: \.folder.id) { entry in
                    Text(entry.path).tag(UUID?.some(entry.folder.id))
                }
            }
            WorkoutTagEditor(tags: $tags, suggestions: WorkoutTags.all(items: WorkoutItem.all(tabatas, reps), folders: folders))
        } header: {
            Text("Folder & tags")
        } footer: {
            let inherited = WorkoutFolderTree.inheritedTags(folderID, in: folders)
            if !inherited.isEmpty {
                Text("Also tagged \(inherited.joined(separator: ", ")) from its folder\(WorkoutFolderTree.chain(from: folderID, in: folders).count > 1 ? "s" : "").")
            }
        }
    }
}

// MARK: - Folder & tag sheets

/// Create or edit a folder (name + tags).
struct WorkoutFolderEditor: View {
    let folder: WorkoutFolder?
    /// Where a new folder goes; nil = top level.
    var parentID: UUID? = nil
    var onCreated: ((WorkoutFolder) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var folders: [WorkoutFolder]
    @Query private var tabatas: [TabataWorkout]
    @Query private var reps: [RepWorkout]

    @State private var name = ""
    @State private var tags: [String] = []
    @State private var parent: UUID?
    @State private var loaded = false

    /// Folders it can go inside: not itself, and not one of its own subfolders.
    private var parentChoices: [(folder: WorkoutFolder, path: String)] {
        guard let folder else { return WorkoutFolderTree.sortedByPath(folders) }
        let blocked = WorkoutFolderTree.descendants(of: folder.id, in: folders).union([folder.id])
        return WorkoutFolderTree.sortedByPath(folders).filter { !blocked.contains($0.folder.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder name, e.g. Insanity", text: $name)
                    Picker("Inside", selection: $parent) {
                        Text("Top level").tag(UUID?.none)
                        ForEach(parentChoices, id: \.folder.id) { entry in
                            Text(entry.path).tag(UUID?.some(entry.folder.id))
                        }
                    }
                }
                Section {
                    WorkoutTagEditor(tags: $tags, suggestions: WorkoutTags.all(items: WorkoutItem.all(tabatas, reps), folders: folders))
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Folder tags count for every workout in the folder and its subfolders when you search or filter.")
                }
            }
            .navigationTitle(folder == nil ? "New folder" : "Edit folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = folder?.name ?? ""
                tags = folder?.tags ?? []
                parent = folder?.parentID ?? parentID
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let folder {
            folder.name = trimmed
            folder.tags = WorkoutTags.clean(tags)
            // Re-checked in case folders changed while editing.
            if let parent, parentChoices.contains(where: { $0.folder.id == parent }) {
                folder.parentID = parent
            } else if parent == nil {
                folder.parentID = nil
            }
        } else {
            let new = WorkoutFolder(name: trimmed, tags: tags, parentID: parent)
            modelContext.insert(new)
            onCreated?(new)
        }
        try? modelContext.save()
        dismiss()
    }
}

/// Edit one workout's tags (and folder) without opening the full editor.
struct WorkoutTagsSheet: View {
    let item: WorkoutItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String] = []
    @State private var folderID: UUID?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                WorkoutFolderAndTagsSection(folderID: $folderID, tags: $tags)
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        item.setTags(tags)
                        item.setFolder(folderID)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                tags = item.tags
                folderID = item.folderID
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Pick existing workouts to put in a folder.
struct AddWorkoutsToFolderSheet: View {
    let folder: WorkoutFolder

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TabataWorkout.createdAt, order: .reverse) private var tabatas: [TabataWorkout]
    @Query(sort: \RepWorkout.createdAt, order: .reverse) private var reps: [RepWorkout]
    @Query private var folders: [WorkoutFolder]
    @State private var selected: Set<UUID> = []
    @State private var search = ""

    private var candidates: [WorkoutItem] {
        let filter = WorkoutFilter(text: search)
        return WorkoutItem.all(tabatas, reps)
            .filter { $0.folderID != folder.id && filter.matches($0, folders: folders) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach([WorkoutKind.tabata, .reps]) { kind in
                    let list = candidates.filter { $0.kind == kind }
                    if !list.isEmpty {
                        Section(kind == .tabata ? "Tabatas" : "Rep workouts") {
                            ForEach(list) { item in
                                Button {
                                    if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                                } label: {
                                    HStack {
                                        Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(item.id) ? Color.accentColor : .secondary)
                                        VStack(alignment: .leading) {
                                            Text(item.name).foregroundStyle(.primary)
                                            if let f = item.folder(in: folders) {
                                                Text("In \(WorkoutFolderTree.path(f, in: folders))").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search workouts")
            .navigationTitle("Add to \(folder.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") {
                        for item in WorkoutItem.all(tabatas, reps) where selected.contains(item.id) {
                            item.setFolder(folder.id)
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}

// MARK: - Folder screen

struct WorkoutFolderView: View {
    let folder: WorkoutFolder

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TabataWorkout.createdAt, order: .reverse) private var tabatas: [TabataWorkout]
    @Query(sort: \RepWorkout.createdAt, order: .reverse) private var reps: [RepWorkout]
    @Query private var folders: [WorkoutFolder]
    @Query private var guides: [ExerciseGuide]

    @State private var search = ""
    @State private var tagFilter: Set<String> = []
    @State private var editingFolder = false
    @State private var addingExisting = false
    @State private var creatingTabata = false
    @State private var creatingReps = false
    @State private var editingTabata: TabataWorkout?
    @State private var editingReps: RepWorkout?
    @State private var taggingItem: WorkoutItem?
    @State private var newFolderFor: WorkoutItem?
    @State private var confirmDelete = false
    @State private var creatingSubfolder = false
    @State private var editingSubfolder: WorkoutFolder?
    @State private var subfolderToDelete: WorkoutFolder?

    private var allItems: [WorkoutItem] { WorkoutItem.all(tabatas, reps) }
    private var subfolders: [WorkoutFolder] { WorkoutFolderTree.children(of: folder.id, in: folders) }

    /// Workouts directly in this folder.
    private var inside: [WorkoutItem] { allItems.filter { $0.folderID == folder.id } }

    /// Workouts in this folder or any folder inside it.
    private var insideDeep: [WorkoutItem] {
        let ids = WorkoutFolderTree.descendants(of: folder.id, in: folders).union([folder.id])
        return allItems.filter { $0.folderID.map(ids.contains) ?? false }
    }

    private var filter: WorkoutFilter { WorkoutFilter(text: search, tags: tagFilter) }

    /// While searching or filtering, look through subfolders too.
    private var shownItems: [WorkoutItem] {
        filter.isActive ? insideDeep.filter { filter.matches($0, folders: folders) } : inside
    }

    private var shownFolders: [WorkoutFolder] {
        guard filter.isActive else { return subfolders }
        let ids = WorkoutFolderTree.descendants(of: folder.id, in: folders)
        return folders.filter { ids.contains($0.id) && filter.matches($0, folders: folders) }
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkoutTagFilterBar(tags: WorkoutTags.used(items: insideDeep, folders: []), selected: $tagFilter)
            List {
                let inherited = WorkoutFolderTree.inheritedTags(folder.id, in: folders)
                if !inherited.isEmpty {
                    Section {
                        WorkoutTagChips(tags: inherited)
                    } footer: {
                        Text(folder.parentID == nil
                             ? "These tags count for everything in this folder."
                             : "These tags (including ones from the folders above) count for everything in this folder.")
                    }
                }
                if inside.isEmpty && subfolders.isEmpty {
                    ContentUnavailableView {
                        Label("Empty folder", systemImage: "folder")
                    } description: {
                        Text("Add workouts you already have, create new ones, or add a folder inside.")
                    } actions: {
                        Button("Add workouts") { addingExisting = true }.buttonStyle(.borderedProminent)
                        Button("New folder inside") { creatingSubfolder = true }
                    }
                } else if filter.isActive && shownItems.isEmpty && shownFolders.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                if !shownFolders.isEmpty {
                    Section("Folders") {
                        ForEach(shownFolders) { sub in
                            NavigationLink {
                                WorkoutFolderView(folder: sub)
                            } label: {
                                WorkoutFolderRow(folder: sub, items: allItems, folders: folders, showPath: filter.isActive, guides: guides)
                            }
                            .contextMenu {
                                Button("Edit or move folder", systemImage: "pencil") { editingSubfolder = sub }
                                Button("Delete folder", systemImage: "trash", role: .destructive) { subfolderToDelete = sub }
                            }
                        }
                    }
                }
                ForEach([WorkoutKind.tabata, .reps]) { kind in
                    let list = shownItems.filter { $0.kind == kind }
                    if !list.isEmpty {
                        Section(kind == .tabata ? "Tabatas" : "Rep workouts") {
                            ForEach(list) { item in row(item) }
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .searchable(text: $search, prompt: "Search in \(folder.name)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New Tabata here", systemImage: "timer") { creatingTabata = true }
                    Button("New rep workout here", systemImage: "dumbbell.fill") { creatingReps = true }
                    Button("New folder inside", systemImage: "folder.badge.plus") { creatingSubfolder = true }
                    Button("Add existing workouts", systemImage: "plus.rectangle.on.folder") { addingExisting = true }
                    Divider()
                    Button("Edit or move folder", systemImage: "pencil") { editingFolder = true }
                    Button("Delete folder", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete \(folder.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete folder", role: .destructive) {
                WorkoutActions.deleteFolder(folder, items: allItems, folders: folders, context: modelContext)
                dismiss()
            }
        } message: {
            Text(deleteMessage)
        }
        .confirmationDialog("Delete \(subfolderToDelete?.name ?? "folder")?",
                            isPresented: Binding(get: { subfolderToDelete != nil }, set: { if !$0 { subfolderToDelete = nil } }),
                            titleVisibility: .visible, presenting: subfolderToDelete) { sub in
            Button("Delete folder", role: .destructive) {
                WorkoutActions.deleteFolder(sub, items: allItems, folders: folders, context: modelContext)
            }
        } message: { _ in
            Text("Its workouts and folders move into \(folder.name).")
        }
        .sheet(isPresented: $editingFolder) { WorkoutFolderEditor(folder: folder) }
        .sheet(isPresented: $creatingSubfolder) { WorkoutFolderEditor(folder: nil, parentID: folder.id) }
        .sheet(item: $editingSubfolder) { WorkoutFolderEditor(folder: $0) }
        .sheet(isPresented: $addingExisting) { AddWorkoutsToFolderSheet(folder: folder) }
        .sheet(isPresented: $creatingTabata) { TabataEditorView(workout: nil, folderID: folder.id) }
        .sheet(isPresented: $creatingReps) { RepWorkoutEditorView(workout: nil, folderID: folder.id) }
        .sheet(item: $editingTabata) { TabataEditorView(workout: $0) }
        .sheet(item: $editingReps) { RepWorkoutEditorView(workout: $0) }
        .sheet(item: $taggingItem) { WorkoutTagsSheet(item: $0) }
        .sheet(item: $newFolderFor) { item in
            WorkoutFolderEditor(folder: nil, parentID: folder.id) { new in item.setFolder(new.id) }
        }
    }

    private var deleteMessage: String {
        let target = WorkoutFolderTree.chain(from: folder.parentID, in: folders).first?.name
        return target.map { "Its workouts and folders are kept and move into \($0)." }
            ?? "Its workouts and folders are kept and move to the top level."
    }

    private func row(_ item: WorkoutItem) -> some View {
        NavigationLink {
            WorkoutItemDetail(item: item)
        } label: {
            WorkoutItemRow(item: item, folders: folders, showFolder: item.folderID != folder.id, guides: guides)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { edit(item) }
            Button("Tags…", systemImage: "tag") { taggingItem = item }
            WorkoutMoveMenu(item: item, folders: folders) { newFolderFor = item }
            Button("Duplicate", systemImage: "plus.square.on.square") { WorkoutActions.duplicate(item, context: modelContext) }
            Button("Delete", systemImage: "trash", role: .destructive) { WorkoutActions.delete(item, context: modelContext) }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { WorkoutActions.delete(item, context: modelContext) }
            Button("Remove", systemImage: "folder.badge.minus") { WorkoutActions.move(item, to: nil, context: modelContext) }.tint(.gray)
            Button("Edit", systemImage: "pencil") { edit(item) }.tint(.orange)
        }
    }

    private func edit(_ item: WorkoutItem) {
        switch item {
        case .tabata(let w): editingTabata = w
        case .reps(let w): editingReps = w
        }
    }
}

/// Detail screen for either kind.
struct WorkoutItemDetail: View {
    let item: WorkoutItem

    var body: some View {
        switch item {
        case .tabata(let w): TabataDetailView(workout: w)
        case .reps(let w): RepWorkoutDetailView(workout: w)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// 📖 badge: green when every exercise has a saved how-to guide,
/// orange with a count when only some do, nothing when none do.
struct GuideCoverageBadge: View {
    let coverage: GuideCoverage

    var body: some View {
        if coverage.isComplete {
            Image(systemName: "book.closed.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityLabel("How-to guides saved for every exercise")
        } else if !coverage.isEmpty {
            HStack(spacing: 2) {
                Image(systemName: "book.closed")
                Text("\(coverage.saved)/\(coverage.total)").monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.orange)
            .accessibilityLabel("How-to guides saved for \(coverage.saved) of \(coverage.total) exercises")
        }
    }
}
