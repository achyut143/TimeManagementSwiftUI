import SwiftUI
import SwiftData
import Foundation

struct PointsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @Query private var eventDays: [EventDay]
    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var showEventDetail = false
    @State private var selectedEventDate: Date?
    @State private var selectedEventDay: EventDay?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerView
                dateFilters
                pointsCalendar
            }
        }
        .navigationTitle("Self-Efficacy Dashboard")
        .sheet(isPresented: $showEventDetail) {
            if let selectedDate = selectedEventDate {
                EventDetailView(date: selectedDate, eventDay: selectedEventDay)
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Self-Efficacy Dashboard")
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
            ForEach(dateRange, id: \.self) { date in
                pointsDayView(date: date)
            }
        }
        .padding()
    }
    
    private func pointsDayView(date: Date) -> some View {
        let stats = getPointsForDay(date: date)
        let percentage = stats.total > 0 ? Int((stats.earned / stats.total) * 100) : 0
        let eventDay = eventDays.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        let eventTypes = eventDay?.eventTypes ?? []
        
        return ZStack {
            // The points cell content
            VStack(spacing: 2) {
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
            
            // Event day halos - circular glowing rings with gaps
            if !eventTypes.isEmpty {
                Button(action: {
                    selectedEventDate = date
                    selectedEventDay = eventDay
                    showEventDetail = true
                }) {
                    ZStack {
                        // Primary halo - innermost ring with gap
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        eventTypes[0].color.opacity(0.8),
                                        eventTypes[0].color.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 62, height: 62)
                            .shadow(color: eventTypes[0].color.opacity(0.6), radius: 3, x: 0, y: 0)
                            .shadow(color: eventTypes[0].color.opacity(0.4), radius: 6, x: 0, y: 0)
                        
                        // Secondary halo - middle ring
                        if eventTypes.count > 1 {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            eventTypes[1].color.opacity(0.7),
                                            eventTypes[1].color.opacity(0.25)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 68, height: 68)
                                .shadow(color: eventTypes[1].color.opacity(0.5), radius: 4, x: 0, y: 0)
                        }
                        
                        // Tertiary halo - outermost ring
                        if eventTypes.count > 2 {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            eventTypes[2].color.opacity(0.6),
                                            eventTypes[2].color.opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                                .frame(width: 74, height: 74)
                                .shadow(color: eventTypes[2].color.opacity(0.4), radius: 5, x: 0, y: 0)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
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
        let earnedPoints = dayTasks.filter { $0.completed }.reduce(0) { $0 + $1.effectiveWeight }
        
        return PointsStats(earned: earnedPoints, total: totalPoints)
    }
    
    private func colorForPercentage(_ percentage: Int) -> Color {
        switch percentage {
        case 100...: return .green  // 100% or more - excellent!
        case 80..<100: return .green
        case 60..<80: return .orange
        case 40..<60: return .yellow
        default: return .red
        }
    }
    
    private func backgroundColorForPercentage(_ percentage: Int) -> Color {
        switch percentage {
        case 100...: return .green.opacity(0.3)  // Slightly more intense for exceeding 100%
        case 80..<100: return .green.opacity(0.2)
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