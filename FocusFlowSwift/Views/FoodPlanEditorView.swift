import SwiftUI
import SwiftData

/// Plan what to eat at each break for one day. Starts from the break
/// template; the day can add or remove its own breaks. Saved on Save.
struct FoodPlanEditorView: View {
    let date: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [FoodEntry]
    @Query private var breaks: [FoodBreak]
    @AppStorage(FoodSettings.dailyCaloriesKey) private var dailyCalories = 2000

    @State private var rows: [Row] = []
    @State private var loaded = false
    @State private var estimating = false
    @State private var error: String?

    struct Row: Identifiable {
        let id = UUID()
        var existing: FoodEntry?
        var breakID: UUID?
        var name: String
        var icon: String
        var time: Date
        var food: String
        var calories: String
        var cost: String
    }

    init(date: Date) {
        self.date = date.startOfDay
    }

    private var isLate: Bool { date <= Date().startOfDay }
    private var totalCalories: Int { rows.compactMap { Int($0.calories.trimmed) }.reduce(0, +) }
    private var totalCost: Double { rows.compactMap { Double($0.cost.trimmed.replacingOccurrences(of: ",", with: ".")) }.reduce(0, +) }

    var body: some View {
        Form {
            if isLate {
                Section {
                    Label("Planning on the day itself. Food planned now counts as a late plan.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            ForEach($rows) { $row in
                Section {
                    TextField("What will you eat?", text: $row.food, axis: .vertical)
                    HStack {
                        TextField("kcal", text: $row.calories).keyboardType(.numberPad)
                        Divider()
                        TextField("Cost", text: $row.cost).keyboardType(.decimalPad)
                    }
                    DatePicker("Time", selection: $row.time, displayedComponents: .hourAndMinute)
                } header: {
                    HStack {
                        Label(row.name, systemImage: row.icon)
                        Spacer()
                        Button(role: .destructive) {
                            rows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .disabled(row.existing.map { $0.status != .pending } ?? false)
                    }
                }
            }

            Section {
                Menu {
                    ForEach(FoodBreak.icons.prefix(6), id: \.self) { icon in
                        Button { addBreak(icon: icon) } label: { Label(name(for: icon), systemImage: icon) }
                    }
                } label: {
                    Label("Add a break for this day", systemImage: "plus.circle")
                }
                Menu {
                    Button("Yesterday's plan") { copy(from: Calendar.current.date(byAdding: .day, value: -1, to: date)!) }
                    Button("Same day last week") { copy(from: Calendar.current.date(byAdding: .day, value: -7, to: date)!) }
                } label: {
                    Label("Copy food from…", systemImage: "doc.on.doc")
                }
                Button {
                    estimateAll()
                } label: {
                    HStack {
                        Label("Estimate missing calories", systemImage: "sparkles")
                        if estimating { Spacer(); ProgressView() }
                    }
                }
                .disabled(estimating || !rows.contains { !$0.food.trimmed.isEmpty && $0.calories.trimmed.isEmpty })
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }

            Section {
                LabeledContent("Calories", value: "\(totalCalories) / \(dailyCalories)")
                    .foregroundStyle(totalCalories > dailyCalories ? .red : .primary)
                LabeledContent("Cost", value: FoodSettings.money(totalCost))
            } header: {
                Text("Total")
            }
        }
        .navigationTitle("Plan " + date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear(perform: load)
    }

    private func name(for icon: String) -> String {
        switch icon {
        case "cup.and.saucer.fill", "mug.fill": return "Coffee / tea"
        case "carrot.fill", "leaf.fill": return "Snack"
        case "takeoutbag.and.cup.and.straw.fill": return "Takeout"
        default: return "Meal"
        }
    }

    // MARK: Load / save

    private func load() {
        guard !loaded else { return }
        loaded = true
        let saved = FoodRules.entries(on: date, entries).filter { $0.kind == .planned }
        if !saved.isEmpty {
            rows = saved.map {
                Row(existing: $0, breakID: $0.breakID, name: $0.breakName, icon: $0.icon, time: $0.time, food: $0.food,
                    calories: $0.calories.map { String(Int($0)) } ?? "", cost: $0.cost.map { format($0) } ?? "")
            }
        } else {
            rows = FoodRules.templateBreaks(for: date, breaks).map {
                Row(breakID: $0.id, name: $0.name, icon: $0.icon, time: $0.time(on: date), food: "", calories: "", cost: "")
            }
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private func addBreak(icon: String) {
        let last = rows.map(\.time).max() ?? Calendar.current.date(byAdding: .hour, value: 12, to: date)!
        let time = min(last.addingTimeInterval(2 * 3600), Calendar.current.date(byAdding: .minute, value: 23 * 60 + 30, to: date)!)
        rows.append(Row(name: name(for: icon), icon: icon, time: time, food: "", calories: "", cost: ""))
    }

    private func copy(from source: Date) {
        let old = FoodRules.entries(on: source, entries).filter { $0.kind == .planned && $0.hasPlan }
        guard !old.isEmpty else { error = "Nothing was planned that day."; return }
        error = nil
        for i in rows.indices {
            // Match by break name first, then by position.
            let match = old.first { $0.breakName == rows[i].name && $0.breakID == rows[i].breakID }
                ?? old.first { $0.breakName == rows[i].name }
                ?? (i < old.count ? old[i] : nil)
            guard let match else { continue }
            rows[i].food = match.food
            rows[i].calories = match.calories.map { String(Int($0)) } ?? ""
            rows[i].cost = match.cost.map { format($0) } ?? ""
        }
    }

    private func estimateAll() {
        let targets = rows.indices.filter { !rows[$0].food.trimmed.isEmpty && rows[$0].calories.trimmed.isEmpty }
        let foods = targets.map { rows[$0].food.trimmed }
        estimating = true
        error = nil
        _Concurrency.Task {
            defer { estimating = false }
            do {
                let values = try await FoodAIService().estimateCalories(foods)
                for (index, value) in zip(targets, values) where index < rows.count {
                    rows[index].calories = String(Int(value))
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        let now = Date()
        let keptIDs = Set(rows.compactMap { $0.existing?.id })
        for entry in FoodRules.entries(on: date, entries) where entry.kind == .planned && !keptIDs.contains(entry.id) {
            modelContext.delete(entry)
        }
        for row in rows {
            let food = row.food.trimmed
            let kcal = Double(row.calories.trimmed)
            let cost = Double(row.cost.trimmed.replacingOccurrences(of: ",", with: "."))
            let time = place(row.time)
            let entry: FoodEntry
            if let existing = row.existing {
                entry = existing
                if existing.food != food { existing.plannedAt = food.isEmpty ? nil : now }
                existing.food = food
            } else {
                entry = FoodEntry(day: date, time: time, kind: .planned, breakID: row.breakID,
                                  breakName: row.name, icon: row.icon, food: food)
                entry.plannedAt = food.isEmpty ? nil : now
                modelContext.insert(entry)
            }
            // A new time replaces any snooze.
            if entry.time != time { entry.snoozedUntil = nil }
            entry.time = time
            entry.calories = kcal
            entry.cost = cost
        }
        try? modelContext.save()
        FoodNotifications.reschedule(context: modelContext)
        dismiss()
    }

    private func place(_ time: Date) -> Date {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return Calendar.current.date(byAdding: .minute, value: (c.hour ?? 0) * 60 + (c.minute ?? 0), to: date)!
    }
}
