import SwiftUI
import SwiftData

struct RestraintInstanceRow: Identifiable {
    // Sentinel window used for abstinence (zero-tolerance) restraints, which
    // have one row per day rather than one per release window. -1 can never
    // collide with a real window time (always 0–23 / 0–59).
    static let abstinenceHour = -1
    static let abstinenceMinute = -1

    var id: String { "\(Int(date.timeIntervalSince1970))-\(windowHour)-\(windowMinute)" }
    var date: Date
    var windowHour: Int
    var windowMinute: Int
    var record: RestraintInstance?
    var status: String { record?.status ?? "pending" }
    var isAbstinenceRow: Bool { windowHour == Self.abstinenceHour && windowMinute == Self.abstinenceMinute }
}

struct RestraintInstancesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let restraint: Restraint

    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var selectedRow: RestraintInstanceRow?
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showMarkAllPassConfirm = false

    static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    private var generatedRows: [RestraintInstanceRow] {
        let cal = Calendar.current
        var rows: [RestraintInstanceRow] = []
        let createdDay = cal.startOfDay(for: restraint.createdAt)
        let requestedStart = cal.startOfDay(for: startDate)
        var current = max(requestedStart, createdDay)
        let end = cal.startOfDay(for: endDate)
        let allInstances = restraint.instances
        // Abstinence restraints (no release windows) get one row per
        // scheduled day, using a sentinel window time — there's no time of
        // day to release at, just a daily Pass/Fail.
        let windows = restraint.isAbstinence
            ? [RestraintTimeWindowInfo(hour: RestraintInstanceRow.abstinenceHour, minute: RestraintInstanceRow.abstinenceMinute)]
            : restraint.timeWindows

        while current <= end {
            if restraint.isScheduledOn(date: current) {
                for window in windows {
                    let wh = window.hour
                    let wm = window.minute
                    let rec = allInstances.first { inst in
                        cal.isDate(inst.date, inSameDayAs: current) &&
                        inst.windowHour == wh &&
                        inst.windowMinute == wm
                    }
                    rows.append(RestraintInstanceRow(
                        date: current,
                        windowHour: wh,
                        windowMinute: wm,
                        record: rec
                    ))
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return rows.reversed()
    }

    private func markAllPendingAsPass() {
        for row in generatedRows where row.status == "pending" {
            let rec: RestraintInstance
            if let existing = row.record {
                rec = existing
            } else {
                rec = RestraintInstance(restraint: restraint, date: row.date, windowHour: row.windowHour, windowMinute: row.windowMinute)
                modelContext.insert(rec)
            }
            rec.status = "pass"
        }
        try? modelContext.save()
    }

    private var summaryText: String {
        let rows = generatedRows
        let passed  = rows.filter { $0.status == "pass" }.count
        let failed  = rows.filter { $0.status == "fail" }.count
        let pending = rows.filter { $0.status == "pending" }.count
        return "\(rows.count) total · \(passed) pass · \(failed) fail · \(pending) pending"
    }

    @ViewBuilder
    private var instanceContent: some View {
        let rows = generatedRows
        if rows.isEmpty {
            Text("No instances in this range")
                .foregroundColor(.secondary)
                .font(.caption)
        } else {
            ForEach(rows) { row in
                InstanceRowCell(row: row, restraint: restraint)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedRow = row }
            }
        }
    }

    var body: some View {
        List {
            Section("Date Range") {
                DateRangeShiftControl(start: $startDate, end: $endDate)
                DatePicker("From", selection: $startDate, in: ...endDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
            }

            Section(summaryText) {
                instanceContent
            }
        }
        .navigationTitle(restraint.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showEdit = true }) {
                        Label("Edit Restraint", systemImage: "pencil")
                    }
                    Button(action: { showMarkAllPassConfirm = true }) {
                        Label("Mark All Pending as Pass", systemImage: "checkmark.circle")
                    }
                    .disabled(!generatedRows.contains { $0.status == "pending" })
                    Button(role: .destructive, action: { showDeleteConfirm = true }) {
                        Label("Delete Restraint", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Mark all pending in this range as Pass?", isPresented: $showMarkAllPassConfirm, titleVisibility: .visible) {
            Button("Mark All Pass") { markAllPendingAsPass() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Applies to every currently-pending instance in \(Self.dateFmt.string(from: startDate)) – \(Self.dateFmt.string(from: endDate)).")
        }
        .sheet(item: $selectedRow) { row in
            LogInstanceView(restraint: restraint, row: row)
        }
        .sheet(isPresented: $showEdit) {
            CreateRestraintView(restraint: restraint)
        }
        .confirmationDialog("Delete \"\(restraint.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(restraint)
                try? modelContext.save()
                let remaining = (try? modelContext.fetch(FetchDescriptor<Restraint>())) ?? []
                RestraintNotificationScheduler.rescheduleAll(from: remaining)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the restraint and all its logged instances.")
        }
    }
}

private struct InstanceRowCell: View {
    let row: RestraintInstanceRow
    let restraint: Restraint

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dateFmt.string(from: row.date))
                        .font(.subheadline)
                    Text(windowTimeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    passFailBadge
                    usageLabels
                }
            }
            if let rec = row.record, !rec.notes.isEmpty {
                Text(rec.notes)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private var windowTimeString: String {
        row.isAbstinenceRow ? "All day" : RestraintTimeWindowInfo(hour: row.windowHour, minute: row.windowMinute).timeString
    }

    private var passFailBadge: some View {
        Text(row.status == "pass" ? "Pass" : row.status == "fail" ? "Fail" : "Pending")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(row.status == "pass" ? .green : row.status == "fail" ? .red : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((row.status == "pass" ? Color.green : row.status == "fail" ? Color.red : Color.orange).opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var usageLabels: some View {
        if let rec = row.record {
            let unit = restraint.effectiveLimitType == .duration ? "min" : restraint.quantityUnit
            if rec.overusedAmount > 0 {
                Text("Over: \(fmt(rec.overusedAmount)) \(unit)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            if rec.awardedUsed > 0 {
                Text("Awarded: \(fmt(rec.awardedUsed)) \(unit)")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

struct LogInstanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let restraint: Restraint
    let row: RestraintInstanceRow

    @State private var status: String = "pending"
    @State private var awardedUsed: String = ""
    @State private var overusedAmount: String = ""
    @State private var notes: String = ""

    private var unit: String {
        restraint.effectiveLimitType == .duration ? "min" : restraint.quantityUnit
    }

    private var baseAward: Double {
        guard let window = restraint.timeWindows.first(where: { $0.hour == row.windowHour && $0.minute == row.windowMinute }) else { return 0 }
        return restraint.effectiveAward(for: window)
    }

    private var rollover: Double {
        restraint.rolloverIntoWindow(hour: row.windowHour, minute: row.windowMinute, on: row.date)
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section(restraint.name) {
                    HStack {
                        Text(Self.dateFmt.string(from: row.date))
                        Spacer()
                        Text(row.isAbstinenceRow ? "All day" : RestraintTimeWindowInfo(hour: row.windowHour, minute: row.windowMinute).timeString)
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        Text("Pending").tag("pending")
                        Text("Pass").tag("pass")
                        Text("Fail").tag("fail")
                    }
                    .pickerStyle(.segmented)
                }

                if !row.isAbstinenceRow {
                    Section {
                        if rollover > 0 {
                            HStack {
                                Text("Available today")
                                Spacer()
                                Text("\(fmt(baseAward + rollover)) \(unit) (includes \(fmt(rollover)) rolled over)")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                        }
                        HStack {
                            Text("Awarded used (\(unit))")
                            Spacer()
                            TextField("0", text: $awardedUsed)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Overused (\(unit))")
                            Spacer()
                            TextField("0", text: $overusedAmount)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    } header: {
                        Text("Usage Log")
                    } footer: {
                        Text("Logging overuse does not automatically mark this as Failed.")
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("Log Instance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRecord() }
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        guard let rec = row.record else { return }
        status = rec.status
        awardedUsed = rec.awardedUsed > 0 ? fmt(rec.awardedUsed) : ""
        overusedAmount = rec.overusedAmount > 0 ? fmt(rec.overusedAmount) : ""
        notes = rec.notes
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }

    private func saveRecord() {
        let rec: RestraintInstance
        if let existing = row.record {
            rec = existing
        } else {
            rec = RestraintInstance(
                restraint: restraint,
                date: row.date,
                windowHour: row.windowHour,
                windowMinute: row.windowMinute
            )
            modelContext.insert(rec)
        }
        rec.status = status
        rec.awardedUsed = Double(awardedUsed) ?? 0
        rec.overusedAmount = Double(overusedAmount) ?? 0
        rec.notes = notes
        try? modelContext.save()
        dismiss()
    }
}
