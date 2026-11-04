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
                ForEach(types.filter { !$0.isArchived }) { type in
                    typeRow(type)
                        .swipeActions(edge: .trailing) {
                            Button { setArchived(type, true) } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button { editingType = type } label: { Label("Edit", systemImage: "pencil") }
                            Button { setArchived(type, true) } label: { Label("Archive", systemImage: "archivebox") }
                        }
                }
                Button {
                    showNewType = true
                } label: {
                    Label("New impulse type", systemImage: "plus")
                }
            } header: {
                Text("Impulse types")
            } footer: {
                Text("Impulse time counts as planned only when it's scheduled at least the plan-before time ahead of its start. Swipe left on a type to archive it.")
            }

            let archived = types.filter(\.isArchived)
            if !archived.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showArchived) {
                        ForEach(archived) { type in
                            HStack {
                                typeRow(type)
                                Button("Restore") { setArchived(type, false) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                            .swipeActions(edge: .trailing) {
                                Button { setArchived(type, false) } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                        }
                    } label: {
                        Label("Archived (\(archived.count))", systemImage: "archivebox")
                    }
                } footer: {
                    Text("Archived types are hidden when adding or logging impulses, and their app checks are off. Past impulse time still counts in your metrics. Restore brings everything back.")
                }
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

    private func typeRow(_ type: ImpulseType) -> some View {
        Button {
            editingType = type
        } label: {
            HStack {
                Circle().fill(type.color).frame(width: 12, height: 12)
                Text(type.name).foregroundStyle(type.isArchived ? .secondary : .primary)
                Spacer()
                if !type.linkedApps.isEmpty {
                    Image(systemName: "apps.iphone").font(.caption).foregroundStyle(.secondary)
                }
                Text("plan \(PlannerRules.formatHours(type.planBeforeHours * 60)) h ahead")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setArchived(_ type: ImpulseType, _ archived: Bool) {
        withAnimation { type.isArchived = archived }
        try? modelContext.save()
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
        Date().atClock(minutes: minutes)
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
    @State private var linkedApps: [ImpulseLinkedApp] = []
    @State private var showOtherApp = false
    @State private var otherName = ""
    @State private var otherLink = ""
    @AppStorage(ImpulseGate.waitSecondsKey) private var waitSeconds = 10

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
                appsSection
                if type != nil {
                    Toggle("Archived", isOn: $archived)
                }
            }
            .alert("Add an app", isPresented: $showOtherApp) {
                TextField("App name", text: $otherName)
                TextField("Link (optional), e.g. myapp://", text: $otherLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") {
                    addApp(ImpulseLinkedApp(name: otherName.trimmed, urlScheme: otherLink.trimmed))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Use the same name when you pick it in the Shortcuts action. The link lets FocusFlow send you back to the app.")
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
                linkedApps = type.linkedApps
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
        target.linkedApps = linkedApps
        try? modelContext.save()
    }

    // MARK: Apps

    private var appsSection: some View {
        Section {
            ForEach($linkedApps) { $app in
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                    TextField("Link, e.g. instagram://", text: $app.urlScheme)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .onDelete { linkedApps.remove(atOffsets: $0) }

            Menu {
                ForEach(ImpulseLinkedApp.presets.filter { p in !linkedApps.contains { $0.id == p.id } }) { preset in
                    Button(preset.name) { addApp(preset) }
                }
                Divider()
                Button("Other app…") {
                    otherName = ""; otherLink = ""
                    showOtherApp = true
                }
            } label: {
                Label("Add app", systemImage: "plus.circle")
            }

            if !linkedApps.isEmpty {
                Stepper("Wait before choosing: \(waitSeconds) s", value: $waitSeconds, in: 0...60, step: 5)
                NavigationLink("How to set up app checks") {
                    ImpulseGateSetupGuide(apps: linkedApps)
                }
                if let type {
                    let week = ImpulseGate.events(typeID: type.id, since: GoalPeriod.week.start(for: Date()))
                    LabeledContent("This week",
                                   value: "\(week.count) checks · \(week.filter { $0.outcome == .resisted }.count) turned back")
                }
            }
        } header: {
            Text("Apps")
        } footer: {
            Text("Opening these apps outside planned \(name.trimmed.isEmpty ? "impulse" : name.trimmed) time asks you first, and using them anyway is logged as unplanned. Needs a one-time Shortcuts automation per app.")
        }
    }

    private func addApp(_ app: ImpulseLinkedApp) {
        guard !app.name.isEmpty, !linkedApps.contains(where: { $0.id == app.id }) else { return }
        linkedApps.append(app)
    }
}
