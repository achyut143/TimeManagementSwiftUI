import SwiftUI
import SwiftData

private struct TimelineEntry: Identifiable {
    let id = UUID()
    let projectName: String
    let activityName: String   // "Project time" for direct entries
    let minutes: Double
    let startMinutes: Int?
    let endMinutes: Int?
    let category: ActivityCategory?
}

private struct TimelineDayGroup: Identifiable {
    let date: Date
    var entries: [TimelineEntry]

    var id: Date { date }

    var totalMinutes: Double {
        entries.reduce(0.0) { $0 + $1.minutes }
    }

    var timedEntries: [TimelineEntry] {
        entries.filter { $0.startMinutes != nil && $0.endMinutes != nil }
    }

    var untimedEntries: [TimelineEntry] {
        entries.filter { $0.startMinutes == nil || $0.endMinutes == nil }
            .sorted { $0.projectName < $1.projectName }
    }
}

private let pixelsPerMinute: CGFloat = 1.0
private let hourLabelWidth: CGFloat = 50
private let minBlockHeight: CGFloat = 26

struct ProjectTimelineView: View {
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    let range: DateRange

    private var dayGroups: [TimelineDayGroup] {
        var byDate: [Date: [TimelineEntry]] = [:]

        for project in projects {
            for activity in project.activities where activity.date >= range.start && activity.date <= range.end {
                let entry = TimelineEntry(
                    projectName: project.name,
                    activityName: activity.name,
                    minutes: activity.totalMinutes,
                    startMinutes: activity.startMinutes,
                    endMinutes: activity.endMinutes,
                    category: activity.category
                )
                byDate[activity.date, default: []].append(entry)
            }
            for direct in project.directTimeEntries where direct.date >= range.start && direct.date <= range.end {
                let entry = TimelineEntry(
                    projectName: project.name,
                    activityName: "Project time",
                    minutes: direct.durationMinutes,
                    startMinutes: nil,
                    endMinutes: nil,
                    category: nil
                )
                byDate[direct.date, default: []].append(entry)
            }
        }

        return byDate.map { TimelineDayGroup(date: $0.key, entries: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            if dayGroups.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.day.timeline.left")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No time logged in this range yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(dayGroups) { day in
                    NavigationLink(destination: DayTimelineDetailView(day: day)) {
                        HStack {
                            Text(day.date, style: .date)
                                .font(.subheadline)
                            Spacer()
                            Text(DurationInput.string(from: day.totalMinutes))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Timeline")
    }
}

private struct DayTimelineDetailView: View {
    let day: TimelineDayGroup
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Text("Timeline").tag(0)
                Text("Untimed").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if selectedTab == 0 {
                ScrollView {
                    DayTimelineView(day: day)
                }
            } else {
                UntimedListView(day: day)
            }
        }
        .navigationTitle(day.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UntimedListView: View {
    let day: TimelineDayGroup

    var body: some View {
        if day.untimedEntries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("No untimed activity for this day")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(day.untimedEntries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.activityName)
                        Text(entry.projectName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(DurationInput.string(from: entry.minutes))
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct DayTimelineView: View {
    let day: TimelineDayGroup

    private let hourRange = 0...23

    var body: some View {
        timeline
    }

    private var timeline: some View {
        let range = hourRange
        let totalHeight = CGFloat(range.count) * 60 * pixelsPerMinute

        return ZStack(alignment: .topLeading) {
            ForEach(Array(range), id: \.self) { hour in
                hourRow(hour, baseHour: range.lowerBound)
            }
            ForEach(day.timedEntries) { entry in
                activityBlock(entry, baseHour: range.lowerBound)
            }
        }
        .frame(height: totalHeight)
    }

    private func hourRow(_ hour: Int, baseHour: Int) -> some View {
        let y = CGFloat(hour - baseHour) * 60 * pixelsPerMinute
        return HStack(alignment: .top, spacing: 8) {
            Text(hourLabel(hour))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: hourLabelWidth, alignment: .trailing)
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)
        }
        .offset(y: y)
    }

    @ViewBuilder
    private func activityBlock(_ entry: TimelineEntry, baseHour: Int) -> some View {
        if let start = entry.startMinutes, let end = entry.endMinutes, end > start {
            let y = CGFloat(start - baseHour * 60) * pixelsPerMinute
            let height = max(minBlockHeight, CGFloat(end - start) * pixelsPerMinute)
            let blockColor = entry.category?.color ?? .blue

            HStack(spacing: 4) {
                if let category = entry.category {
                    Circle()
                        .fill(category.color)
                        .frame(width: 6, height: 6)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.activityName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(entry.projectName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height, alignment: .top)
            .background(blockColor.opacity(0.15))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(blockColor.opacity(0.4), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.leading, hourLabelWidth + 16)
            .padding(.trailing, 8)
            .offset(y: y)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 24
        let displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        let ampm = h < 12 ? "AM" : "PM"
        return "\(displayHour) \(ampm)"
    }
}
