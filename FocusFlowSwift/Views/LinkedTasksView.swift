import SwiftUI
import SwiftData

struct LinkedTasksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [Task]
    
    let reward: Reward
    @State private var showingAddTask = false
    
    var linkedTasks: [TaskRewardLink] {
        reward.taskLinks.filter { $0.isActive }
    }
    
    // Get available tasks to link (excluding already linked ones)
    var availableTasks: [Task] {
        let linkedTaskIds = Set(linkedTasks.compactMap { $0.task?.persistentModelID })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // For repeat tasks, only show the most recent instance
        var tasksByTitle: [String: Task] = [:]
        
        for task in allTasks where !linkedTaskIds.contains(task.persistentModelID) {
            // Filter: only non-completed tasks
            guard !task.completed else { continue }
            
            // Filter: only tasks from today onwards
            if let taskDate = task.date {
                guard taskDate >= today else { continue }
            } else {
                // Skip tasks without a date
                continue
            }
            
            let title = task.title
            
            // If this is a repeat task
            if task.repeatAgain != nil {
                // Keep only the most recent instance (by date)
                if let existing = tasksByTitle[title] {
                    if let taskDate = task.date, let existingDate = existing.date {
                        if taskDate > existingDate {
                            tasksByTitle[title] = task
                        }
                    }
                } else {
                    tasksByTitle[title] = task
                }
            } else {
                // For non-repeat tasks, use a unique key
                let uniqueKey = "\(title)_\(task.persistentModelID)"
                tasksByTitle[uniqueKey] = task
            }
        }
        
        return Array(tasksByTitle.values).sorted { task1, task2 in
            // Sort by date (earliest first for future tasks), then by title
            if let date1 = task1.date, let date2 = task2.date {
                return date1 < date2
            }
            return task1.title < task2.title
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if linkedTasks.isEmpty {
                    ContentUnavailableView(
                        "No Linked Tasks",
                        systemImage: "link.badge.plus",
                        description: Text("Tasks linked to this reward will appear here")
                    )
                } else {
                    Section {
                        ForEach(linkedTasks) { link in
                            if let task = link.task {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(task.title)
                                                .font(.headline)
                                            
                                            HStack(spacing: 4) {
                                                if !task.startTime.isEmpty && !task.endTime.isEmpty {
                                                    Text("\(task.startTime) - \(task.endTime)")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                
                                                if let date = task.date {
                                                    Text("•")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    Text(date, style: .date)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        if task.completed {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.title3)
                                        }
                                    }
                                    
                                    HStack {
                                        Label {
                                            Text("Base Weight: \(String(format: "%.1f", task.weight)) pts")
                                                .font(.caption)
                                        } icon: {
                                            Image(systemName: "star.fill")
                                                .font(.caption2)
                                        }
                                        .foregroundStyle(.blue)
                                        
                                        if let timeSpent = task.timeSpent, task.allocatedTimeInMinutes > 0 {
                                            Text("•")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            
                                            Label {
                                                Text("Effective: \(String(format: "%.1f", task.effectiveWeight)) pts")
                                                    .font(.caption)
                                            } icon: {
                                                Image(systemName: "bolt.fill")
                                                    .font(.caption2)
                                            }
                                            .foregroundStyle(.green)
                                        }
                                    }
                                    
                                    if task.completed {
                                        Text("✅ Points added to reward")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                            .padding(.top, 2)
                                    } else {
                                        Text("⏳ Points will be added when completed")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .padding(.top, 2)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: deleteLinks)
                    } header: {
                        Text("\(linkedTasks.count) Linked Task\(linkedTasks.count == 1 ? "" : "s")")
                    }
                }
            }
            .navigationTitle("Linked Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingAddTask = true
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddTask) {
                AddTaskToRewardView(reward: reward, availableTasks: availableTasks)
            }
        }
    }
    
    private func deleteLinks(at offsets: IndexSet) {
        for index in offsets {
            let link = linkedTasks[index]
            link.isActive = false
        }
        try? modelContext.save()
    }
}

struct AddTaskToRewardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let reward: Reward
    let availableTasks: [Task]
    
    @State private var searchText = ""
    @State private var selectedTasks: Set<Task.ID> = []
    
    var filteredTasks: [Task] {
        if searchText.isEmpty {
            return availableTasks
        }
        return availableTasks.filter { task in
            task.title.localizedCaseInsensitiveContains(searchText) ||
            task.taskDescription.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search tasks...", text: $searchText)
                }
                .padding(8)
                .background(.quaternary)
                .cornerRadius(8)
                .padding()
                
                // Task list
                if filteredTasks.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Tasks Available" : "No Results",
                        systemImage: "checklist",
                        description: Text(searchText.isEmpty ? "All tasks are already linked to this reward" : "Try a different search term")
                    )
                } else {
                    List(filteredTasks) { task in
                        Button {
                            if selectedTasks.contains(task.id) {
                                selectedTasks.remove(task.id)
                            } else {
                                selectedTasks.insert(task.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    
                                    HStack(spacing: 4) {
                                        if !task.startTime.isEmpty && !task.endTime.isEmpty {
                                            Text("\(task.startTime) - \(task.endTime)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("Untimed")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        if let date = task.date {
                                            Text("•")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(date, style: .date)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        if task.repeatAgain != nil {
                                            Text("•")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Image(systemName: "repeat")
                                                .font(.caption)
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    
                                    HStack {
                                        Label {
                                            Text("\(String(format: "%.1f", task.weight)) pts")
                                                .font(.caption)
                                        } icon: {
                                            Image(systemName: "star.fill")
                                                .font(.caption2)
                                        }
                                        .foregroundStyle(.blue)
                                    }
                                }
                                
                                Spacer()
                                
                                if selectedTasks.contains(task.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.title3)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.gray)
                                        .font(.title3)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add (\(selectedTasks.count))") {
                        linkSelectedTasks()
                    }
                    .disabled(selectedTasks.isEmpty)
                }
            }
        }
    }
    
    private func linkSelectedTasks() {
        for taskId in selectedTasks {
            if let task = availableTasks.first(where: { $0.id == taskId }) {
                let link = TaskRewardLink(task: task, reward: reward)
                modelContext.insert(link)
            }
        }
        
        try? modelContext.save()
        dismiss()
    }
}
