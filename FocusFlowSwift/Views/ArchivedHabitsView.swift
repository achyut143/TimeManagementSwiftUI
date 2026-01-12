import SwiftUI
import SwiftData

struct ArchivedHabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchivedHabit.archivedDate, order: .reverse) private var archivedHabits: [ArchivedHabit]
    @State private var searchText = ""
    @State private var selectedHabit: ArchivedHabit?
    @State private var showingDetail = false
    @State private var showingDeleteAllAlert = false
    @State private var habitToDelete: ArchivedHabit?
    @State private var showingDeleteConfirmation = false
    
    var filteredHabits: [ArchivedHabit] {
        if searchText.isEmpty {
            return archivedHabits
        } else {
            return archivedHabits.filter { 
                $0.habitName.localizedCaseInsensitiveContains(searchText) ||
                $0.habitDescription.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if filteredHabits.isEmpty {
                    emptyStateView
                } else {
                    habitsList
                }
            }
            .navigationTitle("Archived Habits")
            .searchable(text: $searchText, prompt: "Search archived habits...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showingDeleteAllAlert = true
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                        .disabled(archivedHabits.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(archivedHabits.isEmpty)
                }
            }
            .alert("Delete All Archived Habits", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    deleteAllHabits()
                }
            } message: {
                Text("Are you sure you want to delete all \(archivedHabits.count) archived habits? This action cannot be undone.")
            }
            .alert("Delete Habit", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { 
                    habitToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let habit = habitToDelete {
                        deleteSingleHabit(habit)
                    }
                }
            } message: {
                if let habit = habitToDelete {
                    Text("Are you sure you want to delete '\(habit.habitName)'? This action cannot be undone.")
                }
            }
            .sheet(isPresented: $showingDetail) {
                if let habit = selectedHabit {
                    ArchivedHabitDetailView(habit: habit) { habitToDelete in
                        self.habitToDelete = habitToDelete
                        self.showingDeleteConfirmation = true
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No Archived Habits")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("When you archive habits, they'll appear here with detailed statistics about your performance.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var habitsList: some View {
        List {
            ForEach(filteredHabits, id: \.id) { habit in
                ArchivedHabitRow(habit: habit) {
                    selectedHabit = habit
                    showingDetail = true
                }
                .contextMenu {
                    Button(role: .destructive) {
                        habitToDelete = habit
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onDelete(perform: deleteHabits)
        }
    }
    
    private func deleteHabits(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredHabits[index])
            }
            try? modelContext.save()
        }
    }
    
    private func deleteSingleHabit(_ habit: ArchivedHabit) {
        withAnimation {
            modelContext.delete(habit)
            try? modelContext.save()
        }
        habitToDelete = nil
    }
    
    private func deleteAllHabits() {
        withAnimation {
            for habit in archivedHabits {
                modelContext.delete(habit)
            }
            try? modelContext.save()
        }
    }
}

struct ArchivedHabitRow: View {
    let habit: ArchivedHabit
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.habitName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if !habit.habitDescription.isEmpty {
                            Text(habit.habitDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(habit.formattedCompletionPercentage)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(Color(habit.performanceLevelColor))
                        
                        Text(habit.performanceLevel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    StatChip(icon: "calendar", value: habit.formattedDuration, color: .blue)
                    StatChip(icon: "checkmark.circle", value: "\(habit.totalCompletedDays)", color: .green)
                    StatChip(icon: "flame", value: "\(habit.longestStreak)", color: .orange)
                    
                    Spacer()
                    
                    Text("Archived \(habit.archivedDate, style: .date)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct StatChip: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .cornerRadius(8)
    }
}

struct ArchivedHabitDetailView: View {
    let habit: ArchivedHabit
    let onDelete: (ArchivedHabit) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection
                    
                    // Performance Overview
                    performanceSection
                    
                    // Time Statistics
                    timeSection
                    
                    // Streak Information
                    streakSection
                    
                    // Weekly/Monthly Performance
                    if !habit.weeklyCompletionRates.isEmpty || !habit.monthlyCompletionRates.isEmpty {
                        performanceTrendsSection
                    }
                    
                    // Additional Statistics
                    additionalStatsSection
                }
                .padding()
            }
            .navigationTitle(habit.habitName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        onDelete(habit)
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(habit.performanceLevel)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color(habit.performanceLevelColor))
                
                Spacer()
                
                Text(habit.formattedCompletionPercentage)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(Color(habit.performanceLevelColor))
            }
            
            if !habit.habitDescription.isEmpty {
                Text(habit.habitDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("Archived on \(habit.archivedDate, style: .date)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Overview")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(title: "Completed Days", value: "\(habit.totalCompletedDays)", icon: "checkmark.circle.fill", color: .green)
                StatCard(title: "Missed Days", value: "\(habit.totalMissedDays)", icon: "xmark.circle.fill", color: .red)
                StatCard(title: "Total Tasks", value: "\(habit.totalTasks)", icon: "list.bullet", color: .blue)
                StatCard(title: "Frequency", value: habit.habitFrequencyDescription, icon: "repeat", color: .purple)
            }
        }
    }
    
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Statistics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(title: "Duration", value: habit.formattedDuration, icon: "calendar", color: .blue)
                StatCard(title: "Time Spent", value: habit.formattedTotalTimeSpent, icon: "clock.fill", color: .orange)
                
                if let firstCompletion = habit.firstCompletionDate {
                    StatCard(title: "First Completion", value: firstCompletion.formatted(date: .abbreviated, time: .omitted), icon: "flag.fill", color: .green)
                }
                
                if let lastCompletion = habit.lastCompletionDate {
                    StatCard(title: "Last Completion", value: lastCompletion.formatted(date: .abbreviated, time: .omitted), icon: "flag.checkered", color: .blue)
                }
            }
        }
    }
    
    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Streak Information")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(title: "Longest Streak", value: "\(habit.longestStreak) days", icon: "flame.fill", color: .orange)
                StatCard(title: "Final Streak", value: "\(habit.currentStreakAtArchive) days", icon: "flame", color: .yellow)
                
                if habit.averageDaysBetweenCompletions > 0 {
                    StatCard(title: "Avg. Gap", value: String(format: "%.1f days", habit.averageDaysBetweenCompletions), icon: "calendar.badge.clock", color: .gray)
                }
                
                StatCard(title: "Avg. Weight", value: String(format: "%.1f pts", habit.averageWeight), icon: "star.fill", color: .yellow)
            }
        }
    }
    
    private var performanceTrendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Trends")
                .font(.headline)
            
            if !habit.weeklyCompletionRates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekly Performance")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Text("Best Week:")
                        Spacer()
                        Text("\(habit.bestWeekCompletions) completions")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Worst Week:")
                        Spacer()
                        Text("\(habit.worstWeekCompletions) completions")
                            .fontWeight(.medium)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
    
    private var additionalStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Additional Statistics")
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    Text("Start Date:")
                    Spacer()
                    Text(habit.startDate, style: .date)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("End Date:")
                    Spacer()
                    Text(habit.endDate, style: .date)
                        .fontWeight(.medium)
                }
                
                if habit.totalExpectedDays > 0 {
                    HStack {
                        Text("Expected Days:")
                        Spacer()
                        Text("\(habit.totalExpectedDays)")
                            .fontWeight(.medium)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ArchivedHabit.self, configurations: config)
    
    // Create sample data
    let sampleHabit = ArchivedHabit(
        habitName: "Morning Exercise",
        habitDescription: "fitness, morning, cardio",
        startDate: Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date(),
        endDate: Date(),
        repeatFrequency: 1,
        totalExpectedDays: 90,
        totalCompletedDays: 75,
        totalMissedDays: 15,
        completionPercentage: 83.3,
        longestStreak: 21,
        currentStreakAtArchive: 5,
        averageWeight: 8.5,
        totalTimeSpent: 2250,
        firstCompletionDate: Calendar.current.date(byAdding: .day, value: -88, to: Date()),
        lastCompletionDate: Calendar.current.date(byAdding: .day, value: -2, to: Date()),
        totalTasks: 90,
        bestWeekCompletions: 7,
        worstWeekCompletions: 3,
        averageDaysBetweenCompletions: 1.2
    )
    
    container.mainContext.insert(sampleHabit)
    
    return ArchivedHabitsView()
        .modelContainer(container)
}

#Preview("Detail View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ArchivedHabit.self, configurations: config)
    
    let sampleHabit = ArchivedHabit(
        habitName: "Morning Exercise",
        habitDescription: "fitness, morning, cardio",
        startDate: Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date(),
        endDate: Date(),
        repeatFrequency: 1,
        totalExpectedDays: 90,
        totalCompletedDays: 75,
        totalMissedDays: 15,
        completionPercentage: 83.3,
        longestStreak: 21,
        currentStreakAtArchive: 5,
        averageWeight: 8.5,
        totalTimeSpent: 2250,
        firstCompletionDate: Calendar.current.date(byAdding: .day, value: -88, to: Date()),
        lastCompletionDate: Calendar.current.date(byAdding: .day, value: -2, to: Date()),
        totalTasks: 90,
        bestWeekCompletions: 7,
        worstWeekCompletions: 3,
        averageDaysBetweenCompletions: 1.2
    )
    
    return ArchivedHabitDetailView(habit: sampleHabit) { _ in }
        .modelContainer(container)
}