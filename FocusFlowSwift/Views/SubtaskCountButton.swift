import SwiftUI
import SwiftData

struct SubtaskCountButton: View {
    let task: Task
    let allSubtasks: [Subtask]
    @State private var showingSubtasks = false
    
    private var subtaskCount: Int {
        let taskIdString = task.persistentModelID.hashValue.description
        return allSubtasks.filter { $0.parentTaskIdString == taskIdString && $0.parentSubtaskIdString == nil }.count
    }
    
    var body: some View {
        if subtaskCount > 0 {
            Button {
                showingSubtasks = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.caption)
                    Text("\(subtaskCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.indigo)
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
