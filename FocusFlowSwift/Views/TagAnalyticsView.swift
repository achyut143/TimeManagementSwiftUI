import SwiftUI
import SwiftData
import Charts

struct TagAnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @State private var selectedTags: Set<String> = []
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()
    
    var allTags: [String] {
        Array(Set(tasks.flatMap { $0.taskDescription.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() } })).sorted()
    }
    
    // Single computation for both hours and points — filter and group tasks once
    private var computedData: (chart: [(Date, Double)], points: [(Date, Double)], totalHours: Double, totalPoints: Double) {
        let cal = Calendar.current
        let rangeStart = cal.startOfDay(for: startDate)
        let rangeEnd = cal.startOfDay(for: endDate)

        // Build date range
        var dates: [Date] = []
        var cur = rangeStart
        while cur <= rangeEnd {
            dates.append(cur)
            cur = cal.date(byAdding: .day, value: 1, to: cur) ?? cur
        }

        // Group filtered tasks by day — single pass
        var hoursByDay: [Date: Double] = [:]
        var pointsByDay: [Date: Double] = [:]
        for task in tasks {
            guard let taskDate = task.date, task.completed else { continue }
            let day = cal.startOfDay(for: taskDate)
            guard day >= rangeStart && day <= rangeEnd else { continue }
            if !selectedTags.isEmpty {
                let taskTags = Set(task.taskDescription.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
                guard !taskTags.isDisjoint(with: selectedTags) else { continue }
            }
            hoursByDay[day, default: 0] += task.effectiveTimeInMinutes / 60.0
            pointsByDay[day, default: 0] += task.effectiveWeight
        }

        var totalHours = 0.0
        var totalPoints = 0.0
        let chart = dates.map { date -> (Date, Double) in
            let h = hoursByDay[date] ?? 0
            totalHours += h
            return (date, h)
        }
        let points = dates.map { date -> (Date, Double) in
            let p = pointsByDay[date] ?? 0
            totalPoints += p
            return (date, p)
        }
        return (chart, points, totalHours, totalPoints)
    }

    var chartData: [(Date, Double)] { computedData.chart }
    var pointsData: [(Date, Double)] { computedData.points }
    var totalHours: Double { computedData.totalHours }
    var totalPoints: Double { computedData.totalPoints }
    
    private func timeToMinutes(_ time: String) -> Int {
        let components = time.split(separator: ":").compactMap { Int($0) }
        return components.count == 2 ? components[0] * 60 + components[1] : 0
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statsCard
                dateFilterSection
                tagSection
                chartSection
            }
            .padding()
        }
        .navigationTitle("Tag Analytics")
        .background(Color(.systemGroupedBackground))
    }
    
    private var statsCard: some View {
        HStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Total Hours")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f", totalHours))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            VStack(spacing: 8) {
                Text("Total Points")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f", totalPoints))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var dateFilterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Range")
                .font(.headline)
            HStack {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                DatePicker("To", selection: $endDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(allTags, id: \.self) { tag in
                        Button(tag) {
                            if selectedTags.contains(tag) {
                                selectedTags.remove(tag)
                            } else {
                                selectedTags.insert(tag)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedTags.contains(tag) ? .blue : .gray.opacity(0.15))
                        .foregroundColor(selectedTags.contains(tag) ? .white : .primary)
                        .cornerRadius(20)
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(selectedTags.isEmpty ? "All Completed Tasks" : "Selected Tags: \(selectedTags.joined(separator: ", "))")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Hours Spent")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Chart(chartData, id: \.0) { item in
                    BarMark(
                        x: .value("Date", item.0, unit: .day),
                        y: .value("Hours", item.1)
                    )
                    .foregroundStyle(.blue.gradient)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 200)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Points Earned")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Chart(pointsData, id: \.0) { item in
                    BarMark(
                        x: .value("Date", item.0, unit: .day),
                        y: .value("Points", item.1)
                    )
                    .foregroundStyle(.green.gradient)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}