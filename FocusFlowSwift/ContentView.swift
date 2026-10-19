import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showDailyNotes = false
    @State private var showWorkouts = false
    @State private var openDailyNotesInFocusMode = false
    @State private var showMetricsSettings = false
    @State private var selectedDate = Date()
    @State private var habitSettings: HabitSettings?
    @AppStorage("metricDays") private var metricDays: Int = 30
    @AppStorage("habitPercentageFilter") private var percentageFilter: String = "all"
    
    var body: some View {
        ZStack {
            TabView {
                NavigationStack {
                    TasksCalendarView(selectedDate: $selectedDate, onOpenFocusMode: {
                        openDailyNotesInFocusMode = true
                        showDailyNotes = true
                    })
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
                                    showWorkouts = true
                                } label: {
                                    Image(systemName: "figure.run")
                                        .foregroundColor(.red)
                                }
                                .accessibilityLabel("Workouts")

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
                    ProjectListView()
                }
                .tabItem {
                    Image(systemName: "folder.fill")
                    Text("Projects")
                }

                NavigationStack {
                    PointsDashboardView()
                }
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Self-Efficacy")
                }

                NavigationStack {
                    OKRInsightsView()
                }
                .tabItem {
                    Image(systemName: "sparkles")
                    Text("OKRs")
                }

                NavigationStack {
                    GoalListView()
                }
                .tabItem {
                    Image(systemName: "target")
                    Text("Goals")
                }
            }
            .sheet(isPresented: $showWorkouts) {
                NavigationStack {
                    WorkoutsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showWorkouts = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showDailyNotes, onDismiss: { openDailyNotesInFocusMode = false }) {
                DailyNotesView(selectedDate: selectedDate, startInFocusMode: openDailyNotesInFocusMode)
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
    }
}


#Preview {
    ContentView()
        .modelContainer(for: [Task.self, Habit.self, DailyNote.self, HabitSettings.self, Goal.self, DayBlock.self, Project.self, ProjectActivity.self, ProjectTimeEntry.self, BacklogFolder.self], inMemory: true)
}
