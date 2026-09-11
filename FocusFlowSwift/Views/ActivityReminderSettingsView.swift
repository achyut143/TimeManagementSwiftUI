import SwiftUI
import SwiftData

// Configuration for ActivityReminderManager's shared schedule — one set of
// times that applies to the whole Activities list, not per-activity. At each
// time, the manager picks a random activity to nag about.
struct ActivityReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var activities: [VirtueActivity]

    @State private var isEnabled: Bool
    @State private var times: [ActivityReminderTime]
    @State private var newTime: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 9; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }()

    init() {
        let manager = ActivityReminderManager.shared
        _isEnabled = State(initialValue: manager.isEnabled)
        _times = State(initialValue: manager.times.sorted { $0.hour * 60 + $0.minute < $1.hour * 60 + $1.minute })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Remind Me", isOn: $isEnabled)
                } footer: {
                    Text("At each time below, you'll be reminded about a randomly picked activity from your list — speech + vibration, repeating until you acknowledge it from the Activities list, Daily Notes, or Focus View.")
                }

                Section {
                    ForEach(times.indices, id: \.self) { idx in
                        HStack {
                            DatePicker("", selection: timeBinding(for: idx), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Spacer()
                            Text(times[idx].timeString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button(action: { times.remove(at: idx) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    DatePicker("New reminder time", selection: $newTime, displayedComponents: .hourAndMinute)

                    Button(action: addTime) {
                        Label("Add Reminder Time", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Reminder Times")
                }
            }
            .navigationTitle("Activity Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func timeBinding(for idx: Int) -> Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = times[idx].hour
                c.minute = times[idx].minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { d in
                let cal = Calendar.current
                times[idx].hour = cal.component(.hour, from: d)
                times[idx].minute = cal.component(.minute, from: d)
            }
        )
    }

    private func addTime() {
        let cal = Calendar.current
        times.append(ActivityReminderTime(
            hour: cal.component(.hour, from: newTime),
            minute: cal.component(.minute, from: newTime)
        ))
    }

    private func save() {
        let manager = ActivityReminderManager.shared
        manager.isEnabled = isEnabled
        manager.times = times
        ActivityReminderManager.rescheduleAll(times: times, activities: activities, isEnabled: isEnabled)
        dismiss()
    }
}
