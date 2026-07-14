import SwiftUI
import SwiftData
import Charts

private struct InsightSlice: Identifiable {
    let id = UUID()
    let name: String
    let minutes: Double
    let percent: Double
}

struct TimeInsightsView: View {
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    let range: DateRange

    @State private var selectedCategory: ActivityCategory?

    private static let palette: [Color] = [.blue, .green, .purple, .orange, .pink, .teal, .indigo, .cyan]

    private var availableMinutes: Double {
        range.elapsedMinutes()
    }

    private var slices: [InsightSlice] {
        guard availableMinutes > 0 else { return [] }
        var result = projects.map { project -> InsightSlice in
            let minutes = project.totalMinutes(from: range.start, to: range.end, category: selectedCategory)
            return InsightSlice(name: project.name, minutes: minutes, percent: minutes / availableMinutes * 100)
        }
        let loggedMinutes = result.reduce(0.0) { $0 + $1.minutes }
        let undocumented = max(availableMinutes - loggedMinutes, 0)
        result.append(InsightSlice(name: "Undocumented", minutes: undocumented, percent: undocumented / availableMinutes * 100))
        return result
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

    private var barHeight: CGFloat { CGFloat(max(slices.count, 1)) * 44 + 24 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                chartSection
                if !slices.isEmpty {
                    breakdownSection
                }
            }
            .padding()
        }
        .navigationTitle("Time Insights")
    }

    @ViewBuilder
    private var chartSection: some View {
        GroupBox {
            categoryFilterRow
            if slices.isEmpty {
                emptyLabel("No projects yet")
            } else {
                Chart(slices) { slice in
                    BarMark(
                        x: .value("Hours", slice.minutes / 60),
                        y: .value("Project", slice.name)
                    )
                    .foregroundStyle(by: .value("Project", slice.name))
                    .annotation(position: .overlay) {
                        barAnnotation(for: slice)
                    }
                }
                .chartForegroundStyleScale(domain: colorDomain, range: colorRange)
                .chartLegend(.hidden)
                .chartXAxisLabel("Hours")
                .frame(height: barHeight)
            }
        } label: {
            Label("Time Breakdown", systemImage: "chart.bar.fill")
                .font(.headline)
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
                    Capsule().fill(cat?.color.opacity(isSelected ? 0.85 : 0.18) ?? Color.secondary.opacity(isSelected ? 0.3 : 0.12))
                )
                .foregroundColor(cat == nil ? .primary : (isSelected ? .white : .primary))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func barAnnotation(for slice: InsightSlice) -> some View {
        if slice.percent > 0 {
            Text(String(format: "%.0f%%", slice.percent))
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var breakdownSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                ForEach(slices) { slice in
                    breakdownRow(for: slice)
                }
            }
        } label: {
            Label("Breakdown", systemImage: "list.bullet")
                .font(.headline)
        }
    }

    @ViewBuilder
    private func breakdownRow(for slice: InsightSlice) -> some View {
        HStack {
            Circle()
                .fill(color(for: slice.name))
                .frame(width: 8, height: 8)
            Text(slice.name)
                .fontWeight(slice.name == "Undocumented" ? .regular : .medium)
                .foregroundColor(slice.name == "Undocumented" ? .secondary : .primary)
            Spacer()
            Text(DurationInput.string(from: slice.minutes))
                .foregroundColor(.secondary)
            Text(String(format: "%.0f%%", slice.percent))
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .font(.subheadline)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }
}
