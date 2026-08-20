import SwiftUI

// Configuration page for AwayTimeTracker — the daily window it measures
// backgrounded time within, and an on/off switch.
struct AwayTimeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tracker = AwayTimeTracker.shared

    @State private var isEnabled: Bool
    @State private var fromDate: Date
    @State private var toDate: Date

    init() {
        let t = AwayTimeTracker.shared
        _isEnabled = State(initialValue: t.isEnabled)
        _fromDate = State(initialValue: Self.date(fromMinute: t.windowFromMinute))
        _toDate = State(initialValue: Self.date(fromMinute: t.windowToMinute))
    }

    private static func date(fromMinute minute: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = minute / 60
        c.minute = minute % 60
        return Calendar.current.date(from: c) ?? Date()
    }

    private static func minute(from date: Date) -> Int {
        let cal = Calendar.current
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    private var windowIsValid: Bool {
        Self.minute(from: toDate) > Self.minute(from: fromDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Track Away Time", isOn: $isEnabled)
                } header: {
                    Text("Tracking")
                } footer: {
                    Text("While enabled, the app measures how long you're away from it (backgrounded) during the window below, tracked down to the second.")
                }

                Section {
                    DatePicker("From", selection: $fromDate, displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: $toDate, displayedComponents: .hourAndMinute)
                    if !windowIsValid {
                        Text("\"To\" must be after \"From\" — nothing will be tracked until this is fixed.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Window")
                } footer: {
                    Text("Only time spent away between these two times each day counts. Overnight windows (e.g. 10 PM–6 AM) aren't supported yet.")
                }

                Section("Today") {
                    HStack {
                        Text("Away so far")
                        Spacer()
                        Text(AwayTimeTracker.formatted(tracker.todaySeconds))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle("Away Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
        }
    }

    private func save() {
        tracker.isEnabled = isEnabled
        tracker.windowFromMinute = Self.minute(from: fromDate)
        tracker.windowToMinute = Self.minute(from: toDate)
    }
}
