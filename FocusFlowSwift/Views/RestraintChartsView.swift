import SwiftUI
import SwiftData
import Charts

struct RestraintChartsView: View {
    @Query(filter: #Predicate<Restraint> { $0.isActive }) private var restraints: [Restraint]
    @Query private var allInstances: [RestraintInstance]

    // "From" persists across sessions; "To" always resets to today
    @AppStorage("restraintCharts.startDateInterval") private var startDateInterval: Double =
        Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970
    @State private var endDate: Date = Date()
    @State private var searchText: String = ""
    @State private var selectedTab: Int = 0

    private var startDate: Date { Date(timeIntervalSince1970: startDateInterval) }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: startDateInterval) },
            set: { startDateInterval = $0.timeIntervalSince1970 }
        )
    }

    private var filtered: [Restraint] {
        guard !searchText.isEmpty else { return restraints }
        return restraints.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    struct PassFailItem: Identifiable {
        var id = UUID()
        var name: String
        var status: String   // "Pass" or "Fail"
        var count: Int
    }

    struct UsageItem: Identifiable {
        var id = UUID()
        var name: String
        var kind: String     // "Awarded" or "Overused"
        var amount: Double
    }

    private func instances(for r: Restraint) -> [RestraintInstance] {
        let start = startDate
        let end = endDate
        let rid = r.persistentModelID
        return allInstances.filter { inst in
            inst.restraint?.persistentModelID == rid &&
            inst.date >= start && inst.date <= end
        }
    }

    private var passFailItems: [PassFailItem] {
        filtered.flatMap { r -> [PassFailItem] in
            let recs = instances(for: r)
            let passed = recs.filter { $0.isPassed }.count
            let failed = recs.filter { !$0.isPassed }.count
            return [
                PassFailItem(name: r.name, status: "Pass", count: passed),
                PassFailItem(name: r.name, status: "Fail", count: failed)
            ]
        }
    }

    private var usageItems: [UsageItem] {
        filtered.flatMap { r -> [UsageItem] in
            let recs = instances(for: r)
            let awarded = recs.reduce(0.0) { $0 + $1.awardedUsed }
            let overused = recs.reduce(0.0) { $0 + $1.overusedAmount }
            return [
                UsageItem(name: r.name, kind: "Awarded", amount: awarded),
                UsageItem(name: r.name, kind: "Overused", amount: overused)
            ]
        }
    }

    private var barHeight: CGFloat { CGFloat(max(filtered.count, 1)) * 54 + 24 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                DatePicker("", selection: startDateBinding, in: ...endDate, displayedComponents: .date)
                    .labelsHidden()
                Text("–").foregroundColor(.secondary)
                DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .labelsHidden()
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            Picker("Chart", selection: $selectedTab) {
                Text("Pass / Fail").tag(0)
                Text("Usage").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                Group {
                    if selectedTab == 0 { chartA } else { chartB }
                }
                .padding()
            }
        }
        .navigationTitle("Restraint Charts")
        .searchable(text: $searchText, prompt: "Search restraints")
    }

    @ViewBuilder
    private var chartA: some View {
        let items = passFailItems
        let maxStack = Dictionary(grouping: items, by: \.name)
            .values.map { $0.reduce(0) { $0 + $1.count } }.max() ?? 0
        GroupBox {
            if filtered.isEmpty {
                emptyLabel("No restraints")
            } else if maxStack == 0 {
                emptyLabel("No logged instances in this range")
            } else {
                Chart(items) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Restraint", item.name)
                    )
                    .foregroundStyle(by: .value("Status", item.status))
                    .annotation(position: .overlay) {
                        if item.count > 0 {
                            Text("\(item.count)")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
                .chartForegroundStyleScale(["Pass": Color.green, "Fail": Color.red])
                .chartXScale(domain: 0...(maxStack + 1))
                .chartXAxisLabel("Instances")
                .frame(height: barHeight)
            }
        } label: {
            Label("Pass / Fail", systemImage: "checkmark.circle")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var chartB: some View {
        let items = usageItems
        let maxStack = Dictionary(grouping: items, by: \.name)
            .values.map { $0.reduce(0.0) { $0 + $1.amount } }.max() ?? 0.0
        GroupBox {
            if filtered.isEmpty || maxStack == 0 {
                emptyLabel("No usage logged yet")
            } else {
                Chart(items) { item in
                    BarMark(
                        x: .value("Amount", item.amount),
                        y: .value("Restraint", item.name)
                    )
                    .foregroundStyle(by: .value("Type", item.kind))
                    .annotation(position: .overlay) {
                        if item.amount > 0 {
                            let label = item.amount == item.amount.rounded()
                                ? "\(Int(item.amount))"
                                : String(format: "%.1f", item.amount)
                            Text(label)
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
                .chartForegroundStyleScale(["Awarded": Color.blue, "Overused": Color.orange])
                .chartXScale(domain: 0...(maxStack * 1.2 + 1))
                .chartXAxisLabel("Amount")
                .frame(height: barHeight)
            }
        } label: {
            Label("Used vs Awarded", systemImage: "chart.bar.fill")
                .font(.headline)
        }
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }
}
