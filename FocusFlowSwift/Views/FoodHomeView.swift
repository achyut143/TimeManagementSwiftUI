import SwiftUI
import SwiftData

/// Today's food: the planned breaks with a countdown, unplanned food,
/// calories, money and cheats. Swipe between days with the arrows.
struct FoodHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [FoodEntry]
    @Query private var breaks: [FoodBreak]
    @Query(sort: \FoodCraving.date, order: .reverse) private var cravings: [FoodCraving]

    @AppStorage(FoodSettings.dailyCaloriesKey) private var dailyCalories = 2000
    @AppStorage(FoodSettings.weeklyBudgetKey) private var weeklyBudget = 0.0
    @AppStorage(FoodSettings.weeklyCheatsKey) private var weeklyCheats = 2
    @AppStorage(FoodUrge.startedAtKey) private var urgeStarted = 0.0
    @AppStorage(FoodSettings.showPillKey) private var showPill = true

    @State private var day = Date().startOfDay
    @State private var planDay: PlanTarget?
    @State private var logMode: FoodLogSheet.Mode?
    @State private var actionSlot: FoodSlot?
    @State private var showCravingStart = false
    @State private var snoozeSlot: FoodSlot?
    @AppStorage(FoodSettings.lastSnoozeKey) private var lastSnooze = 20

    struct PlanTarget: Identifiable { let date: Date; var id: Date { date } }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var dayEntries: [FoodEntry] { FoodRules.entries(on: day, entries) }
    private var slots: [FoodSlot] { FoodRules.slots(on: day, entries: entries, breaks: breaks) }
    private var unplanned: [FoodEntry] { dayEntries.filter(\.isUnplanned) }
    private var weekEntries: [FoodEntry] {
        let start = FoodRules.weekStart(day)
        return FoodRules.entries(entries, from: start, to: GoalPeriod.week.next(after: start))
    }

    var body: some View {
        List {
            dateBar
            summarySection
            if isToday { cravingSection }
            planBanner
            scheduleSection
            Section {
                HStack(spacing: 12) {
                    Button { logMode = .unplanned(day: day, trigger: "") } label: {
                        Label("Unplanned food", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    if isToday {
                        Button { showCravingStart = true } label: {
                            Label("I'm craving", systemImage: "hourglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .disabled(urgeStarted > 0)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button { planDay = PlanTarget(date: day) } label: { Label("Plan this day", systemImage: "square.and.pencil") }
                    Button { planDay = PlanTarget(date: tomorrow) } label: { Label("Plan tomorrow", systemImage: "calendar.badge.plus") }
                    if !isToday { Button { day = Date().startOfDay } label: { Label("Go to today", systemImage: "calendar") } }
                    Toggle(isOn: $showPill) { Label("On-screen timer", systemImage: "timer") }
                    NavigationLink { FoodMetricsView() } label: { Label("Metrics", systemImage: "chart.bar.xaxis") }
                    NavigationLink { FoodSettingsView() } label: { Label("Breaks & budgets", systemImage: "gearshape") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $planDay) { target in
            NavigationStack { FoodPlanEditorView(date: target.date) }
        }
        .sheet(item: $logMode) { mode in
            NavigationStack { FoodLogSheet(mode: mode) }
        }
        .sheet(item: $snoozeSlot) { slot in
            NavigationStack {
                RoutineSnoozeSheet(stepName: slot.name, from: max(slot.time, Date()), initial: lastSnooze) { minutes in
                    lastSnooze = minutes
                    snooze(slot, minutes)
                    snoozeSlot = nil
                } onCancel: { snoozeSlot = nil }
            }
        }
        .confirmationDialog(actionSlot.map { "\($0.name) · \($0.time.formatted(date: .omitted, time: .shortened))" } ?? "",
                            isPresented: Binding(get: { actionSlot != nil }, set: { if !$0 { actionSlot = nil } }),
                            titleVisibility: .visible, presenting: actionSlot) { slot in
            if !slot.food.isEmpty { Button("Ate it") { mark(slot, .eaten) } }
            Button("Ate something else…") { swap(slot) }
            Button("Skipped") { mark(slot, .skipped) }
            if slot.status == .pending && isToday {
                Button("Snooze 10 min") { snooze(slot, 10) }
                Button("Snooze \(lastSnooze) min") { snooze(slot, lastSnooze) }
                Button("Snooze for…") { snoozeSlot = slot }
            }
            if slot.status != .pending { Button("Not eaten yet") { mark(slot, .pending) } }
            Button("Edit plan") { planDay = PlanTarget(date: day) }
        } message: { slot in
            Text(slot.food.isEmpty ? "Nothing planned" : slot.food)
        }
        .confirmationDialog("What's driving the craving?", isPresented: $showCravingStart, titleVisibility: .visible) {
            ForEach(FoodSettings.triggers, id: \.self) { t in
                Button(t) { FoodUrge.start(trigger: t) }
            }
            Button("Not sure") { FoodUrge.start() }
        } message: {
            Text("Wait \(FoodSettings.urgeMinutes) minutes. Most cravings fade by then.")
        }
    }

    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: Date().startOfDay)! }

    /// The day shown, with arrows to move between days. Kept out of the
    /// navigation bar so the date always fits.
    private var dateBar: some View {
        Section {
            HStack {
                Button { shiftDay(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(relativeDay).font(.headline)
                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onTapGesture { day = Date().startOfDay }
                Spacer()
                Button { shiftDay(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var relativeDay: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated))
    }

    private func shiftDay(_ by: Int) {
        day = Calendar.current.date(byAdding: .day, value: by, to: day)!
    }

    // MARK: Summary

    private var summarySection: some View {
        let eatenCalories = dayEntries.reduce(0) { $0 + $1.eatenCalories }
        let plannedCalories = slots.compactMap { $0.entry?.calories }.reduce(0, +)
        let spentToday = dayEntries.reduce(0) { $0 + $1.eatenCost }
        let spentWeek = weekEntries.reduce(0) { $0 + $1.eatenCost }
        let cheatsToday = FoodRules.cheats(dayEntries).count
        let cheatsWeek = FoodRules.cheats(weekEntries).count
        let streak = FoodRules.cleanStreak(entries: entries, breaks: breaks)

        return Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Calories").font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(eatenCalories)) / \(dailyCalories)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(eatenCalories > Double(dailyCalories) ? .red : .primary)
                }
                ProgressView(value: min(eatenCalories, Double(dailyCalories)), total: Double(max(dailyCalories, 1)))
                    .tint(eatenCalories > Double(dailyCalories) ? .red : .green)
                if plannedCalories > 0 {
                    Text("Planned: \(Int(plannedCalories)) kcal")
                        .font(.caption)
                        .foregroundStyle(plannedCalories > Double(dailyCalories) ? .orange : .secondary)
                }
            }
            HStack(spacing: 0) {
                stat("\(cheatsToday)", "Cheats today", cheatsToday > 0 ? .red : .green)
                stat("\(cheatsWeek)/\(weeklyCheats)", "Cheats this week", cheatsWeek > weeklyCheats ? .red : .primary)
                stat("\(streak)🔥", "Clean days", .primary)
            }
            HStack(spacing: 0) {
                stat(FoodSettings.money(spentToday), "Spent today", .primary)
                stat(weeklyBudget > 0 ? "\(FoodSettings.money(spentWeek)) / \(FoodSettings.money(weeklyBudget))" : FoodSettings.money(spentWeek),
                     "This week", weeklyBudget > 0 && spentWeek > weeklyBudget ? .red : .primary)
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Craving

    @ViewBuilder
    private var cravingSection: some View {
        if urgeStarted > 0 {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    switch FoodUrge.state(at: context.date) {
                    case .waiting(let left):
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Waiting out a craving", systemImage: "hourglass").font(.headline).foregroundStyle(.orange)
                            Text(String(format: "%d:%02d left", left / 60, left % 60))
                                .font(.title.monospacedDigit().bold())
                            if let next = FoodRules.nextSlot(after: context.date, entries: entries, breaks: breaks) {
                                Text("Next food: \(next.name) at \(next.time.formatted(date: .omitted, time: .shortened))\(next.food.isEmpty ? "" : " · \(next.food)")")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text("Drink water, take a short walk, or do something with your hands.")
                                .font(.caption).foregroundStyle(.secondary)
                            cravingButtons(resistLabel: "I'm over it")
                        }
                    case .done:
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Time's up. Do you still want it?", systemImage: "questionmark.circle").font(.headline)
                            cravingButtons(resistLabel: "No, resisted 💪")
                        }
                    case .idle:
                        EmptyView()
                    }
                }
            }
        }
    }

    private func cravingButtons(resistLabel: String) -> some View {
        HStack {
            Button(resistLabel) { FoodUrge.finish(resisted: true, context: modelContext) }
                .buttonStyle(.borderedProminent).tint(.green)
            Button("I ate something") {
                let trigger = FoodUrge.trigger
                FoodUrge.finish(resisted: false, context: modelContext)
                logMode = .unplanned(day: Date().startOfDay, trigger: trigger)
            }
            .buttonStyle(.bordered).tint(.red)
            Spacer()
            Button("Cancel") { FoodUrge.cancel() }.font(.caption).buttonStyle(.borderless)
        }
    }

    // MARK: Plan banner

    @ViewBuilder
    private var planBanner: some View {
        let target = isToday ? tomorrow : day
        if day >= Date().startOfDay && !FoodRules.isDayPlanned(target, entries: entries)
            && (!isToday || Calendar.current.component(.hour, from: Date()) >= 12) {
            Section {
                Button { planDay = PlanTarget(date: target) } label: {
                    Label(isToday ? "Plan tomorrow's food" : "Plan this day's food", systemImage: "calendar.badge.plus")
                        .font(.headline)
                }
            } footer: {
                Text("Food planned before the day starts counts as planned.")
            }
        }
    }

    // MARK: Schedule

    private var scheduleSection: some View {
        Section {
            if slots.isEmpty && unplanned.isEmpty {
                Text("No food breaks. Add some in Breaks & budgets.").foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let next = isToday ? FoodRules.nextSlot(after: context.date, entries: entries, breaks: breaks) : nil
                VStack(spacing: 0) {
                    ForEach(timeline(), id: \.id) { item in
                        Group {
                            switch item {
                            case .slot(let slot):
                                slotRow(slot, isNext: next?.id == slot.id, now: context.date)
                                    .contentShape(Rectangle())
                                    .onTapGesture { actionSlot = slot }
                            case .unplanned(let entry):
                                unplannedRow(entry)
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        } header: {
            Text("Breaks")
        } footer: {
            Text("Tap a break to mark it as eaten, swapped or skipped.")
        }
    }

    private enum Item {
        case slot(FoodSlot), unplanned(FoodEntry)
        var id: UUID { switch self { case .slot(let s): return s.id; case .unplanned(let e): return e.id } }
        var time: Date { switch self { case .slot(let s): return s.time; case .unplanned(let e): return e.time } }
    }

    private func timeline() -> [Item] {
        (slots.map(Item.slot) + unplanned.map(Item.unplanned)).sorted { $0.time < $1.time }
    }

    private func slotRow(_ slot: FoodSlot, isNext: Bool, now: Date) -> some View {
        let entry = slot.entry
        let cheat = entry.flatMap(FoodRules.cheatReason)
        return HStack(alignment: .top, spacing: 10) {
            Text(slot.time.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Image(systemName: slot.icon).foregroundStyle(.teal).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.name).font(.subheadline.bold())
                Text(slot.food.isEmpty ? "Not planned" : slot.food)
                    .font(.subheadline)
                    .foregroundStyle(slot.food.isEmpty ? .orange : .primary)
                    .strikethrough(slot.status == .swapped || slot.status == .skipped)
                if let entry, entry.status == .swapped {
                    Text("Ate: \(entry.actualFood)").font(.caption).foregroundStyle(.red)
                }
                if slot.isSnoozed {
                    Label("Snoozed from \(slot.plannedTime.formatted(date: .omitted, time: .shortened))", systemImage: "zzz")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let cheat { Text(cheat.rawValue).font(.caption2.bold()).foregroundStyle(.red) }
                if let entry, entry.hasPlan, !entry.plannedOnTime, cheat == nil {
                    Text("Planned on the day").font(.caption2).foregroundStyle(.orange)
                }
                if isNext {
                    let secs = Int(slot.time.timeIntervalSince(now))
                    Text("in \(Self.countdown(secs))")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                statusIcon(slot.status)
                if let kcal = slot.status == .swapped ? entry?.actualCalories : entry?.calories {
                    Text("\(Int(kcal)) kcal").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func unplannedRow(_ entry: FoodEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.time.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Unplanned").font(.subheadline.bold()).foregroundStyle(.red)
                Text(entry.food).font(.subheadline)
                if !entry.trigger.isEmpty { Text(entry.trigger).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Menu {
                    Button { logMode = .edit(entry) } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) {
                        modelContext.delete(entry)
                        try? modelContext.save()
                    } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
                if let kcal = entry.calories { Text("\(Int(kcal)) kcal").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: FoodEntryStatus) -> some View {
        switch status {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .eaten: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .swapped: Image(systemName: "arrow.triangle.swap").foregroundStyle(.red)
        case .skipped: Image(systemName: "minus.circle.fill").foregroundStyle(.gray)
        }
    }

    static func countdown(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Actions

    private func mark(_ slot: FoodSlot, _ status: FoodEntryStatus) {
        FoodRules.mark(slot, status, day: day, breaks: breaks, context: modelContext)
    }

    private func snooze(_ slot: FoodSlot, _ minutes: Int) {
        FoodRules.snooze(slot, minutes: minutes, day: day, breaks: breaks, context: modelContext)
    }

    private func swap(_ slot: FoodSlot) {
        let entry = slot.entry ?? FoodRules.materialize(day, breaks: breaks, context: modelContext)
            .first { $0.breakID == slot.id }
        if let entry { logMode = .swap(entry) }
    }
}

// MARK: - Log sheet

/// Log unplanned food, or what was eaten instead of the plan.
struct FoodLogSheet: View {
    enum Mode: Identifiable {
        case unplanned(day: Date, trigger: String)
        case swap(FoodEntry)
        case edit(FoodEntry)

        var id: String {
            switch self {
            case .unplanned(let d, _): return "u\(d.timeIntervalSince1970)"
            case .swap(let e): return "s\(e.id)"
            case .edit(let e): return "e\(e.id)"
            }
        }
    }

    let mode: Mode
    var onClose: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var food = ""
    @State private var calories = ""
    @State private var cost = ""
    @State private var time = Date()
    @State private var trigger = ""
    @State private var hunger = 3
    @State private var note = ""
    @State private var estimating = false
    @State private var error: String?
    @State private var loaded = false

    private var title: String {
        switch mode {
        case .unplanned: return "Unplanned food"
        case .swap(let e): return "Instead of \(e.breakName)"
        case .edit: return "Edit food"
        }
    }

    var body: some View {
        Form {
            if case .swap(let e) = mode, e.hasPlan {
                Section { Text("Planned: \(e.food)").foregroundStyle(.secondary) }
            }
            Section("What did you eat?") {
                TextField("e.g. Chips, small bag", text: $food, axis: .vertical)
                HStack {
                    TextField("Calories", text: $calories).keyboardType(.numberPad)
                    Button {
                        estimate()
                    } label: {
                        if estimating { ProgressView() } else { Label("Estimate", systemImage: "sparkles") }
                    }
                    .buttonStyle(.borderless)
                    .disabled(food.trimmed.isEmpty || estimating)
                }
                TextField("Cost", text: $cost).keyboardType(.decimalPad)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Section("Why?") {
                VocabFlowLayout(spacing: 6) {
                    ForEach(FoodSettings.triggers, id: \.self) { t in
                        Button {
                            trigger = trigger == t ? "" : t
                        } label: {
                            Text(t)
                                .font(.subheadline)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(trigger == t ? Color.orange : Color(.tertiarySystemFill)))
                                .foregroundStyle(trigger == t ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                Stepper("How hungry: \(hunger) / 5", value: $hunger, in: 1...5)
                TextField("Note (optional)", text: $note)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(food.trimmed.isEmpty)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .unplanned(let day, let t):
            trigger = t
            if !Calendar.current.isDateInToday(day) {
                time = day.atClock(hour: 12)
            }
        case .swap(let e):
            food = e.actualFood
            calories = e.actualCalories.map { String(Int($0)) } ?? ""
            cost = e.actualCost.map { String($0) } ?? ""
            time = Calendar.current.isDateInToday(e.day) ? Date() : e.time
            trigger = e.trigger
            hunger = e.hunger == 0 ? 3 : e.hunger
            note = e.note
        case .edit(let e):
            food = e.food
            calories = e.calories.map { String(Int($0)) } ?? ""
            cost = e.cost.map { String($0) } ?? ""
            time = e.time
            trigger = e.trigger
            hunger = e.hunger == 0 ? 3 : e.hunger
            note = e.note
        }
    }

    private func estimate() {
        estimating = true
        error = nil
        let text = food.trimmed
        _Concurrency.Task {
            defer { estimating = false }
            do {
                if let kcal = try await FoodAIService().estimateCalories([text]).first {
                    calories = String(Int(kcal))
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        let kcal = Double(calories.trimmed)
        let money = Double(cost.trimmed.replacingOccurrences(of: ",", with: "."))
        switch mode {
        case .unplanned(let day, _):
            let at = place(time, on: day)
            let entry = FoodEntry(day: day, time: at, kind: .unplanned, breakName: "Unplanned",
                                  icon: "exclamationmark.triangle.fill", food: food.trimmed)
            entry.status = .eaten
            entry.eatenAt = at
            apply(to: entry, kcal: kcal, money: money)
            modelContext.insert(entry)
        case .swap(let e):
            e.status = .swapped
            e.actualFood = food.trimmed
            e.actualCalories = kcal
            e.actualCost = money
            e.eatenAt = place(time, on: e.day)
            e.trigger = trigger
            e.hunger = hunger
            e.note = note.trimmed
        case .edit(let e):
            e.food = food.trimmed
            e.time = place(time, on: e.day)
            e.eatenAt = e.time
            apply(to: e, kcal: kcal, money: money)
        }
        try? modelContext.save()
        FoodNotifications.reschedule(context: modelContext)
        close()
    }

    private func apply(to e: FoodEntry, kcal: Double?, money: Double?) {
        e.calories = kcal
        e.cost = money
        e.trigger = trigger
        e.hunger = hunger
        e.note = note.trimmed
    }

    private func place(_ time: Date, on day: Date) -> Date {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return day.atClock(minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}
