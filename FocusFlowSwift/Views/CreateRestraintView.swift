import SwiftUI
import SwiftData

struct CreateRestraintView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var restraint: Restraint?

    @State private var name: String = ""
    @State private var everyDay: Bool = true
    @State private var selectedWeekdays: Set<Int> = []
    @State private var limitType: RestraintLimitType = .duration
    @State private var awardedMinutes: Int = 30
    @State private var quantityLimit: String = ""
    @State private var quantityUnit: String = ""
    @State private var releaseWindows: [RestraintTimeWindowInfo] = []
    @State private var newWindowTime: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 16; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var colorName: String = "blue"
    @State private var iconName: String = "hand.raised.fill"

    private let weekdayLabels: [(Int, String)] = [
        (1,"Sun"),(2,"Mon"),(3,"Tue"),(4,"Wed"),(5,"Thu"),(6,"Fri"),(7,"Sat")
    ]
    private let weekdayCols = Array(repeating: GridItem(.flexible()), count: 7)

    private let colorOptions: [(String, Color)] = [
        ("blue", .blue), ("indigo", .indigo), ("purple", .purple),
        ("pink", .pink), ("red", .red), ("orange", .orange),
        ("green", .green), ("teal", .teal), ("cyan", .cyan)
    ]
    private let colorCols = Array(repeating: GridItem(.flexible()), count: 5)

    private let iconOptions: [String] = [
        "hand.raised.fill", "tv.fill", "iphone", "fork.knife", "gamecontroller.fill", "book.fill",
        "cup.and.saucer.fill", "car.fill", "moon.fill", "flame.fill", "heart.fill", "dumbbell.fill",
        "music.note", "cart.fill", "creditcard.fill", "wineglass.fill", "popcorn.fill", "figure.walk",
        "star.fill", "bolt.fill", "leaf.fill", "bed.double.fill", "desktopcomputer", "pills.fill"
    ]
    private let iconCols = Array(repeating: GridItem(.flexible()), count: 6)

    private var selectedColor: Color {
        colorOptions.first { $0.0 == colorName }?.1 ?? .blue
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !releaseWindows.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Instagram, TV, Food", text: $name)
                }

                Section("Days") {
                    Toggle("Every Day", isOn: $everyDay)
                    if !everyDay { weekdayGrid }
                }

                Section("Appearance") {
                    appearanceSection
                }

                Section {
                    Picker("Type", selection: $limitType) {
                        ForEach(RestraintLimitType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    if limitType == .duration {
                        Stepper("Awarded: \(awardedMinutes) min per window", value: $awardedMinutes, in: 1...480, step: 5)
                    } else {
                        HStack {
                            Text("Awarded amount")
                            Spacer()
                            TextField("700", text: $quantityLimit)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            TextField("kcal", text: $quantityUnit)
                                .frame(width: 60)
                        }
                    }
                } header: {
                    Text("Award per Release Window")
                } footer: {
                    Text("You are restrained at all times. At each release window you earn this amount.")
                }

                Section {
                    ForEach(releaseWindows.indices, id: \.self) { idx in
                        HStack {
                            DatePicker(
                                "",
                                selection: windowBinding(for: idx),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            Spacer()
                            Text(releaseWindows[idx].timeString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button(action: { releaseWindows.remove(at: idx) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    DatePicker("New release time", selection: $newWindowTime, displayedComponents: .hourAndMinute)

                    Button(action: addWindow) {
                        Label("Add Release Window", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Release Windows")
                } footer: {
                    Text("The times each day when you're released from the restraint.")
                }
            }
            .navigationTitle(restraint == nil ? "New Restraint" : "Edit Restraint")
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
            .onAppear { loadExisting() }
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(selectedColor)
                    .frame(width: 36, height: 36)
                    .background(selectedColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Preview")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 2)

            Text("Color").font(.caption).foregroundColor(.secondary)
            LazyVGrid(columns: colorCols, spacing: 8) {
                ForEach(colorOptions, id: \.0) { (cName, color) in
                    Button(action: { colorName = cName }) {
                        ZStack {
                            Circle().fill(color).frame(width: 32, height: 32)
                            if colorName == cName {
                                Image(systemName: "checkmark")
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Icon").font(.caption).foregroundColor(.secondary)
            LazyVGrid(columns: iconCols, spacing: 8) {
                ForEach(iconOptions, id: \.self) { icon in
                    Button(action: { iconName = icon }) {
                        Image(systemName: icon)
                            .font(.body)
                            .frame(width: 40, height: 36)
                            .background(iconName == icon ? selectedColor.opacity(0.2) : Color(.systemGray6))
                            .foregroundColor(iconName == icon ? selectedColor : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var weekdayGrid: some View {
        LazyVGrid(columns: weekdayCols, spacing: 4) {
            ForEach(weekdayLabels, id: \.0) { (num, label) in
                Button(action: { toggleWeekday(num) }) {
                    Text(label)
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selectedWeekdays.contains(num) ? Color.blue : Color(.systemGray5))
                        .foregroundColor(selectedWeekdays.contains(num) ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func windowBinding(for idx: Int) -> Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = releaseWindows[idx].hour
                c.minute = releaseWindows[idx].minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { d in
                let cal = Calendar.current
                releaseWindows[idx].hour = cal.component(.hour, from: d)
                releaseWindows[idx].minute = cal.component(.minute, from: d)
            }
        )
    }

    private func toggleWeekday(_ num: Int) {
        if selectedWeekdays.contains(num) { selectedWeekdays.remove(num) }
        else { selectedWeekdays.insert(num) }
    }

    private func addWindow() {
        let cal = Calendar.current
        releaseWindows.append(RestraintTimeWindowInfo(
            hour: cal.component(.hour, from: newWindowTime),
            minute: cal.component(.minute, from: newWindowTime)
        ))
    }

    private func loadExisting() {
        guard let r = restraint else { return }
        name = r.name
        everyDay = r.weekdays.isEmpty
        selectedWeekdays = Set(r.weekdays)
        limitType = r.effectiveLimitType
        awardedMinutes = r.awardedMinutes
        quantityLimit = r.quantityLimit > 0 ? String(format: "%g", r.quantityLimit) : ""
        quantityUnit = r.quantityUnit
        releaseWindows = r.timeWindows
        colorName = r.colorName
        iconName = r.iconName
    }

    private func save() {
        let days = everyDay ? [] : Array(selectedWeekdays)
        let qLimit = Double(quantityLimit) ?? 0
        if let r = restraint {
            r.name = name.trimmingCharacters(in: .whitespaces)
            r.weekdays = days
            r.limitType = limitType.rawValue
            r.awardedMinutes = awardedMinutes
            r.quantityLimit = qLimit
            r.quantityUnit = quantityUnit
            r.timeWindows = releaseWindows
            r.colorName = colorName
            r.iconName = iconName
        } else {
            let r = Restraint(
                name: name.trimmingCharacters(in: .whitespaces),
                weekdays: days,
                limitType: limitType,
                awardedMinutes: awardedMinutes,
                quantityLimit: qLimit,
                quantityUnit: quantityUnit,
                timeWindows: releaseWindows,
                colorName: colorName,
                iconName: iconName
            )
            modelContext.insert(r)
        }
        dismiss()
    }
}
