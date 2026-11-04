import SwiftUI
import SwiftData

/// Logs an impulse that already happened, without placing it on the calendar
/// by hand: pick the day, the type and how long it took.
///
/// It's saved as a normal impulse task (marked done and unplanned), so the
/// day plan, budget and every impulse metric count it like any other.
struct ImpulseQuickLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ImpulseType.sortOrder) private var types: [ImpulseType]

    @State private var day: Date
    @State private var typeID: UUID?
    @State private var title = ""
    @State private var hours = 0
    @State private var minutes = 30
    @State private var knowsStart = false
    @State private var start: Date
    @State private var note = ""

    init(date: Date = Date()) {
        _day = State(initialValue: date.startOfDay)
        // Default start: the duration ending about now on today, else the evening.
        let suggested = Calendar.current.isDateInToday(date)
            ? Date().addingTimeInterval(-30 * 60)
            : date.atClock(hour: 20)
        _start = State(initialValue: suggested)
    }

    private var activeTypes: [ImpulseType] { types.filter { !$0.isArchived } }
    private var totalMinutes: Int { hours * 60 + minutes }
    private var canSave: Bool { typeID != nil && totalMinutes > 0 }

    private static let quickPicks = [15, 30, 45, 60, 90, 120, 180]

    var body: some View {
        NavigationStack {
            Form {
                if activeTypes.isEmpty {
                    Section {
                        Text("Create an impulse type in Planner Settings first.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                        Picker("Impulse", selection: $typeID) {
                            ForEach(activeTypes) { type in
                                HStack {
                                    Circle().fill(type.color).frame(width: 10, height: 10)
                                    Text(type.name)
                                }
                                .tag(Optional(type.id))
                            }
                        }
                        TextField("What was it? (optional)", text: $title)
                    }

                    Section {
                        HStack(spacing: 0) {
                            Picker("Hours", selection: $hours) {
                                ForEach(0...12, id: \.self) { Text("\($0) h").tag($0) }
                            }
                            .pickerStyle(.wheel)
                            Picker("Minutes", selection: $minutes) {
                                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text("\($0) min").tag($0) }
                            }
                            .pickerStyle(.wheel)
                        }
                        .frame(height: 120)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Self.quickPicks, id: \.self) { m in
                                    Button(PlannerRules.formatMinutes(Double(m))) {
                                        hours = m / 60
                                        minutes = m % 60
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(totalMinutes == m ? .accentColor : .secondary)
                                    .controlSize(.small)
                                }
                            }
                        }
                    } header: {
                        Text("How long")
                    } footer: {
                        Text("Total: \(PlannerRules.formatMinutes(Double(totalMinutes)))")
                    }

                    Section {
                        Toggle("I know when it started", isOn: $knowsStart)
                        if knowsStart {
                            DatePicker("Started at", selection: $start, displayedComponents: .hourAndMinute)
                        }
                    } footer: {
                        Text(knowsStart
                             ? "It will show on the calendar at that time."
                             : "Without a time it's listed with the day's untimed tasks.")
                    }

                    Section("Note (optional)") {
                        TextField("What triggered it?", text: $note, axis: .vertical)
                    }

                    Section {
                        Label("Counted as unplanned time in the day plan, budget and metrics.",
                              systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Log unplanned impulse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if typeID == nil { typeID = activeTypes.first?.id }
            }
        }
    }

    private func save() {
        guard let typeID else { return }
        let typeName = activeTypes.first { $0.id == typeID }?.name ?? "Impulse"
        let name = title.trimmed.isEmpty ? typeName : title.trimmed

        let task: Task
        if knowsStart {
            let c = Calendar.current.dateComponents([.hour, .minute], from: start)
            let startDate = day.atClock(hour: c.hour ?? 0, minute: c.minute ?? 0)
            let endDate = startDate.addingTimeInterval(Double(totalMinutes) * 60)
            task = Task(title: name, startTime: DayPlanDetailView.hm(startDate),
                        endTime: DayPlanDetailView.hm(endDate), weight: 0, date: day)
        } else {
            task = Task(title: name, startTime: "", endTime: "", weight: 0, date: day,
                        elapsedTime: Double(totalMinutes))
        }
        task.completed = true
        task.timeSpent = Double(totalMinutes)
        if !note.trimmed.isEmpty { task.notes = note.trimmed }
        task.impulseTypeID = typeID
        // Logged after the fact, so it's unplanned no matter the time picked.
        task.impulseCheckedAt = Date()
        task.impulsePlannedMinutes = 0

        modelContext.insert(task)
        try? modelContext.save()
        NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
        dismiss()
    }
}

/// Small "Log" button used next to the Impulses headings.
struct ImpulseQuickLogButton: View {
    let date: Date
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Label("Log unplanned", systemImage: "plus.circle")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $showing) {
            ImpulseQuickLogView(date: date)
        }
    }
}
