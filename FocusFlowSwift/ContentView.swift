import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showAlertManager = false
    @State private var showBooksLibrary = false
    @State private var showDailyNotes = false
    @State private var showNewActivity = false
    @State private var showMetricsSettings = false
    @State private var selectedDate = Date()
    @State private var habitSettings: HabitSettings?
    @AppStorage("metricDays") private var metricDays: Int = 30
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("habitPercentageFilter") private var percentageFilter: String = "all"
    
    // Query for active activities (used for points distribution)
    @Query(filter: #Predicate<ScheduledActivity> { $0.isActive })
    private var activeActivities: [ScheduledActivity]

    // Watch completed tasks to award points to activities
    @Query(filter: #Predicate<Task> { $0.completed == true })
    private var completedTasks: [Task]

    @State private var initialCompletedTaskIds: Set<UUID> = []
    
    var body: some View {
        ZStack {
            TabView {
                NavigationStack {
                    TasksCalendarView(selectedDate: $selectedDate)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            HStack(spacing: 12) {
                                Button {
                                    showDailyNotes = true
                                } label: {
                                    Image(systemName: "note.text")
                                        .foregroundColor(.green)
                                }

                                Button {
                                    showMetricsSettings = true
                                } label: {
                                    HStack(spacing: 2) {
                                        Image(systemName: "chart.bar.fill")
                                            .font(.caption)
                                        Text("\(metricDays)d")
                                            .font(.caption2)
                                        if percentageFilter != "all" {
                                            Circle()
                                                .fill(percentageFilter == "above" ? Color.green : Color.orange)
                                                .frame(width: 6, height: 6)
                                        }
                                    }
                                    .foregroundColor(.orange)
                                }
                                .popover(isPresented: $showMetricsSettings) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Metrics Period")
                                            .font(.headline)

                                        Text("Show completion rate and streak for:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        ForEach([7, 15, 30, 45, 60], id: \.self) { days in
                                            Button(action: {
                                                metricDays = days
                                                if let settings = habitSettings {
                                                    settings.updateMetricDays(days, context: modelContext)
                                                }
                                                showMetricsSettings = false
                                            }) {
                                                HStack {
                                                    Text("Last \(days) days")
                                                    Spacer()
                                                    if metricDays == days {
                                                        Image(systemName: "checkmark")
                                                            .foregroundColor(.blue)
                                                    }
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.vertical, 4)
                                        }

                                        Divider()

                                        Text("Completion Filter")
                                            .font(.headline)

                                        Text("Show repeat tasks matching:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        HStack(spacing: 8) {
                                            ForEach([("all", "All", Color.blue), ("above", "≥85%", Color.green), ("below", "<85%", Color.orange)], id: \.0) { value, label, color in
                                                Button(action: { percentageFilter = value }) {
                                                    Text(label)
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(percentageFilter == value ? .white : color)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 6)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .fill(percentageFilter == value ? color : color.opacity(0.12))
                                                        )
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                        }
                                    }
                                    .padding()
                                    .frame(width: 220)
                                }

                                Button {
                                    showBooksLibrary = true
                                } label: {
                                    Image(systemName: "books.vertical")
                                        .foregroundColor(.indigo)
                                }
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Button {
                                    showNewActivity = true
                                } label: {
                                    Label("New Activity", systemImage: "clock.badge.plus")
                                }
                                Divider()
                                Button {
                                    isDarkMode.toggle()
                                } label: {
                                    Label(isDarkMode ? "Switch to Light" : "Switch to Dark",
                                          systemImage: isDarkMode ? "sun.max.fill" : "moon.fill")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Tasks")
                }
                
                NavigationStack {
                    HabitOverviewView()
                }
                .tabItem {
                    Image(systemName: "repeat")
                    Text("Habits")
                }

                NavigationStack {
                    GoalListView()
                }
                .tabItem {
                    Image(systemName: "target")
                    Text("Goals")
                }

                NavigationStack {
                    PointsDashboardView()
                }
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Self-Efficacy")
                }

                NavigationStack {
                    ScheduledActivityView()
                }
                .tabItem {
                    Image(systemName: "clock.badge.checkmark.fill")
                    Text("Activities")
                }

                NavigationStack {
                    OKRInsightsView()
                }
                .tabItem {
                    Image(systemName: "sparkles")
                    Text("OKRs")
                }

                NavigationStack {
                    AlertManagerView()
                }
                .tabItem {
                    Image(systemName: "bell.badge")
                    Text("Alerts")
                }

                NavigationStack {
                    RestraintListView()
                }
                .tabItem {
                    Image(systemName: "hand.raised.fill")
                    Text("Restraints")
                }
            }
            .sheet(isPresented: $showAlertManager) {
                AlertManagerView()
            }
            .sheet(isPresented: $showDailyNotes) {
                DailyNotesView(selectedDate: selectedDate)
            }
            .sheet(isPresented: $showBooksLibrary) {
                BooksView()
            }
            .sheet(isPresented: $showNewActivity) {
                NewScheduledActivityView()
            }
            
            QuickActivityButton()

            // Active timer button (iOS 16.1+)
            if #available(iOS 16.1, *) {
                ActiveTimerButton()
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true

            // Activate the UIWindow overlay (shown above sheets & popovers)
            FloatingButtonsWindowManager.shared.show()

            // Load habit settings
            habitSettings = HabitSettings.getOrCreate(context: modelContext)
            if let settings = habitSettings {
                metricDays = settings.effectiveMetricDays
            }
            
            // Force refresh Live Activity when main view appears
            if #available(iOS 16.1, *) {
                AlertSettings.shared.forceRefreshLiveActivity()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onAppear {
            initialCompletedTaskIds = Set(completedTasks.map { $0.id })
        }
        .onChange(of: completedTasks) { oldTasks, newTasks in
            let knownIds = Set(oldTasks.map { $0.id }).union(initialCompletedTaskIds)
            let newlyCompleted = newTasks.filter { !knownIds.contains($0.id) }
            guard !newlyCompleted.isEmpty else { return }
            for task in newlyCompleted {
                let pts = task.effectiveWeight
                guard pts > 0 else { continue }
                for activity in activeActivities {
                    activity.addTaskPoints(pts, context: modelContext)
                }
            }
            try? modelContext.save()
        }
    }
}


#Preview {
    ContentView()
        .modelContainer(for: [Task.self, Habit.self, ScheduledActivity.self, ActivityUsageHistory.self, DailyNote.self, HabitSettings.self, Goal.self, DayBlock.self, Restraint.self, RestraintInstance.self], inMemory: true)
}
