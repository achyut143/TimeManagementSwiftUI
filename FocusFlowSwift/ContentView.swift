import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showAlertView = false
    @State private var showAlertManager = false
    @State private var showBackgroundCounter = false
    @State private var showDailyNotes = false
    @State private var showNewActivity = false
    @State private var showMetricsSettings = false
    @State private var selectedDate = Date()
    @State private var habitSettings: HabitSettings?
    @AppStorage("metricDays") private var metricDays: Int = 30 // Use AppStorage for cross-view sync
    @ObservedObject private var counterManager = BackgroundCounterManager.shared
    
    var body: some View {
        ZStack {
            TabView {
                NavigationStack {
                    VStack(spacing: 0) {
                        // Background Counter at the top
                        if showBackgroundCounter {
                            BackgroundCounterView()
                                .padding(.horizontal)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        TasksCalendarView(selectedDate: $selectedDate)
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            HStack {
                                Button {
                                    withAnimation {
                                        showBackgroundCounter.toggle()
                                    }
                                } label: {
                                    Text(counterManager.formattedTime(counterManager.totalBackgroundTime))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                
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
                                    }
                                    .padding()
                                    .frame(width: 200)
                                }
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack {
                                Button {
                                    showNewActivity = true
                                } label: {
                                    Image(systemName: "clock.badge.plus")
                                        .foregroundColor(.purple)
                                }
                                
                                Button {
                                    showAlertView = true
                                } label: {
                                    Image(systemName: "clock")
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
                    PointsDashboardView()
                }
                .tabItem {
                    Image(systemName: "star.fill")
                    Text("Points")
                }
                
                NavigationStack {
                    RewardsActivitiesTabView()
                }
                .tabItem {
                    Image(systemName: "gift")
                    Text("Rewards/Activities")
                }
                
                NavigationStack {
                    AlertManagerView()
                }
                .tabItem {
                    Image(systemName: "bell.badge")
                    Text("Alerts")
                }
            }
            .sheet(isPresented: $showAlertView) {
                AlertView()
            }
            .sheet(isPresented: $showAlertManager) {
                AlertManagerView()
            }
            .sheet(isPresented: $showDailyNotes) {
                DailyNotesView(selectedDate: selectedDate)
            }
            .sheet(isPresented: $showNewActivity) {
                NewScheduledActivityView()
            }
            
            QuickAlertButton()
            
            QuickActivityButton()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            
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
        .modelContainer(for: [Task.self, Habit.self, Reward.self, ScheduledActivity.self, ActivityUsageHistory.self, DailyNote.self, HabitSettings.self], inMemory: true)
}
