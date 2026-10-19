import SwiftUI
import SwiftData

/// Impulse types, the shared monthly budget, and the versioned sleep schedule.
struct PlannerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ImpulseType.sortOrder) private var types: [ImpulseType]
    @Query(sort: \ImpulseBudgetVersion.effectiveFrom, order: .reverse) private var budgets: [ImpulseBudgetVersion]
    @Query(sort: \SleepScheduleVersion.effectiveFrom, order: .reverse) private var schedules: [SleepScheduleVersion]

    @State private var editingType: ImpulseType?
    @State private var showNewType = false
    @State private var budgetHours: Double = 0
    @State private var wake = Date()
    @State private var sleep = Date()
    @State private var window = 15
    @State private var showArchived = false

    private var currentBudget: Double { budgets.first?.monthlyHours ?? 0 }

    var body: some View {
        Form {
            Section {
                ForEach(types.filter { showArchived || !$0.isArchived }) { type in
                    Button {
                        editingType = type
                    } label: {
                        HStack {
                            Circle().fill(type.color).frame(width: 12, height: 12)
                            Text(type.name).foregroundStyle(type.isArchived ? .secondary : .primary)
                            Spacer()
                            Text("plan \(PlannerRules.formatHours(type.planBeforeHours * 60)) h ahead")
                                .font(.caption).foregroundStyle(.secondary)
                            if type.isArchived { Badge(text: "Archived", color: .secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showNewType = true
                } label: {
                    Label("New impulse type", systemImage: "plus")
                }
                if types.contains(where: \.isArchived) {
                    Toggle("Show archived", isOn: $showArchived)
                }
            } header: {
                Text("Impulse types")
            } footer: {
                Text("Impulse time counts as planned only when it's scheduled at least the plan-before time ahead of its start.")
            }

            Section {
                HStack {
                    Text("Hours per month")
                    Spacer()
                    TextField("0", value: $budgetHours, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                if budgetHours != currentBudget {
                    Button("Save budget") { saveBudget() }
                }
            } header: {
                Text("Monthly impulse budget")
            } footer: {
                Text("One budget for all impulse types combined. Resets on the 1st. A change applies from now on; past months keep their budget. Set 0 for no budget.")
            }

            Section {
                DatePicker("Wake up", selection: $wake, displayedComponents: .hourAndMinute)
                DatePicker("Go to sleep", selection: $sleep, displayedComponents: .hourAndMinute)
                Stepper("On-time window ±\(window) min", value: $window, in: 0...90, step: 5)
                if scheduleChanged {
                    Button(schedules.isEmpty ? "Save schedule" : "Save as new version from today") { saveSchedule() }
                }
            } header: {
                Text("Sleep schedule")
            } footer: {
                Text("Each change starts a new version, and every day is judged against the version active that day.")
            }

            if !schedules.isEmpty {
                Section("Schedule history") {
                    ForEach(schedules) { v in
                        HStack {
                            Text(v.label)
                            Spacer()
                            Text("since \(v.effectiveFrom.formatted(.dateTime.month(.abbreviated).day().year()))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                LabeledContent("Week starts", value: "Monday")
            }
        }
        .navigationTitle("Planner Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .sheet(item: $editingType) { type in
            ImpulseTypeEditor(type: type, nextSortOrder: types.count)
        }
        .sheet(isPresented: $showNewType) {
            ImpulseTypeEditor(type: nil, nextSortOrder: types.count)
        }
        .onAppear(perform: load)
    }

    private var scheduleChanged: Bool {
        guard let s = schedules.first else { return true }
        return s.wakeMinutes != minutes(of: wake) || s.sleepMinutes != minutes(of: sleep) || s.windowMinutes != window
    }

    private func load() {
        budgetHours = currentBudget
        let s = schedules.first
        wake = date(for: s?.wakeMinutes ?? 6 * 60 + 30)
        sleep = date(for: s?.sleepMinutes ?? 22 * 60 + 30)
        window = s?.windowMinutes ?? 15
    }

    private func saveBudget() {
        modelContext.insert(ImpulseBudgetVersion(monthlyHours: max(0, budgetHours)))
        try? modelContext.save()
    }

    private func saveSchedule() {
        let today = Date().startOfDay
        // Several edits on one day are one version, not many.
        if let same = schedules.first(where: { $0.effectiveFrom == today }) {
            same.wakeMinutes = minutes(of: wake)
            same.sleepMinutes = minutes(of: sleep)
            same.windowMinutes = window
        } else {
            modelContext.insert(SleepScheduleVersion(wakeMinutes: minutes(of: wake), sleepMinutes: minutes(of: sleep),
                                                     windowMinutes: window, effectiveFrom: today))
        }
        try? modelContext.save()
    }

    private func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func date(for minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: Date().startOfDay)!
    }
}

struct ImpulseTypeEditor: View {
    let type: ImpulseType?
    let nextSortOrder: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var colorHex = ImpulseType.palette[0]
    @State private var planBefore: Double = 12
    @State private var archived = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, e.g. Instagram", text: $name)
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(ImpulseType.palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color.primary, lineWidth: colorHex == hex ? 3 : 0))
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    HStack {
                        Text("Plan before (hours)")
                        Spacer()
                        TextField("12", value: $planBefore, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                } footer: {
                    Text("A change applies to impulse time scheduled from now on; tasks already checked keep their result.")
                }
                if type != nil {
                    Toggle("Archived", isOn: $archived)
                }
            }
            .navigationTitle(type == nil ? "New Impulse Type" : "Edit Impulse Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                        .disabled(name.trimmed.isEmpty)
                }
            }
            .onAppear {
                guard let type else { return }
                name = type.name
                colorHex = type.colorHex
                planBefore = type.planBeforeHours
                archived = type.isArchived
            }
        }
    }

    private func save() {
        let target = type ?? {
            let t = ImpulseType(name: "", colorHex: colorHex, planBeforeHours: 0, sortOrder: nextSortOrder)
            modelContext.insert(t)
            return t
        }()
        target.name = name.trimmed
        target.colorHex = colorHex
        target.planBeforeHours = max(0, planBefore)
        target.isArchived = archived
        try? modelContext.save()
    }
}
