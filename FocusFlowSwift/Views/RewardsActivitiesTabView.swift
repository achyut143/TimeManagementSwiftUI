import SwiftUI
import SwiftData

struct RewardsActivitiesTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Tab Picker with enhanced styling
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    HStack {
                        Image(systemName: "gift.fill")
                        Text("Rewards")
                    }.tag(0)
                    
                    HStack {
                        Image(systemName: "clock.badge.checkmark.fill")
                        Text("Activities")
                    }.tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 12)
                
                Divider()
            }
            .background(.ultraThinMaterial)
            
            // Tab Content
            TabView(selection: $selectedTab) {
                // Rewards Tab
                RewardsView()
                    .tag(0)
                
                // Activities Tab  
                ScheduledActivityView()
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: selectedTab)
        }
        .navigationTitle(selectedTab == 0 ? "Rewards" : "Activities")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RewardsActivitiesTabView()
    }
    .modelContainer(for: [Reward.self, ScheduledActivity.self, ActivityUsageHistory.self, Task.self], inMemory: true)
}