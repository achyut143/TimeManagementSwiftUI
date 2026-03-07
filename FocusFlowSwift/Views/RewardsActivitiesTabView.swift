import SwiftUI
import SwiftData

struct RewardsActivitiesTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Tab Picker with enhanced styling
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    Text("Activities").tag(0)
                    Text("Rewards").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 12)
                
                Divider()
            }
            .background(.ultraThinMaterial)
            
            // Tab Content
            TabView(selection: $selectedTab) {
                // Activities Tab  
                ScheduledActivityView()
                    .tag(0)
                
                // Rewards Tab
                RewardsView()
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: selectedTab)
        }
        .navigationTitle(selectedTab == 0 ? "Activities" : "Rewards")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RewardsActivitiesTabView()
    }
    .modelContainer(for: [Reward.self, ScheduledActivity.self, ActivityUsageHistory.self, Task.self], inMemory: true)
}