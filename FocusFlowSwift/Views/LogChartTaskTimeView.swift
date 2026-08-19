import SwiftUI
import SwiftData

// Sheet shown when tapping a bar in TaskChartsView — lets the user log that
// task's time directly against one of their Projects.
struct LogChartTaskTimeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    let taskName: String
    /// Called with the minutes actually saved, after the ProjectTimeEntry is committed —
    /// lets the caller record that this task's time has been logged (e.g. the
    /// project-log marker written back into the daily notes for "By Task" bars).
    var onLogged: ((Double) -> Void)? = nil

    @State private var selectedProject: Project?
    @State private var durationText: String
    @State private var note: String
    @State private var date: Date
    @State private var showInvalidDuration = false

    init(taskName: String, defaultMinutes: Int, date: Date, defaultNote: String? = nil, onLogged: ((Double) -> Void)? = nil) {
        self.taskName = taskName
        self.onLogged = onLogged
        _durationText = State(initialValue: DurationInput.string(from: Double(defaultMinutes)))
        _note = State(initialValue: defaultNote ?? taskName)
        _date = State(initialValue: date)
    }

    private var canSave: Bool {
        selectedProject != nil && DurationInput.minutes(from: durationText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    if projects.isEmpty {
                        Text("No projects yet — create one first.")
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Project", selection: $selectedProject) {
                            Text("Select a project").tag(nil as Project?)
                            ForEach(projects) { project in
                                Text(project.name).tag(project as Project?)
                            }
                        }
                    }
                }
                Section("Duration") {
                    TextField("e.g. 1h 30m, 45m, 2.5h", text: $durationText)
                }
                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Log \"\(taskName)\"")
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
        guard let project = selectedProject else { return }
        guard let minutes = DurationInput.minutes(from: durationText) else {
            showInvalidDuration = true
            return
        }
        let entry = ProjectTimeEntry(project: project, durationMinutes: minutes, date: date, note: note)
        modelContext.insert(entry)
        try? modelContext.save()
        onLogged?(minutes)
        dismiss()
    }
}
