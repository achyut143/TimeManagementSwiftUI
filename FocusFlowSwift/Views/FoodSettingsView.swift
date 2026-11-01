import SwiftUI
import SwiftData

/// Break template, budgets and cheat rules.
struct FoodSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodBreak.minutes) private var breaks: [FoodBreak]

    @AppStorage(FoodSettings.dailyCaloriesKey) private var dailyCalories = 2000
    @AppStorage(FoodSettings.weeklyBudgetKey) private var weeklyBudget = 0.0
    @AppStorage(FoodSettings.weeklyCheatsKey) private var weeklyCheats = 2
    @AppStorage(FoodSettings.cheatEarlyKey) private var cheatEarly = false
    @AppStorage(FoodSettings.earlyMinutesKey) private var earlyMinutes = 30
    @AppStorage(FoodSettings.cheatLatePlanKey) private var cheatLatePlan = false
    @AppStorage(FoodSettings.showPillKey) private var showPill = true
    @AppStorage(FoodSettings.notifyKey) private var notify = true
    @AppStorage(FoodSettings.planReminderKey) private var planReminder = 21 * 60
    @AppStorage(FoodSettings.urgeMinutesKey) private var urgeMinutes = 10
    @AppStorage(FoodSettings.acknowledgeKey) private var acknowledge = true

    @State private var editing: FoodBreak?
    @State private var adding = false

    var body: some View {
        Form {
            Section {
                ForEach(breaks) { b in
                    Button { editing = b } label: {
                        HStack {
                            Image(systemName: b.icon).foregroundStyle(.teal).frame(width: 24)
                            Text(b.name).foregroundStyle(.primary)
                            Spacer()
                            Text(PlannerRules.clock(b.minutes)).foregroundStyle(.secondary)
                            if b.weekdays.count < 7 {
                                Text(daysLabel(b.weekdays)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(breaks[i]) }
                    try? modelContext.save()
                }
                Button { adding = true } label: { Label("Add break", systemImage: "plus") }
            } header: {
                Text("Food breaks")
            } footer: {
                Text("New day plans start from these. Changing them doesn't change days you've already planned.")
            }

            Section("Targets") {
                Stepper("Calories per day: \(dailyCalories)", value: $dailyCalories, in: 800...5000, step: 50)
                HStack {
                    Text("Food money per week")
                    Spacer()
                    TextField("None", value: $weeklyBudget, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                Stepper("Cheats allowed per week: \(weeklyCheats)", value: $weeklyCheats, in: 0...21)
            }

            Section {
                Toggle("Eating a planned break early is a cheat", isOn: $cheatEarly)
                if cheatEarly {
                    Stepper("More than \(earlyMinutes) min early", value: $earlyMinutes, in: 10...180, step: 10)
                }
                Toggle("Food planned on the day is a cheat", isOn: $cheatLatePlan)
            } header: {
                Text("What counts as a cheat")
            } footer: {
                Text("Unplanned food and eating something other than the plan always count as cheats.")
            }

            Section("Reminders & timer") {
                Toggle("Show countdown on screen", isOn: $showPill)
                Toggle("Notify at each break", isOn: $notify)
                Toggle("Ask me to acknowledge each break", isOn: $acknowledge)
                DatePicker("Remind me to plan tomorrow at", selection: Binding(
                    get: { Date().atClock(minutes: planReminder) },
                    set: {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                        planReminder = (c.hour ?? 21) * 60 + (c.minute ?? 0)
                    }), displayedComponents: .hourAndMinute)
                Stepper("Craving wait: \(urgeMinutes) min", value: $urgeMinutes, in: 2...30)
            }
        }
        .navigationTitle("Breaks & budgets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { b in
            NavigationStack { FoodBreakEditor(existing: b) }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { FoodBreakEditor(existing: nil) }
        }
        .onDisappear { FoodNotifications.reschedule(context: modelContext) }
    }

    private func daysLabel(_ days: [Int]) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return days.sorted().map { symbols[$0 - 1] }.joined()
    }
}

struct FoodBreakEditor: View {
    let existing: FoodBreak?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var icon = "fork.knife"
    @State private var time = Date()
    @State private var weekdays: Set<Int> = Set(1...7)
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("Name (e.g. Lunch)", text: $name)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
            }
            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                    ForEach(FoodBreak.icons, id: \.self) { i in
                        Button { icon = i } label: {
                            Image(systemName: i)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 8).fill(icon == i ? Color.teal.opacity(0.25) : Color.clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section("Days") {
                HStack {
                    ForEach(1...7, id: \.self) { d in
                        let on = weekdays.contains(d)
                        Button {
                            if on { if weekdays.count > 1 { weekdays.remove(d) } } else { weekdays.insert(d) }
                        } label: {
                            Text(Calendar.current.veryShortWeekdaySymbols[d - 1])
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(Circle().fill(on ? Color.teal : Color(.tertiarySystemFill)))
                                .foregroundStyle(on ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? "New break" : "Edit break")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(name.trimmed.isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let b = existing {
                name = b.name
                icon = b.icon
                time = Date().atClock(minutes: b.minutes)
                weekdays = Set(b.weekdays)
            } else {
                time = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
            }
        }
    }

    private func save() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let minutes = (c.hour ?? 12) * 60 + (c.minute ?? 0)
        if let b = existing {
            b.name = name.trimmed
            b.icon = icon
            b.minutes = minutes
            b.weekdays = weekdays.sorted()
        } else {
            modelContext.insert(FoodBreak(name: name.trimmed, icon: icon, minutes: minutes, weekdays: weekdays.sorted()))
        }
        try? modelContext.save()
        dismiss()
    }
}
