import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: Task
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingAttachmentPreview = false
    @State private var selectedAttachment: TaskAttachment?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Task Header
                    taskHeaderSection
                    
                    // Task Details
                    taskDetailsSection
                    
                    // Notes Section
                    notesSection
                    
                    // Attachments Section
                    TaskAttachmentsView(task: task)
                    
                    // Subtasks Section
                    if let subtasks = task.subtasks, !subtasks.isEmpty {
                        subtasksSection(subtasks)
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        // TODO: Add edit functionality
                    }
                }
            }
        }
        .sheet(item: $selectedAttachment) { attachment in
            FilePreviewView(attachment: attachment)
        }
    }
    
    private var taskHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(task.title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text(task.priority)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(priorityColor(task.priority))
                    .clipShape(Capsule())
            }
            
            if !task.taskDescription.isEmpty {
                Text(task.taskDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                if task.completed {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
                
                if task.notCompleted {
                    Label("Not Completed", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var taskDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                DetailCard(title: "Date", value: task.date?.formatted(date: .abbreviated, time: .omitted) ?? "Not set")
                DetailCard(title: "Time", value: "\(task.startTime) - \(task.endTime)")
                DetailCard(title: "Weight", value: String(format: "%.1f", task.weight))
                DetailCard(title: "Time Spent", value: task.timeSpent != nil ? "\(Int(task.timeSpent!))m" : "Not set")
            }
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)
            
            if let notes = task.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Notes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(notes)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            if let persistentNotes = task.persistentNotes, !persistentNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Persistent Notes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(persistentNotes)
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            if (task.notes?.isEmpty ?? true) && (task.persistentNotes?.isEmpty ?? true) {
                Text("No notes added")
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
    
    private func subtasksSection(_ subtasks: [Subtask]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtasks (\(subtasks.count))")
                .font(.headline)
            
            ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                HStack {
                    Image(systemName: subtask.completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(subtask.completed ? .green : .gray)
                    
                    Text(subtask.name)
                        .strikethrough(subtask.completed)
                        .foregroundStyle(subtask.completed ? .secondary : .primary)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
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
}

struct DetailCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}