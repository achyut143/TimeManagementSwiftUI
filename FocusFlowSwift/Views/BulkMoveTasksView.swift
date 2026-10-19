import SwiftUI

/// Lets the user multi-select timed tasks for a day and shift the whole
/// selection together to a new start time — the earliest-starting selected
/// task lands exactly on the chosen time, and every other selected task
/// keeps its original spacing relative to it (not packed back-to-back).
/// e.g. Task A 2:30 PM (30m), Task B 4:30 PM (30m) — selecting both and
/// moving to 4:30 PM shifts everything by the same +2h delta: A -> 4:30 PM,
/// B -> 6:30 PM.
///
/// This view only handles selection + the target time; the actual mutation
/// (and its notification scheduling) is delegated back to the caller via
/// `onMove`, so TasksCalendarView stays the single place that knows how to
/// reschedule a task.
struct BulkMoveTasksView: View {
    let selectedDate: Date
    let tasks: [Task]
    @Binding var isPresented: Bool
    let onMove: (_ selectedTaskIDs: [UUID], _ targetTime: Date) -> Void

    @State private var selectedIDs: Set<UUID> = []
    @State private var targetTime: Date = roundToNearestFiveMinutes(Date())

    private var sortedTimedTasks: [Task] {
        tasks
            .filter { !$0.startTime.isEmpty && !$0.endTime.isEmpty }
            .sorted { timeToMinutes($0.startTime) < timeToMinutes($1.startTime) }
    }

    private var untimedCount: Int {
        tasks.count - sortedTimedTasks.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Move to", selection: $targetTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .onChange(of: targetTime) { _, newValue in
                            targetTime = roundToNearestFiveMinutes(newValue)
                        }
                } footer: {
                    if !selectedIDs.isEmpty, let earliest = earliestSelectedTask {
                        Text("\(earliest.title) moves to \(targetTime.formatted(date: .omitted, time: .shortened)); everything else you've selected shifts by the same amount, keeping its spacing from \"\(earliest.title)\".")
                    }
                }

                Section {
                    if sortedTimedTasks.isEmpty {
                        Text("No timed tasks on \(selectedDate.formatted(date: .abbreviated, time: .omitted)).")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedTimedTasks) { task in
                            taskRow(task)
                        }
                    }
                } header: {
                    HStack {
                        Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        if !sortedTimedTasks.isEmpty {
                            Button(selectedIDs.count == sortedTimedTasks.count ? "Deselect All" : "Select All") {
                                if selectedIDs.count == sortedTimedTasks.count {
                                    selectedIDs.removeAll()
                                } else {
                                    selectedIDs = Set(sortedTimedTasks.map(\.id))
                                }
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                } footer: {
                    if untimedCount > 0 {
                        Text("\(untimedCount) untimed task\(untimedCount == 1 ? "" : "s") not shown — untimed tasks have no start time to shift.")
                    }
                }
            }
            .navigationTitle("Move Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        onMove(Array(selectedIDs), targetTime)
                        isPresented = false
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private var earliestSelectedTask: Task? {
        sortedTimedTasks.first { selectedIDs.contains($0.id) }
    }

    private func taskRow(_ task: Task) -> some View {
        let isSelected = selectedIDs.contains(task.id)
        return Button {
            if isSelected {
                selectedIDs.remove(task.id)
            } else {
                selectedIDs.insert(task.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("\(formatTimeToAMPM(task.startTime)) – \(formatTimeToAMPM(task.endTime)) (\(durationLabel(task)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func durationLabel(_ task: Task) -> String {
        let start = timeToMinutes(task.startTime)
        let end = timeToMinutes(task.endTime)
        let duration = end > start ? end - start : (24 * 60 - start) + end
        return "\(duration)m"
    }

    private func timeToMinutes(_ timeStr: String) -> Int {
        let clean = timeStr.trimmingCharacters(in: .whitespaces)
        let parts = clean.components(separatedBy: ":")
        guard parts.count >= 2,
              let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return 0 }
        return h * 60 + m
    }
}
