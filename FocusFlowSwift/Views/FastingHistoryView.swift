import SwiftUI
import SwiftData

struct FastingHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<FastingSession> { $0.status != "active" }, sort: \FastingSession.completedAt, order: .reverse)
    private var completedSessions: [FastingSession]
    
    var successCount: Int {
        completedSessions.filter { $0.status == "success" }.count
    }
    
    var failedCount: Int {
        completedSessions.filter { $0.status == "failed" }.count
    }
    
    var successRate: Double {
        let total = completedSessions.count
        guard total > 0 else { return 0 }
        return Double(successCount) / Double(total) * 100
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        HStack(spacing: 20) {
                            StatCard(
                                title: "Success",
                                value: "\(successCount)",
                                color: .green,
                                icon: "checkmark.circle.fill"
                            )
                            
                            StatCard(
                                title: "Failed",
                                value: "\(failedCount)",
                                color: .red,
                                icon: "xmark.circle.fill"
                            )
                        }
                        
                        HStack(spacing: 20) {
                            StatCard(
                                title: "Total",
                                value: "\(completedSessions.count)",
                                color: .blue,
                                icon: "chart.bar.fill"
                            )
                            
                            StatCard(
                                title: "Success Rate",
                                value: String(format: "%.0f%%", successRate),
                                color: .purple,
                                icon: "percent"
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                
                Section("History") {
                    if completedSessions.isEmpty {
                        Text("No completed fasting sessions yet")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(completedSessions) { session in
                            FastingHistoryRow(session: session)
                        }
                        .onDelete(perform: deleteSessions)
                    }
                }
            }
            .navigationTitle("Fasting History")
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
    
    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(completedSessions[index])
        }
        try? modelContext.save()
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct FastingHistoryRow: View {
    let session: FastingSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: session.status == "success" ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(session.status == "success" ? .green : .red)
                
                Text(session.status == "success" ? "Success" : "Failed")
                    .fontWeight(.semibold)
                
                Spacer()
                
                if let completedAt = session.completedAt {
                    Text(completedAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Label(durationString(from: session.duration), systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(session.startTime, style: .time) - \(session.endTime, style: .time)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func durationString(from interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

#Preview {
    FastingHistoryView()
        .modelContainer(for: [FastingSession.self], inMemory: true)
}
