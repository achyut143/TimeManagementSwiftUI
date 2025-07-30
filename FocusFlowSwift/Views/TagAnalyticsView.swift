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
        Array(Set(tasks.flatMap { $0.taskDescription.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } })).sorted()
    }
    
    var chartData: [(Date, Double)] {
        let filteredTasks = tasks.filter { task in
            guard let taskDate = task.date, task.completed else { return false }
            let dateInRange = taskDate >= startDate && taskDate <= endDate
            if selectedTags.isEmpty { return dateInRange }
            let taskTags = Set(task.taskDescription.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            return dateInRange && !taskTags.isDisjoint(with: selectedTags)
        }
        
        let dateRange = generateDateRange()
        let groupedByDate = Dictionary(grouping: filteredTasks) { task in
            Calendar.current.startOfDay(for: task.date ?? Date())
        }
        
        return dateRange.map { date in
            let tasksForDate = groupedByDate[date] ?? []
            let timeSpent = tasksForDate.reduce(0.0) { total, task in
                let start = timeToMinutes(task.startTime)
                let end = timeToMinutes(task.endTime)
                return total + Double(end - start)
            }
            return (date, timeSpent / 60.0)
        }
    }
    
    private func generateDateRange() -> [Date] {
        var dates: [Date] = []
        var currentDate = Calendar.current.startOfDay(for: startDate)
        let endOfDay = Calendar.current.startOfDay(for: endDate)
        
        while currentDate <= endOfDay {
            dates.append(currentDate)
            currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        return dates
    }
    
    var totalHours: Double {
        chartData.reduce(0) { $0 + $1.1 }
    }
    
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
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedTags.isEmpty ? "All Completed Tasks" : "Selected Tags: \(selectedTags.joined(separator: ", "))")
                .font(.headline)
            
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
            .frame(height: 250)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}