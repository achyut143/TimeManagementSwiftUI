import SwiftUI
import SwiftData

struct SubtaskCountButton: View {
    @Query private var allSubtasks: [Subtask]
    let task: Task
    @State private var showingSubtasks = false

    private var topLevelSubtasks: [Subtask] {
        allSubtasks.filter {
            $0.parentTask?.persistentModelID == task.persistentModelID &&
            $0.parentSubtask == nil
        }
    }

    private var subtaskCount: Int { topLevelSubtasks.count }
    private var completedCount: Int { topLevelSubtasks.filter { $0.completed }.count }

    var body: some View {
        if subtaskCount > 0 {
            Button {
                showingSubtasks = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: completedCount == subtaskCount ? "checkmark.circle.fill" : "list.bullet")
                        .font(.caption)
                    Text("\(completedCount)/\(subtaskCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(completedCount == subtaskCount ? .green : .indigo)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingSubtasks) {
                SubtasksView(parentTask: task)
            }
        } else {
            Button {
                showingSubtasks = true
            } label: {
                Image(systemName: "list.bullet.badge.plus")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingSubtasks) {
                SubtasksView(parentTask: task)
            }
        }
    }
}
