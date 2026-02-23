import SwiftUI
import SwiftData

struct ActivityHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ActivityUsageHistory.usedAt, order: .reverse) private var history: [ActivityUsageHistory]
    
    @State private var selectedDateRange: DateRange = .week
    
    enum DateRange: String, CaseIterable {
        case day = "Today"
        case week = "This Week"
        case month = "This Month"
        case all = "All Time"
    }
    
    var filteredHistory: [ActivityUsageHistory] {
        let now = Date()
        let calendar = Calendar.current
        
        switch selectedDateRange {
        case .day:
            let startOfDay = calendar.startOfDay(for: now)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
            print("📅 DEBUG: Today filter - Start: \(startOfDay), End: \(endOfDay), Total history: \(history.count)")
            let filtered = history.filter { $0.usedAt >= startOfDay && $0.usedAt < endOfDay }
            print("📅 DEBUG: Today filtered count: \(filtered.count)")
            return filtered
            
        case .week:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let endOfWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: startOfWeek) ?? now
            print("📅 DEBUG: Week filter - Start: \(startOfWeek), End: \(endOfWeek), Total history: \(history.count)")
            let filtered = history.filter { $0.usedAt >= startOfWeek && $0.usedAt < endOfWeek }
            print("📅 DEBUG: Week filtered count: \(filtered.count)")
            return filtered
            
        case .month:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? now
            print("📅 DEBUG: Month filter - Start: \(startOfMonth), End: \(endOfMonth), Total history: \(history.count)")
            let filtered = history.filter { $0.usedAt >= startOfMonth && $0.usedAt < endOfMonth }
            print("📅 DEBUG: Month filtered count: \(filtered.count)")
            print("📅 DEBUG: Month - Latest date in history: \(history.first?.usedAt ?? Date())")
            return filtered
            
        case .all:
            print("📅 DEBUG: All time - Total history: \(history.count)")
            if let earliest = history.last?.usedAt, let latest = history.first?.usedAt {
                print("📅 DEBUG: All time - Date range: \(earliest) to \(latest)")
            }
            return history
        }
    }
    
    var groupedHistory: [(date: Date, key: String, items: [ActivityUsageHistory])] {
        let grouped = Dictionary(grouping: filteredHistory) { usage in
            Calendar.current.startOfDay(for: usage.usedAt)
        }
        
        return grouped.map { (date, items) in
            (date: date, key: DateFormatter.dayFormatter.string(from: date), items: items)
        }.sorted { $0.date > $1.date } // Sort by actual date, not string
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Date Range Picker
                Picker("Date Range", selection: $selectedDateRange) {
                    ForEach(DateRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                if filteredHistory.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(groupedHistory, id: \.date) { group in
                            Section(group.key) {
                                ForEach(group.items, id: \.usedAt) { usage in
                                    HistoryRowView(usage: usage)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Activity History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Activity History")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your activity usage will appear here once you start using scheduled windows")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HistoryRowView: View {
    let usage: ActivityUsageHistory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Activity name with usage type icon
                HStack(spacing: 6) {
                    Image(systemName: usage.effectiveUsageType.icon)
                        .foregroundColor(
                            usage.effectiveUsageType == .creditUsage ? .orange :
                            usage.effectiveUsageType == .creditIgnore ? .red : .blue
                        )
                        .font(.caption)
                    
                    Text(usage.activityName)
                        .font(.headline)
                }
                
                Spacer()
                
                Text(usage.usedAt, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Different display based on usage type
            if usage.effectiveUsageType == .creditUsage {
                HStack {
                    Text("Credit Usage")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                    
                    if let credits = usage.creditsUsed {
                        Text("(\(credits) \(credits == 1 ? "credit" : "credits"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            } else if usage.effectiveUsageType == .creditIgnore {
                HStack {
                    Text("Credit Ignore")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                    
                    if let credits = usage.creditsUsed {
                        Text("(\(credits) \(credits == 1 ? "credit" : "credits"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            } else {
                HStack {
                    Text("Window: \(usage.windowStartTime, style: .time) - \(usage.windowEndTime, style: .time)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            
            if let notes = usage.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

extension DateFormatter {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

#Preview {
    ActivityHistoryView()
        .modelContainer(for: [ActivityUsageHistory.self], inMemory: true)
}