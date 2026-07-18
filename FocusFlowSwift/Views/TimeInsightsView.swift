import SwiftUI
import SwiftData
import Charts

private struct InsightSlice: Identifiable {
    let id = UUID()
    let name: String
    let minutes: Double
    let percent: Double
    let project: Project?
}

private enum GoalFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case exceeded = "Exceeded"
    case needsImprovement = "Needs Improvement"
    var id: String { rawValue }
}

struct TimeInsightsView: View {
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    let range: DateRange
    var isDark: Bool = false

    // Local shift override so the < > navigator can move the window without a live
    // binding back to the caller; resets whenever the caller passes a new `range`.
    @State private var overrideRange: DateRange?
    @State private var selectedCategory: ActivityCategory?
    @State private var goalFilter: GoalFilter = .all
    @State private var sortByAttention = false

    private static let palette: [Color] = [.blue, .green, .purple, .orange, .pink, .teal, .indigo, .cyan]

    private var effectiveRange: DateRange { overrideRange ?? range }

    private var rangeBinding: Binding<DateRange> {
        Binding(get: { effectiveRange }, set: { overrideRange = $0 })
    }

    private var availableMinutes: Double {
        effectiveRange.elapsedMinutes()
    }

    private var slices: [InsightSlice] {
        guard availableMinutes > 0 else { return [] }
        var result = projects.map { project -> InsightSlice in
            let minutes = project.totalMinutes(from: effectiveRange.start, to: effectiveRange.end, category: selectedCategory)
            return InsightSlice(name: project.name, minutes: minutes, percent: minutes / availableMinutes * 100, project: project)
        }
        let loggedMinutes = result.reduce(0.0) { $0 + $1.minutes }
        let undocumented = max(availableMinutes - loggedMinutes, 0)
        result.append(InsightSlice(name: "Undocumented", minutes: undocumented, percent: undocumented / availableMinutes * 100, project: nil))
        return result
    }

    private var hasGoals: Bool {
        projects.contains { $0.goalType != nil }
    }

    private func status(for slice: InsightSlice) -> ProjectGoalStatus {
        slice.project?.goalStatus(actualPercent: slice.percent) ?? .none
    }

    // Higher score = needs more attention. Control projects score by how far over the
    // target they are; Improve projects score by how far under. No goal sorts last.
    private func attentionScore(for slice: InsightSlice) -> Double {
        guard let target = slice.project?.targetPercent, let type = slice.project?.goalType else {
            return -Double.greatestFiniteMagnitude
        }
        let delta = slice.percent - target
        switch type {
        case .control: return delta
        case .improve: return -delta
        }
    }

    // How far off the target the actual percentage is, phrased per goal type so it
    // reads naturally either way ("8% over (1h 20m)" vs "8% short (1h 20m)").
    private func deltaText(for slice: InsightSlice) -> String? {
        guard let target = slice.project?.targetPercent, let type = slice.project?.goalType else { return nil }
        let delta = slice.percent - target
        if abs(delta) < 0.5 { return "on target" }
        let targetMinutes = target / 100 * availableMinutes
        let hoursText = DurationInput.string(from: abs(slice.minutes - targetMinutes))
        switch type {
        case .control:
            return delta > 0 ? "\(Int(delta))% over (\(hoursText))" : "\(Int(-delta))% under (\(hoursText))"
        case .improve:
            return delta > 0 ? "\(Int(delta))% ahead (\(hoursText))" : "\(Int(-delta))% short (\(hoursText))"
        }
    }

    private var filteredSlices: [InsightSlice] {
        let base: [InsightSlice]
        switch goalFilter {
        case .all: base = slices
        case .exceeded: base = slices.filter { status(for: $0) == .exceeded }
        case .needsImprovement: base = slices.filter { status(for: $0) == .needsImprovement }
        }
        guard sortByAttention else { return base }
        return base.sorted { attentionScore(for: $0) > attentionScore(for: $1) }
    }

    private var colorDomain: [String] {
        projects.map { $0.name } + ["Undocumented"]
    }

    private var colorRange: [Color] {
        projects.indices.map { Self.palette[$0 % Self.palette.count] } + [.gray]
    }

    private func color(for name: String) -> Color {
        if let index = colorDomain.firstIndex(of: name) { return colorRange[index] }
        return .gray
    }

    // Bars for projects with a goal are colored by status (red/orange/green) instead of
    // the per-project palette color, so the chart itself flags what needs attention.
    private func barColor(for slice: InsightSlice) -> Color {
        let goalStatus = status(for: slice)
        return goalStatus == .none ? color(for: slice.name) : goalStatus.color
    }

    private var barHeight: CGFloat { CGFloat(max(filteredSlices.count, 1)) * 44 + 24 }

    var body: some View {
        Group {
            if isDark {
                // No inner ScrollView / navigationTitle here: this mode is embedded in a
                // fixed (non-scrolling) Focus View layout, so it must size to its natural
                // content height like its sibling widgets, not scroll internally.
                content
            } else {
                ScrollView {
                    content
                        .padding()
                }
                .navigationTitle("Time Insights")
            }
        }
        .onChange(of: range) { _, _ in overrideRange = nil }
    }

    private var content: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                DateRangeNavigatorView(range: rangeBinding, isDark: isDark)
                HStack {
                    Spacer()
                    todayButton
                }
            }
            chartSection
            if !filteredSlices.isEmpty {
                breakdownSection
            }
        }
    }

    // Tapping again while already in Today mode clears the override and returns to
    // whatever range the caller originally passed in — otherwise there'd be no way
    // back short of changing the "From" date picker (which may not even fire onChange
    // if you re-pick the same date).
    private var isTodayMode: Bool {
        overrideRange == .day(Date())
    }

    private var todayButton: some View {
        Button {
            overrideRange = isTodayMode ? nil : .day(Date())
        } label: {
            Text(isTodayMode ? "Today ✕" : "Today")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isTodayMode
                        ? (isDark ? Color.cyan.opacity(0.55) : Color.accentColor.opacity(0.4))
                        : (isDark ? Color.cyan.opacity(0.2) : Color.accentColor.opacity(0.15)))
                )
                .foregroundColor(isTodayMode ? .white : (isDark ? .cyan : .accentColor))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var chartSection: some View {
        cardContainer(title: "Time Breakdown", icon: "chart.bar.fill") {
            categoryFilterRow
            if hasGoals {
                goalFilterRow
            }
            if filteredSlices.isEmpty {
                emptyLabel(slices.isEmpty ? "No projects yet" : "Nothing matches this filter")
            } else {
                Chart(filteredSlices) { slice in
                    BarMark(
                        x: .value("Hours", slice.minutes / 60),
                        y: .value("Project", slice.name)
                    )
                    .foregroundStyle(barColor(for: slice))
                    .annotation(position: .trailing) {
                        barAnnotation(for: slice)
                    }

                    if let target = slice.project?.targetPercent, slice.project?.goalType != nil {
                        // A tick mark (not a second bar, so Charts can't dodge it
                        // side-by-side) crossing the actual bar right at the target
                        // position — the gap between the tick and the bar's end is
                        // exactly how much is missed by / exceeded past the mark.
                        PointMark(
                            x: .value("Target", target / 100 * availableMinutes / 60),
                            y: .value("Project", slice.name)
                        )
                        .symbol {
                            Rectangle()
                                .fill(isDark ? Color.white : Color.black.opacity(0.85))
                                .frame(width: 3, height: 26)
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartXAxisLabel("Hours")
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(isDark ? Color.white.opacity(0.2) : Color.gray.opacity(0.25))
                        AxisValueLabel().foregroundStyle(isDark ? Color.white.opacity(0.7) : Color.primary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(isDark ? Color.white : Color.primary)
                    }
                }
                .frame(height: barHeight)
            }
        }
    }

    // Mirrors GroupBox's look but recolors for the Focus View's dark background when isDark.
    @ViewBuilder
    private func cardContainer<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        if isDark {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundColor(.white)
                content()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        } else {
            GroupBox {
                content()
            } label: {
                Label(title, systemImage: icon)
                    .font(.headline)
            }
        }
    }

    private var categoryFilterRow: some View {
        HStack(spacing: 8) {
            categoryFilterChip(nil, label: "All")
            ForEach(ActivityCategory.allCases) { cat in
                categoryFilterChip(cat, label: cat.rawValue)
            }
            Spacer()
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func categoryFilterChip(_ cat: ActivityCategory?, label: String) -> some View {
        let isSelected = selectedCategory == cat
        Button {
            selectedCategory = cat
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(cat?.color.opacity(isSelected ? 0.85 : 0.18) ?? (isDark ? Color.white.opacity(isSelected ? 0.3 : 0.12) : Color.secondary.opacity(isSelected ? 0.3 : 0.12)))
                )
                .foregroundColor(cat == nil ? (isDark ? .white : .primary) : (isSelected ? .white : (isDark ? .white : .primary)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func barAnnotation(for slice: InsightSlice) -> some View {
        if slice.percent > 0 {
            HStack(spacing: 3) {
                if let icon = status(for: slice).icon {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundColor(status(for: slice).color)
                }
                Text(String(format: "%.0f%%", slice.percent))
            }
            .font(.caption2).fontWeight(.bold)
            .foregroundColor(isDark ? .white : .primary)
        }
    }

    private var goalFilterRow: some View {
        HStack(spacing: 8) {
            ForEach(GoalFilter.allCases) { filter in
                goalFilterChip(filter)
            }
            Spacer()
            sortByAttentionChip
        }
        .padding(.bottom, 8)
    }

    private var sortByAttentionChip: some View {
        Button {
            sortByAttention.toggle()
        } label: {
            Label("Attention", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.red.opacity(sortByAttention ? 0.85 : 0.18))
                )
                .foregroundColor(sortByAttention ? .white : (isDark ? .white : .primary))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func goalFilterChip(_ filter: GoalFilter) -> some View {
        let isSelected = goalFilter == filter
        Button {
            goalFilter = filter
        } label: {
            Text(filter.rawValue)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(goalFilterColor(filter).opacity(isSelected ? 0.85 : 0.18))
                )
                .foregroundColor(isSelected ? .white : (isDark ? .white : .primary))
        }
        .buttonStyle(.plain)
    }

    private func goalFilterColor(_ filter: GoalFilter) -> Color {
        switch filter {
        case .all: return isDark ? .white.opacity(0.4) : .secondary
        case .exceeded: return .red
        case .needsImprovement: return .orange
        }
    }

    @ViewBuilder
    private var breakdownSection: some View {
        cardContainer(title: "Breakdown", icon: "list.bullet") {
            VStack(spacing: 8) {
                ForEach(filteredSlices) { slice in
                    breakdownRow(for: slice)
                }
            }
        }
    }

    @ViewBuilder
    private func breakdownRow(for slice: InsightSlice) -> some View {
        let goalStatus = status(for: slice)
        HStack {
            Circle()
                .fill(color(for: slice.name))
                .frame(width: 8, height: 8)
            Text(slice.name)
                .fontWeight(slice.name == "Undocumented" ? .regular : .medium)
                .foregroundColor(slice.name == "Undocumented" ? (isDark ? .white.opacity(0.5) : .secondary) : (isDark ? .white : .primary))
            if let icon = goalStatus.icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(goalStatus.color)
            }
            Spacer()
            if let delta = deltaText(for: slice) {
                Text(delta)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(goalStatus == .none ? (isDark ? .white.opacity(0.4) : .secondary) : goalStatus.color)
            }
            Text(DurationInput.string(from: slice.minutes))
                .foregroundColor(isDark ? .white.opacity(0.6) : .secondary)
            Text(String(format: "%.0f%%", slice.percent))
                .foregroundColor(isDark ? .white.opacity(0.6) : .secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .font(.subheadline)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundColor(isDark ? .white.opacity(0.5) : .secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }
}
