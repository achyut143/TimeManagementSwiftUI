import SwiftUI
import SwiftData

// Shared sheet for logging time either against a ProjectActivity or directly on a Project.
// Also doubles as the edit sheet for an existing ProjectTimeEntry (init(entry:)) —
// updates it in place on save instead of inserting a new one.
struct AddTimeEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var activity: ProjectActivity?
    var project: Project?
    var existingEntry: ProjectTimeEntry?
    // Fires after a successful save (not on cancel) — e.g. so a caller can
    // reset a ProjectTimer once its session has actually been logged.
    var onLogged: (() -> Void)?

    @State private var durationText: String = ""
    @State private var date: Date
    @State private var note: String = ""
    @State private var showInvalidDuration = false

    private let fixedDate: Bool

    init(activity: ProjectActivity) {
        self.activity = activity
        self.project = nil
        self.existingEntry = nil
        self.fixedDate = true
        _date = State(initialValue: activity.date)
    }

    init(project: Project) {
        self.activity = nil
        self.project = project
        self.existingEntry = nil
        self.fixedDate = false
        _date = State(initialValue: Date())
    }

    // Used to log a just-stopped project timer session: duration comes
    // pre-filled from the elapsed time (still editable) and `onLogged` lets
    // the caller reset the timer once the entry is actually saved.
    init(project: Project, prefillMinutes: Double, onLogged: (() -> Void)? = nil) {
        self.activity = nil
        self.project = project
        self.existingEntry = nil
        self.fixedDate = false
        self.onLogged = onLogged
        _date = State(initialValue: Date())
        _durationText = State(initialValue: DurationInput.string(from: max(prefillMinutes, 1)))
    }

    init(entry: ProjectTimeEntry) {
        self.activity = entry.activity
        self.project = entry.project
        self.existingEntry = entry
        self.fixedDate = entry.activity != nil
        _durationText = State(initialValue: DurationInput.string(from: entry.durationMinutes))
        _date = State(initialValue: entry.date)
        _note = State(initialValue: entry.note)
    }

    private var canSave: Bool {
        DurationInput.minutes(from: durationText) != nil
    }

    private var navTitle: String {
        if existingEntry != nil { return "Edit Time Entry" }
        return activity != nil ? "Log Time to \(activity!.name)" : "Log Project Time"
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
            .navigationTitle(navTitle)
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
        if let existingEntry {
            existingEntry.durationMinutes = minutes
            existingEntry.note = note
            if !fixedDate {
                existingEntry.date = Calendar.current.startOfDay(for: date)
            }
        } else {
            let entry: ProjectTimeEntry
            if let activity {
                entry = ProjectTimeEntry(activity: activity, durationMinutes: minutes, date: activity.date, note: note)
            } else if let project {
                entry = ProjectTimeEntry(project: project, durationMinutes: minutes, date: date, note: note)
            } else {
                return
            }
            modelContext.insert(entry)
        }
        try? modelContext.save()
        onLogged?()
        dismiss()
    }
}
