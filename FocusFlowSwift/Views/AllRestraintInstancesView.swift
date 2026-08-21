import SwiftUI
import SwiftData

// Same virtual-row generation as RestraintInstancesView, just fanned out across every
// restraint instead of one, so windows without a saved record still show as "pending".
private struct AllInstanceRow: Identifiable {
    let restraint: Restraint
    let date: Date
    let windowHour: Int
    let windowMinute: Int
    let record: RestraintInstance?

    var id: String { "\(restraint.id)-\(Int(date.timeIntervalSince1970))-\(windowHour)-\(windowMinute)" }
    var status: String { record?.status ?? "pending" }
}

private enum InstanceStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pass = "Pass"
    case fail = "Fail"
    case pending = "Pending"
    var id: String { rawValue }
}

struct AllRestraintInstancesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Restraint.createdAt, order: .reverse) private var restraints: [Restraint]

    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var statusFilter: InstanceStatusFilter = .all
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var rowForEdit: AllInstanceRow?
    @State private var showBulkConfirm = false
    @State private var pendingBulkStatus: String = "pass"

    private var generatedRows: [AllInstanceRow] {
        let cal = Calendar.current
        var rows: [AllInstanceRow] = []
        let requestedStart = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)

        for restraint in restraints {
            let createdDay = cal.startOfDay(for: restraint.createdAt)
            var current = max(requestedStart, createdDay)
            let allInstances = restraint.instances

            while current <= end {
                if restraint.isScheduledOn(date: current) {
                    for window in restraint.timeWindows {
                        let wh = window.hour
                        let wm = window.minute
                        let rec = allInstances.first { inst in
                            cal.isDate(inst.date, inSameDayAs: current) &&
                            inst.windowHour == wh &&
                            inst.windowMinute == wm
                        }
                        rows.append(AllInstanceRow(restraint: restraint, date: current, windowHour: wh, windowMinute: wm, record: rec))
                    }
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
        }
        return rows.sorted { $0.date > $1.date }
    }

    private var filteredRows: [AllInstanceRow] {
        switch statusFilter {
        case .all: return generatedRows
        case .pass: return generatedRows.filter { $0.status == "pass" }
        case .fail: return generatedRows.filter { $0.status == "fail" }
        case .pending: return generatedRows.filter { $0.status == "pending" }
        }
    }

    private var summaryText: String {
        let rows = generatedRows
        let passed = rows.filter { $0.status == "pass" }.count
        let failed = rows.filter { $0.status == "fail" }.count
        let pending = rows.filter { $0.status == "pending" }.count
        return "\(rows.count) total · \(passed) pass · \(failed) fail · \(pending) pending"
    }

    var body: some View {
        List {
            Section("Date Range") {
                DateRangeShiftControl(start: $startDate, end: $endDate)
                DatePicker("From", selection: $startDate, in: ...endDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
            }

            Section {
                Picker("Status", selection: $statusFilter) {
                    ForEach(InstanceStatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(summaryText) {
                if filteredRows.isEmpty {
                    Text("No instances match this filter")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(filteredRows) { row in
                        AllInstanceRowCell(row: row, isSelecting: isSelecting, isSelected: selectedIDs.contains(row.id))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelecting {
                                    if selectedIDs.contains(row.id) {
                                        selectedIDs.remove(row.id)
                                    } else {
                                        selectedIDs.insert(row.id)
                                    }
                                } else {
                                    rowForEdit = row
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("All Rule Instances")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    if !isSelecting { selectedIDs.removeAll() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting && !selectedIDs.isEmpty {
                bulkActionBar
            }
        }
        .sheet(item: $rowForEdit) { row in
            LogInstanceView(
                restraint: row.restraint,
                row: RestraintInstanceRow(date: row.date, windowHour: row.windowHour, windowMinute: row.windowMinute, record: row.record)
            )
        }
        .confirmationDialog(
            "Set \(selectedIDs.count) instance\(selectedIDs.count == 1 ? "" : "s") to \(pendingBulkStatus.capitalized)?",
            isPresented: $showBulkConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirm") { applyBulkStatus() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var bulkActionBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedIDs.count) selected")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Pass") { pendingBulkStatus = "pass"; showBulkConfirm = true }
                .tint(.green)
            Button("Fail") { pendingBulkStatus = "fail"; showBulkConfirm = true }
                .tint(.red)
            Button("Pending") { pendingBulkStatus = "pending"; showBulkConfirm = true }
                .tint(.orange)
        }
        .buttonStyle(.bordered)
        .padding()
        .background(.bar)
    }

    private func applyBulkStatus() {
        let targeted = filteredRows.filter { selectedIDs.contains($0.id) }
        for row in targeted {
            let rec: RestraintInstance
            if let existing = row.record {
                rec = existing
            } else {
                rec = RestraintInstance(restraint: row.restraint, date: row.date, windowHour: row.windowHour, windowMinute: row.windowMinute)
                modelContext.insert(rec)
            }
            rec.status = pendingBulkStatus
        }
        try? modelContext.save()
        selectedIDs.removeAll()
        isSelecting = false
    }
}

private struct AllInstanceRowCell: View {
    let row: AllInstanceRow
    let isSelecting: Bool
    let isSelected: Bool

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            Circle()
                .fill(row.restraint.displayColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.restraint.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(Self.dateFmt.string(from: row.date)) · \(windowTimeString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            passFailBadge
        }
        .padding(.vertical, 4)
    }

    private var windowTimeString: String {
        RestraintTimeWindowInfo(hour: row.windowHour, minute: row.windowMinute).timeString
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
}
