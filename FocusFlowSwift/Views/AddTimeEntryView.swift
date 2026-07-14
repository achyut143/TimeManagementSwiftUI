import SwiftUI
import SwiftData

// Shared sheet for logging time either against a ProjectActivity or directly on a Project.
struct AddTimeEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var activity: ProjectActivity?
    var project: Project?

    @State private var durationText: String = ""
    @State private var date: Date
    @State private var note: String = ""
    @State private var showInvalidDuration = false

    private let fixedDate: Bool

    init(activity: ProjectActivity) {
        self.activity = activity
        self.project = nil
        self.fixedDate = true
        _date = State(initialValue: activity.date)
    }

    init(project: Project) {
        self.activity = nil
        self.project = project
        self.fixedDate = false
        _date = State(initialValue: Date())
    }

    private var canSave: Bool {
        DurationInput.minutes(from: durationText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Duration") {
                    TextField("e.g. 1h 30m, 45m, 2.5h", text: $durationText)
                }
                if !fixedDate {
                    Section("Date") {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(activity != nil ? "Log Time to \(activity!.name)" : "Log Project Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .alert("Couldn't parse duration", isPresented: $showInvalidDuration) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try formats like \"1h 30m\", \"45m\", or \"2.5h\".")
            }
        }
    }

    private func save() {
        guard let minutes = DurationInput.minutes(from: durationText) else {
            showInvalidDuration = true
            return
        }
        let entry: ProjectTimeEntry
        if let activity {
            entry = ProjectTimeEntry(activity: activity, durationMinutes: minutes, date: activity.date, note: note)
        } else if let project {
            entry = ProjectTimeEntry(project: project, durationMinutes: minutes, date: date, note: note)
        } else {
            return
        }
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}
