import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showAlertView = false
    @State private var showAlertManager = false
    @State private var showBackgroundCounter = false
    
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
                        
                        TasksCalendarView()
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                withAnimation {
                                    showBackgroundCounter.toggle()
                                }
                            } label: {
                                Image(systemName: showBackgroundCounter ? "clock.arrow.circlepath.fill" : "clock.arrow.circlepath")
                                    .foregroundColor(.blue)
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showAlertView = true
                            } label: {
                                Image(systemName: "clock")
                            }
                        }
                    }
                }
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Tasks")
                }
                
                NavigationStack {
                    HabitDashboardView()
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
                    RewardsView()
                }
                .tabItem {
                    Image(systemName: "gift")
                    Text("Rewards")
                }
                
                NavigationStack {
                    AlertManagerView()
                }
                .tabItem {
                    Image(systemName: "bell.badge")
                    Text("Alerts")
                }
                
                NavigationStack {
                    FastingView()
                }
                .tabItem {
                    Image(systemName: "fork.knife")
                    Text("Fasting")
                }
            }
            .sheet(isPresented: $showAlertView) {
                AlertView()
            }
            .sheet(isPresented: $showAlertManager) {
                AlertManagerView()
            }
            
            QuickAlertButton()
            
            FloatingTimerView()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            
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
        .modelContainer(for: [Task.self, Habit.self, Reward.self, FastingSession.self], inMemory: true)
}
