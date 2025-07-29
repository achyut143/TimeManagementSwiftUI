import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showAlertView = false
    
    var body: some View {
        TabView {
            NavigationView {
                TasksCalendarView()
                  .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Alerts") {
                                showAlertView = true
                            }
                        }
                    }
            }
            .tabItem {
                Image(systemName: "calendar")
                Text("Tasks")
            }
            
            NavigationView {
                HabitDashboardView()
            }
            .tabItem {
                Image(systemName: "repeat")
                Text("Habits")
            }
            
            NavigationView {
                PointsDashboardView()
            }
            .tabItem {
                Image(systemName: "star.fill")
                Text("Points")
            }
        }
        .sheet(isPresented: $showAlertView) {
            AlertView()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Task.self, Habit.self], inMemory: true)
}
