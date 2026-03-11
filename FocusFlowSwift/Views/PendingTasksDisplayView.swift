import SwiftUI
import SwiftData

struct PendingTasksDisplayView: View {
    let selectedDate: Date
    @Environment(\.modelContext) private var modelContext

    @AppStorage("display.tasksVisible") private var isVisible: Bool = true
    @AppStorage("display.tasksInterval") private var intervalSeconds: Int = 10

    @State private var pendingTasks: [Task] = []
    @State private var currentIndex: Int = 0
    @State private var showTask: Bool = true
    @State private var cycleTimer: Timer?

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 0) {
                if pendingTasks.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("No pending tasks for today")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                } else {
                    let task = pendingTasks[currentIndex]
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Pending · \(currentIndex + 1) of \(pendingTasks.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        if showTask {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)

                                if !task.startTime.isEmpty && !task.endTime.isEmpty {
                                    Text("\(task.startTime) – \(task.endTime)")
                                        .font(.caption2)
                                        .foregroundColor(.orange.opacity(0.8))
                                }
                            }
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                            )
                            .id("task-\(currentIndex)")
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .onAppear {
                loadPendingTasks()
                startCycling()
            }
            .onDisappear {
                stopCycling()
            }
            .onChange(of: selectedDate) { _, _ in
                loadPendingTasks()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TaskUpdated"))) { _ in
                loadPendingTasks()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TaskCreated"))) { _ in
                loadPendingTasks()
            }
        }
    }

    private func loadPendingTasks() {
        let all = (try? modelContext.fetch(FetchDescriptor<Task>(sortBy: [SortDescriptor(\.startTime)]))) ?? []
        pendingTasks = all.filter { task in
            guard let date = task.date else { return false }
            return Calendar.current.isDate(date, inSameDayAs: selectedDate)
                && !task.completed
                && !task.notCompleted
        }
        currentIndex = 0
    }

    private func startCycling() {
        guard cycleTimer == nil else { return }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalSeconds), repeats: true) { _ in
            advanceTask()
        }
    }

    private func stopCycling() {
        cycleTimer?.invalidate()
        cycleTimer = nil
    }

    private func advanceTask() {
        guard pendingTasks.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.4)) { showTask = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            currentIndex = (currentIndex + 1) % pendingTasks.count
            withAnimation(.easeInOut(duration: 0.4)) { showTask = true }
        }
    }
}
