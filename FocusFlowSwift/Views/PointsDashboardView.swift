import SwiftUI
import SwiftData
import Foundation

struct PointsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate = Date()
    
    var body: some View {
        VStack(spacing: 16) {
            headerView
            dateFilters
            pointsCalendar
        }
        .navigationTitle("Points Dashboard")
    }
    
    private var headerView: some View {
        HStack {
            Text("Points Dashboard")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding()
    }
    
    private var dateFilters: some View {
        HStack {
            DatePicker("From", selection: $fromDate, displayedComponents: .date)
                .datePickerStyle(.compact)
            
            DatePicker("To", selection: $toDate, displayedComponents: .date)
                .datePickerStyle(.compact)
        }
        .padding(.horizontal)
    }
    
    private var pointsCalendar: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
            ForEach(dateRange, id: \.self) { date in
                pointsDayView(date: date)
            }
        }
        .padding()
    }
    
    private func pointsDayView(date: Date) -> some View {
        let stats = getPointsForDay(date: date)
        let percentage = stats.total > 0 ? Int((stats.earned / stats.total) * 100) : 0
        
        return VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.caption)
                .fontWeight(.medium)
            
            Text(DateFormatter.shortMonth.string(from: date))
                .font(.caption2)
            
            Text(DateFormatter.weekday.string(from: date))
                .font(.caption2)
            
            Text("\(Int(stats.earned))/\(Int(stats.total))")
                .font(.caption2)
                .fontWeight(.semibold)
            
            Text("\(percentage)%")
                .font(.caption2)
                .foregroundColor(colorForPercentage(percentage))
        }
        .frame(width: 50, height: 70)
        .background(backgroundColorForPercentage(percentage))
        .cornerRadius(6)
    }
    
    private var dateRange: [Date] {
        var dates: [Date] = []
        var currentDate = fromDate
        
        while currentDate <= toDate {
            dates.append(currentDate)
            currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return dates
    }
    
    private func getPointsForDay(date: Date) -> PointsStats {
        let dayTasks = tasks.filter { task in
            Calendar.current.isDate(task.date ?? Date(), inSameDayAs: date)
        }
        
        let totalPoints = dayTasks.reduce(0) { $0 + $1.weight }
        let earnedPoints = dayTasks.filter { $0.completed }.reduce(0) { $0 + $1.weight }
        
        return PointsStats(earned: earnedPoints, total: totalPoints)
    }
    
    private func colorForPercentage(_ percentage: Int) -> Color {
        switch percentage {
        case 80...100: return .green
        case 60..<80: return .orange
        case 40..<60: return .yellow
        default: return .red
        }
    }
    
    private func backgroundColorForPercentage(_ percentage: Int) -> Color {
        switch percentage {
        case 80...100: return .green.opacity(0.2)
        case 60..<80: return .orange.opacity(0.2)
        case 40..<60: return .yellow.opacity(0.2)
        default: return .red.opacity(0.2)
        }
    }
}

struct PointsStats {
    let earned: Double
    let total: Double
}

#Preview {
    PointsDashboardView()
        .modelContainer(for: [Task.self], inMemory: true)
}