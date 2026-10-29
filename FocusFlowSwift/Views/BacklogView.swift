import SwiftUI
import SwiftData

/// Backlog tasks are ordinary `Task` rows with `date == nil` — they exist but
/// haven't been scheduled onto any particular day yet. This view manages them
/// (create, file into folders, edit, delete) and doubles as the drag source
/// for pulling a task onto `TasksCalendarView`'s timeline (see
/// `TaskDragPayload`, declared in TasksCalendarView.swift).
///
/// Two presentations share this one implementation:
/// - `isDrawer: true` — a compact bottom drawer overlaid on top of the
///   calendar (still part of the same view hierarchy as the timeline, so a
///   system drag started here can be dropped straight onto a time slot).
/// - `isDrawer: false` — a full screen for more deliberate folder/task
///   management, presented as a sheet.
struct BacklogView: View {
    var isDrawer: Bool = false
    @Binding var isPresented: Bool
    var targetDate: Date = Date()
    var onSchedule: () -> Void = {}
    var onExpand: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BacklogFolder.sortOrder) private var folders: [BacklogFolder]
    @Query(filter: #Predicate<Task> { $0.date == nil }, sort: \Task.title) private var backlogTasks: [Task]

    @State private var selectedFolder: BacklogFolder?
    @State private var showUnfiledOnly = false
    @State private var quickTitle = ""
    @State private var showAddFolder = false
    @State private var newFolderName = ""
    @State private var editingTask: Task?
    @State private var folderPendingDeletion: BacklogFolder?
    /// Set while creating a folder inside another one.
    @State private var newFolderParent: BacklogFolder?
    @State private var renamingFolder: BacklogFolder?
    @State private var renameText = ""

    /// A folder shows its own tasks plus those in every folder inside it.
    private var filteredTasks: [Task] {
        if showUnfiledOnly {
            return backlogTasks.filter { $0.backlogFolder == nil }
        }
        guard let folder = selectedFolder else { return backlogTasks }
        let ids = FolderTree.descendants(of: folder.id, in: folders).union([folder.id])
        return backlogTasks.filter { $0.backlogFolder.map { ids.contains($0.id) } ?? false }
    }

    /// Sub-folders in the user's order (then by name).
    private func children(of id: UUID?) -> [BacklogFolder] {
        FolderTree.children(of: id, in: folders).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private func path(_ folder: BacklogFolder) -> String { FolderTree.path(folder, in: folders) }

    var body: some View {
        Group {
            if isDrawer {
                drawerLayout
            } else {
                NavigationStack {
                    fullLayout
                        .navigationTitle("Backlog")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { isPresented = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { editingTask != nil },
            set: { if !$0 { editingTask = nil } }
        )) {
            // Same actions sheet as a scheduled task gets (Notes,
            // Subtasks, Attach Files, Edit, etc.) — nothing about a task is
            // hidden just because it's sitting in the backlog; date/time are
            // the only fields it doesn't have yet.
            if let task = editingTask {
                TaskActionsView(task: task, selectedDate: targetDate, onTaskDeleted: {})
                    .presentationDetents([.medium, .large])
            }
        }
        .alert(newFolderParent.map { "New folder in \($0.name)" } ?? "New Folder", isPresented: $showAddFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = ""; newFolderParent = nil }
            Button("Create") { createFolder() }
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Folder name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingFolder = nil }
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if let folder = renamingFolder, !name.isEmpty { folder.name = name; try? modelContext.save() }
                renamingFolder = nil
            }
        }
        .alert("Delete Folder?", isPresented: Binding(
            get: { folderPendingDeletion != nil },
            set: { if !$0 { folderPendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { folderPendingDeletion = nil }
            Button("Delete", role: .destructive) { deleteFolder() }
        } message: {
            Text(folderPendingDeletion?.parentID == nil
                 ? "Tasks and folders inside move back to the top level (tasks to Unfiled) — nothing is deleted."
                 : "Tasks and folders inside move up into the folder above — nothing is deleted.")
        }
    }

    // MARK: - Drawer layout

    private var drawerLayout: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            HStack {
                Text("Backlog")
                    .font(.headline)
                Spacer()
                if let onExpand {
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                }
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 8)

            quickAddField

            folderChips
                .padding(.vertical, 8)

            if filteredTasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredTasks) { task in
                            taskRow(task)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: -4)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Full layout

    private var fullLayout: some View {
        VStack(spacing: 0) {
            quickAddField
                .padding(.top, 8)

            folderChips
                .padding(.vertical, 8)

            if filteredTasks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredTasks) { task in
                        taskRow(task)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(backlogTasks.isEmpty ? "No backlog tasks yet" : "No tasks in this folder")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - Shared pieces

    private var quickAddField: some View {
        HStack {
            TextField("Add a backlog task…", text: $quickTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addQuickTask() }
            Button {
                addQuickTask()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .disabled(quickTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal)
    }

    /// Top level: All · Unfiled · top folders. Inside a folder: ‹ back,
    /// the folder itself, then the folders inside it.
    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let current = selectedFolder {
                    Button {
                        selectedFolder = FolderTree.chain(from: current.parentID, in: folders).first
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to \(current.parentID == nil ? "all folders" : "parent folder")")

                    folderChip(title: path(current), isSelected: true) {}
                        .contextMenu { folderMenu(current) }
                    ForEach(children(of: current.id)) { sub in
                        folderChip(title: sub.name, isSelected: false, hasChildren: !children(of: sub.id).isEmpty) {
                            selectedFolder = sub
                        }
                        .contextMenu { folderMenu(sub) }
                    }
                } else {
                    folderChip(title: "All", isSelected: !showUnfiledOnly) {
                        showUnfiledOnly = false
                    }
                    folderChip(title: "Unfiled", isSelected: showUnfiledOnly) {
                        showUnfiledOnly = true
                    }
                    ForEach(children(of: nil)) { folder in
                        folderChip(title: folder.name, isSelected: false, hasChildren: !children(of: folder.id).isEmpty) {
                            selectedFolder = folder
                            showUnfiledOnly = false
                        }
                        .contextMenu { folderMenu(folder) }
                    }
                }
                Button {
                    newFolderParent = selectedFolder
                    showAddFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selectedFolder == nil ? "New folder" : "New folder inside")
            }
            .padding(.horizontal)
        }
    }

    /// Long-press menu on a folder chip.
    @ViewBuilder
    private func folderMenu(_ folder: BacklogFolder) -> some View {
        Button {
            newFolderParent = folder
            showAddFolder = true
        } label: {
            Label("New Folder Inside", systemImage: "folder.badge.plus")
        }
        Button {
            renameText = folder.name
            renamingFolder = folder
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Menu {
            if folder.parentID != nil {
                Button("Top Level") { move(folder, into: nil) }
            }
            ForEach(FolderTree.sortedByPath(FolderTree.moveTargets(for: folder, in: folders)), id: \.folder.id) { entry in
                if entry.folder.id != folder.parentID {
                    Button(entry.path) { move(folder, into: entry.folder) }
                }
            }
        } label: {
            Label("Move Folder", systemImage: "folder")
        }
        Button(role: .destructive) {
            folderPendingDeletion = folder
        } label: {
            Label("Delete Folder", systemImage: "trash")
        }
    }

    private func folderChip(title: String, isSelected: Bool, hasChildren: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                if hasChildren { Image(systemName: "chevron.right").font(.caption2) }
            }
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.indigo : Color.secondary.opacity(0.12))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func taskRow(_ task: Task) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Where it's filed, when that isn't obvious from the chips.
                if let folder = task.backlogFolder, folder.id != selectedFolder?.id {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                        Text(path(folder))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer()

            Text(task.priority)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(priorityColor(task.priority))
                .clipShape(Capsule())

            // A tap-triggered Menu here (not `.contextMenu` on the row) — a
            // long-press context menu on the same view as `.draggable` wins
            // the gesture arbitration and blocks the drag from ever starting.
            Menu {
                Button {
                    scheduleUntimed(task)
                } label: {
                    Label("Schedule for \(targetDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar.badge.plus")
                }
                Menu("Move to Folder") {
                    Button("Unfiled") { task.backlogFolder = nil; try? modelContext.save() }
                    ForEach(FolderTree.sortedByPath(folders), id: \.folder.id) { entry in
                        Button(entry.path) { task.backlogFolder = entry.folder; try? modelContext.save() }
                    }
                }
                Button(role: .destructive) {
                    deleteTask(task)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { editingTask = task }
        .draggable(TaskDragPayload(id: task.id)) {
            Text(task.title)
                .font(.caption)
                .padding(8)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteTask(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "P1": return .red
        case "P2": return .orange
        case "P3": return .blue
        case "P4": return .gray
        default: return .blue
        }
    }

    // MARK: - Actions

    private func addQuickTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let folderForNewTask = showUnfiledOnly ? nil : selectedFolder
        let task = Task(title: title, weight: 1.0, date: nil, priority: "P3", backlogFolder: folderForNewTask)
        modelContext.insert(task)
        try? modelContext.save()
        quickTitle = ""
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { newFolderName = ""; return }
        let folder = BacklogFolder(name: name, sortOrder: (folders.map(\.sortOrder).max() ?? 0) + 1,
                                   parentID: newFolderParent?.id)
        modelContext.insert(folder)
        try? modelContext.save()
        newFolderName = ""
        newFolderParent = nil
    }

    /// Deletes only the folder: its tasks and sub-folders move up one level.
    private func deleteFolder() {
        guard let folder = folderPendingDeletion else { return }
        let parent = FolderTree.chain(from: folder.parentID, in: folders).first
        for task in backlogTasks where task.backlogFolder?.id == folder.id { task.backlogFolder = parent }
        for child in folders where child.parentID == folder.id { child.parentID = folder.parentID }
        if let selected = selectedFolder,
           selected.id == folder.id || FolderTree.descendants(of: folder.id, in: folders).contains(selected.id) {
            selectedFolder = parent
        }
        modelContext.delete(folder)
        try? modelContext.save()
        folderPendingDeletion = nil
    }

    /// Moves a folder (with everything inside) into another folder, or to the top level.
    private func move(_ folder: BacklogFolder, into parent: BacklogFolder?) {
        // Never inside itself or its own sub-folders.
        if let parent, parent.id == folder.id || FolderTree.descendants(of: folder.id, in: folders).contains(parent.id) { return }
        folder.parentID = parent?.id
        try? modelContext.save()
    }

    private func deleteTask(_ task: Task) {
        modelContext.delete(task)
        try? modelContext.save()
    }

    /// Manual fallback for scheduling a backlog task without dragging —
    /// files it onto `targetDate` as an untimed task.
    private func scheduleUntimed(_ task: Task) {
        task.startTime = ""
        task.endTime = ""
        task.date = targetDate
        try? modelContext.save()
        onSchedule()
    }
}

/// Lightweight picker used from the "tap a time slot → create task" form to
/// pull a backlog task's details into the new-task fields. Selecting a row
/// hands the task back via `onSelect`; the caller is responsible for actually
/// removing it from the backlog once the new task is saved (see
/// `TasksCalendarView.createTaskFromSeparateFields`), so it isn't deleted
/// here in case the user backs out of the form without saving.
struct BacklogPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BacklogFolder.sortOrder) private var folders: [BacklogFolder]
    @Query(filter: #Predicate<Task> { $0.date == nil }, sort: \Task.title) private var backlogTasks: [Task]
    let onSelect: (Task) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if backlogTasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No backlog tasks yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(backlogTasks) { task in
                            Button {
                                onSelect(task)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .foregroundStyle(.primary)
                                    if let folder = task.backlogFolder {
                                        Text(FolderTree.path(folder, in: folders))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick from Backlog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
