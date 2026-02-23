import SwiftUI
import Charts
import SwiftData

struct ActivityWindowChartView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var usageHistory: [ActivityUsageHistory]
    
    let activity: ScheduledActivity
    
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var showDatePicker = false
    @State private var aggregationMode: AggregationMode
    
    private static let startDateKey = "ActivityWindowChartStartDate"
    
    init(activity: ScheduledActivity) {
        self.activity = activity
        let calendar = Calendar.current
        let now = Date()
        
        // Determine aggregation mode based on recurrence type
        let mode: AggregationMode
        let defaultStartDate: Date
        
        switch activity.effectiveRecurrenceType {
        case .daily:
            mode = .daily
            defaultStartDate = calendar.date(byAdding: .day, value: -29, to: now) ?? now
        case .weekly:
            mode = .weekly
            defaultStartDate = calendar.date(byAdding: .weekOfYear, value: -11, to: now) ?? now
        case .monthly:
            mode = .monthly
            defaultStartDate = calendar.date(byAdding: .month, value: -5, to: now) ?? now
        case .quarterly:
            mode = .monthly
            defaultStartDate = calendar.date(byAdding: .month, value: -11, to: now) ?? now
        }
        
        // Load start date from UserDefaults or use default
        let savedStartDate = UserDefaults.standard.object(forKey: Self.startDateKey) as? Date ?? defaultStartDate
        
        _startDate = State(initialValue: savedStartDate)
        _endDate = State(initialValue: now) // Always use today
        _aggregationMode = State(initialValue: mode)
    }
    
    private func saveStartDate() {
        UserDefaults.standard.set(startDate, forKey: Self.startDateKey)
    }
    
    // Filter usage history for this activity
    private var activityHistory: [ActivityUsageHistory] {
        usageHistory.filter { $0.activityName == activity.name }
    }
    
    // Calculate daily data for the date range
    private var dailyData: [DailyWindowData] {
        switch aggregationMode {
        case .daily:
            return calculateDailyData()
        case .weekly:
            return calculateWeeklyData()
        case .monthly:
            return calculateMonthlyData()
        }
    }
    
    private func calculateDailyData() -> [DailyWindowData] {
        let calendar = Calendar.current
        var data: [DailyWindowData] = []
        
        var currentDate = calendar.startOfDay(for: startDate)
        let endOfRange = calendar.startOfDay(for: endDate)
        
        while currentDate <= endOfRange {
            let allocated = allocatedWindows(for: currentDate)
            let used = usedWindows(for: currentDate)
            let overdraft = overdraftWindows(for: currentDate)
            
            data.append(DailyWindowData(
                date: currentDate,
                allocated: allocated,
                used: used,
                overdraft: overdraft,
                label: formatDate(currentDate, for: .daily)
            ))
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return data
    }
    
    private func calculateWeeklyData() -> [DailyWindowData] {
        let calendar = Calendar.current
        var data: [DailyWindowData] = []
        
        var currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start ?? startDate
        let endOfRange = endDate
        
        while currentWeekStart <= endOfRange {
            guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) else { break }
            
            var weekAllocated = 0
            var weekUsed = 0
            var weekOverdraft = 0
            
            // Sum up all days in the week
            var dayInWeek = currentWeekStart
            while dayInWeek <= weekEnd && dayInWeek <= endOfRange {
                weekAllocated += allocatedWindows(for: dayInWeek)
                weekUsed += usedWindows(for: dayInWeek)
                weekOverdraft += overdraftWindows(for: dayInWeek)
                dayInWeek = calendar.date(byAdding: .day, value: 1, to: dayInWeek) ?? dayInWeek
            }
            
            data.append(DailyWindowData(
                date: currentWeekStart,
                allocated: weekAllocated,
                used: weekUsed,
                overdraft: weekOverdraft,
                label: formatDate(currentWeekStart, for: .weekly)
            ))
            
            currentWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) ?? currentWeekStart
        }
        
        return data
    }
    
    private func calculateMonthlyData() -> [DailyWindowData] {
        let calendar = Calendar.current
        var data: [DailyWindowData] = []
        
        var currentMonthStart = calendar.dateInterval(of: .month, for: startDate)?.start ?? startDate
        let endOfRange = endDate
        
        while currentMonthStart <= endOfRange {
            guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonthStart) else { break }
            let monthEnd = min(monthInterval.end, endOfRange)
            
            var monthAllocated = 0
            var monthUsed = 0
            var monthOverdraft = 0
            
            // Sum up all days in the month
            var dayInMonth = currentMonthStart
            while dayInMonth < monthEnd {
                monthAllocated += allocatedWindows(for: dayInMonth)
                monthUsed += usedWindows(for: dayInMonth)
                monthOverdraft += overdraftWindows(for: dayInMonth)
                dayInMonth = calendar.date(byAdding: .day, value: 1, to: dayInMonth) ?? dayInMonth
            }
            
            data.append(DailyWindowData(
                date: currentMonthStart,
                allocated: monthAllocated,
                used: monthUsed,
                overdraft: monthOverdraft,
                label: formatDate(currentMonthStart, for: .monthly)
            ))
            
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonthStart) else { break }
            currentMonthStart = nextMonth
        }
        
        return data
    }
    
    private func formatDate(_ date: Date, for mode: AggregationMode) -> String {
        let formatter = DateFormatter()
        switch mode {
        case .daily:
            formatter.dateFormat = "MMM d"
        case .weekly:
            formatter.dateFormat = "'Week of' MMM d"
        case .monthly:
            formatter.dateFormat = "MMM yyyy"
        }
        return formatter.string(from: date)
    }
    
    // Calculate allocated windows for a specific date
    private func allocatedWindows(for date: Date) -> Int {
        // Check if this date is valid for the activity's recurrence pattern
        if !activity.isValidDayForActivity(date: date) {
            return 0
        }
        
        // Return number of scheduled times for this day
        return activity.scheduledTimes.count
    }
    
    // Calculate used windows for a specific date (excluding overdraft)
    private func usedWindows(for date: Date) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
        
        let usages = activityHistory.filter { usage in
            usage.usedAt >= dayStart && 
            usage.usedAt < dayEnd &&
            (usage.effectiveUsageType == .regularWindow || usage.effectiveUsageType == .creditUsage)
        }
        
        return usages.reduce(0) { sum, usage in
            sum + (usage.creditsUsed ?? 1)
        }
    }
    
    // Calculate overdraft windows for a specific date
    private func overdraftWindows(for date: Date) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
        
        let overdraftUsages = activityHistory.filter { usage in
            usage.usedAt >= dayStart && 
            usage.usedAt < dayEnd &&
            usage.effectiveUsageType == .overdraftUsage
        }
        
        return overdraftUsages.reduce(0) { sum, usage in
            sum + (usage.creditsUsed ?? 1)
        }
    }
    
    private func getQuarterStart(for date: Date, calendar: Calendar) -> Date? {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        return calendar.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1))
    }
    
    // Summary statistics for the selected range
    private var totalAllocated: Int {
        dailyData.reduce(0) { $0 + $1.allocated }
    }
    
    private var totalUsed: Int {
        dailyData.reduce(0) { $0 + $1.used }
    }
    
    private var totalOverdraft: Int {
        dailyData.reduce(0) { $0 + $1.overdraft }
    }
    
    private var aggregationModeDescription: String {
        switch aggregationMode {
        case .daily:
            return "Showing daily data"
        case .weekly:
            return "Showing weekly aggregated data"
        case .monthly:
            return "Showing monthly aggregated data"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Date Range Selector
            VStack(spacing: 12) {
                HStack {
                    Text("Date Range")
                        .font(.headline)
                    Spacer()
                    Button {
                        showDatePicker.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                            Text("\(startDate, style: .date) - \(endDate, style: .date)")
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    }
                }
                
                if showDatePicker {
                    VStack(spacing: 12) {
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                            .onChange(of: startDate) { _, _ in
                                saveStartDate()
                            }
                        
                        HStack {
                            Text("End Date: Today")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(endDate, style: .date)
                                .font(.subheadline)
                        }
                        
                        HStack(spacing: 12) {
                            switch aggregationMode {
                            case .daily:
                                Button("Last 7 Days") {
                                    let calendar = Calendar.current
                                    endDate = Date()
                                    startDate = calendar.date(byAdding: .day, value: -6, to: endDate) ?? endDate
                                    saveStartDate()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Last 30 Days") {
                                    let calendar = Calendar.current
                                    endDate = Date()
                                    startDate = calendar.date(byAdding: .day, value: -29, to: endDate) ?? endDate
                                    saveStartDate()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("This Month") {
                                    let calendar = Calendar.current
                                    let now = Date()
                                    endDate = now
                                    startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
                                    saveStartDate()
                                }
                                .buttonStyle(.bordered)
                                
                            case .weekly:
                                Button("Last 4 Weeks") {
                                    let calendar = Calendar.current
                                    endDate = Date()
                                    startDate = calendar.date(byAdding: .weekOfYear, value: -3, to: endDate) ?? endDate
                                    saveStartDate()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Last 12 Weeks") {
                                    let calendar = Calendar.current
                                    endDate = Date()
                                    startDate = calendar.date(byAdding: .weekOfYear, value: -11, to: endDate) ?? endDate
                                    saveStartDate()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("This Quarter") {
                                    let calendar = Calendar.current
                                    let now = Date()
                                    endDate = now
                                    startDate = getQuarterStart(for: now, calendar: calendar) ?? now
                                    saveStartDate()
                                }
                                .buttonStyle(.bordered)
                                
                            case .monthly:
                                Button("Last 3 Months") {
                                    let calendar = Calendar.current
                                    endDate = Date()
                                    startDate = calendar.date(byAdding: .month, value: -2, to: endDate) ?? endDate
                                    saveStartDate()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Last 6 Months") {
                                    let calendar = Calendar.current
                                    endDate = Date()
                                    startDate = calendar.date(byAdding: .month, value: -5, to: endDate) ?? endDate
                                    saveStartDate()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("This Year") {
                                    let calendar = Calendar.current
                                    let now = Date()
                                    endDate = now
                                    startDate = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: 1, day: 1)) ?? now
                                    saveStartDate()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .font(.caption)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            
            // Line Chart
            if !dailyData.isEmpty {
                Chart {
                    ForEach(dailyData) { data in
                        // Allocated windows area (blue background)
                        AreaMark(
                            x: .value("Date", data.date, unit: .day),
                            y: .value("Windows", data.allocated)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        
                        // Allocated windows line
                        LineMark(
                            x: .value("Date", data.date, unit: .day),
                            y: .value("Windows", data.allocated)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                        .symbol {
                            Circle()
                                .fill(.blue)
                                .frame(width: 8, height: 8)
                        }
                        
                        // Used windows area (green background)
                        AreaMark(
                            x: .value("Date", data.date, unit: .day),
                            y: .value("Windows", data.used)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green.opacity(0.4), Color.green.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        
                        // Used windows line
                        LineMark(
                            x: .value("Date", data.date, unit: .day),
                            y: .value("Windows", data.used)
                        )
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(.catmullRom)
                        .symbol {
                            Rectangle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                        }
                        
                        // Overdraft windows area (red background - if any)
                        if data.overdraft > 0 {
                            AreaMark(
                                x: .value("Date", data.date, unit: .day),
                                y: .value("Windows", data.overdraft)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.4), Color.red.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                            
                            // Overdraft windows line
                            LineMark(
                                x: .value("Date", data.date, unit: .day),
                                y: .value("Windows", data.overdraft)
                            )
                            .foregroundStyle(.red)
                            .lineStyle(StrokeStyle(lineWidth: 3, dash: [5, 3]))
                            .interpolationMethod(.catmullRom)
                            .symbol {
                                Image(systemName: "triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisGridLine()
                        AxisTick()
                        if aggregationMode == .daily {
                            AxisValueLabel(format: .dateTime.month().day())
                        } else if aggregationMode == .weekly {
                            AxisValueLabel(format: .dateTime.month().day())
                        } else {
                            AxisValueLabel(format: .dateTime.month().year())
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartLegend(position: .bottom) {
                    VStack(spacing: 8) {
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 10, height: 10)
                                Text("Allocated")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(.green)
                                    .frame(width: 10, height: 10)
                                Text("Used")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 10))
                                Text("Overdraft")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        Text("Tip: Blue area = allocated windows, Green area = used windows, Red area = overdraft")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        // Show aggregation mode
                        Text(aggregationModeDescription)
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                }
                .frame(height: 300)
                .padding(.horizontal)
            } else {
                Text("No data available for selected range")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
            
            // Summary Stats
            VStack(spacing: 12) {
                Text("Summary (\(startDate, style: .date) - \(endDate, style: .date))")
                    .font(.headline)
                
                HStack {
                    Label("Total Allocated", systemImage: "calendar")
                        .foregroundColor(.blue)
                    Spacer()
                    Text("\(totalAllocated)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Total Used", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Spacer()
                    Text("\(totalUsed)")
                        .fontWeight(.semibold)
                }
                
                if totalOverdraft > 0 {
                    HStack {
                        Label("Total Overdraft", systemImage: "arrow.up.circle.fill")
                            .foregroundColor(.red)
                        Spacer()
                        Text("\(totalOverdraft)")
                            .fontWeight(.semibold)
                    }
                }
                
                Divider()
                
                HStack {
                    Label("Available Credits", systemImage: "gift")
                        .foregroundColor(.orange)
                    Spacer()
                    Text("\(activity.accumulatedWindowCredits)")
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
                
                // Usage Percentage
                if totalAllocated > 0 {
                    let usagePercentage = Double(totalUsed) / Double(totalAllocated) * 100
                    let overdraftPercentage = Double(totalOverdraft) / Double(totalAllocated) * 100
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Usage Rate:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(usagePercentage))%")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(usagePercentage > 100 ? .red : .green)
                        }
                        
                        if totalOverdraft > 0 {
                            HStack {
                                Text("Overdraft Rate:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("+\(Int(overdraftPercentage))%")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
}

struct DailyWindowData: Identifiable {
    let id = UUID()
    let date: Date
    let allocated: Int
    let used: Int
    let overdraft: Int
    let label: String
}

enum AggregationMode {
    case daily
    case weekly
    case monthly
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ScheduledActivity.self, ActivityUsageHistory.self, configurations: config)
    
    let activity = ScheduledActivity(
        name: "Morning Exercise",
        scheduledTimes: [Date()],
        windowDuration: 600,
        recurrenceType: .daily
    )
    activity.windowsUsedInPeriod = 5
    activity.windowsSkippedInPeriod = 2
    activity.overdraftWindowsUsed = 1
    activity.accumulatedWindowCredits = 2
    
    container.mainContext.insert(activity)
    
    // Add some sample usage history
    let calendar = Calendar.current
    for i in 0..<10 {
        if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
            let usage = ActivityUsageHistory(
                activityName: "Morning Exercise",
                usedAt: date,
                windowStartTime: date,
                windowEndTime: date,
                usageType: i % 3 == 0 ? .overdraftUsage : .regularWindow
            )
            container.mainContext.insert(usage)
        }
    }
    
    return ActivityWindowChartView(activity: activity)
        .modelContainer(container)
}
