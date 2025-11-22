import SwiftUI
import SwiftData

enum DateFilterOption: String, CaseIterable {
    case week = "1 Week"
    case twoWeeks = "2 Weeks"
    case month = "1 Month"
    case threeMonths = "3 Months"
    case all = "All Time"
    
    var days: Int? {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 30
        case .threeMonths: return 90
        case .all: return nil
        }
    }
}

struct FastingHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<FastingSession> { $0.status != "active" }, sort: \FastingSession.completedAt, order: .reverse)
    private var allCompletedSessions: [FastingSession]
    
    @State private var selectedFilter: DateFilterOption = .week
    @State private var editingSession: FastingSession?
    @State private var showNotesEditor = false
    
    var filteredSessions: [FastingSession] {
        guard let days = selectedFilter.days else {
            return allCompletedSessions
        }
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return allCompletedSessions.filter { session in
            guard let completedAt = session.completedAt else { return false }
            return completedAt >= cutoffDate
        }
    }
    
    var successCount: Int {
        filteredSessions.filter { $0.status == "success" }.count
    }
    
    var failedCount: Int {
        filteredSessions.filter { $0.status == "failed" }.count
    }
    
    var successRate: Double {
        let total = filteredSessions.count
        guard total > 0 else { return 0 }
        return Double(successCount) / Double(total) * 100
    }
    
    var averageDuration: TimeInterval {
        guard !filteredSessions.isEmpty else { return 0 }
        let totalDuration = filteredSessions.reduce(0.0) { $0 + $1.duration }
        return totalDuration / Double(filteredSessions.count)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Time Range", selection: $selectedFilter) {
                        ForEach(DateFilterOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                
                Section {
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
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
                        
                        HStack(spacing: 12) {
                            StatCard(
                                title: "Total",
                                value: "\(filteredSessions.count)",
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
                        
                        if !filteredSessions.isEmpty {
                            StatCard(
                                title: "Avg Duration",
                                value: durationString(from: averageDuration),
                                color: .orange,
                                icon: "clock.fill"
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                
                Section("History") {
                    if filteredSessions.isEmpty {
                        Text("No completed fasting sessions in this time range")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(filteredSessions) { session in
                            FastingHistoryRow(session: session) {
                                editingSession = session
                                showNotesEditor = true
                            }
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
            .sheet(isPresented: $showNotesEditor) {
                if let session = editingSession {
                    EditNotesView(session: session)
                }
            }
        }
    }
    
    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredSessions[index])
        }
        try? modelContext.save()
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
    let onEditNotes: () -> Void
    
    var body: some View {
        Button(action: onEditNotes) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: session.status == "success" ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(session.status == "success" ? .green : .red)
                    
                    Text(session.status == "success" ? "Success" : "Failed")
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
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
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        MarkdownText(text: notes)
                            .lineLimit(2)
                    }
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text.badge.plus")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        
                        Text("Add notes")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
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

struct EditNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let session: FastingSession
    @State private var notes: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: session.status == "success" ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(session.status == "success" ? .green : .red)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.status == "success" ? "Success" : "Failed")
                                .fontWeight(.semibold)
                            
                            if let completedAt = session.completedAt {
                                Text(completedAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(durationString(from: session.duration))
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("\(session.startTime, style: .time) - \(session.endTime, style: .time)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Notes") {
                    RichTextEditor(text: $notes)
                        .frame(height: 250)
                }
            }
            .navigationTitle("Edit Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveNotes()
                    }
                }
            }
            .onAppear {
                notes = session.notes ?? ""
            }
        }
    }
    
    private func saveNotes() {
        session.notes = notes.isEmpty ? nil : notes
        try? modelContext.save()
        dismiss()
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
