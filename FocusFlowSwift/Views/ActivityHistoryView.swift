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
            return history.filter { $0.usedAt >= startOfDay && $0.usedAt < endOfDay }
            
        case .week:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let endOfWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: startOfWeek) ?? now
            return history.filter { $0.usedAt >= startOfWeek && $0.usedAt < endOfWeek }
            
        case .month:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? now
            return history.filter { $0.usedAt >= startOfMonth && $0.usedAt < endOfMonth }
            
        case .all:
            return history
        }
    }
    
    var groupedHistory: [String: [ActivityUsageHistory]] {
        Dictionary(grouping: filteredHistory) { usage in
            DateFormatter.dayFormatter.string(from: usage.usedAt)
        }
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
                        ForEach(groupedHistory.keys.sorted(by: >), id: \.self) { dateKey in
                            Section(dateKey) {
                                ForEach(groupedHistory[dateKey] ?? [], id: \.usedAt) { usage in
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
                        .foregroundColor(usage.effectiveUsageType == .creditUsage ? .orange : .blue)
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