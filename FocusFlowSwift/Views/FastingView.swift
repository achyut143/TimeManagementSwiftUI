import SwiftUI
import SwiftData

struct FastingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<FastingSession> { $0.status == "active" }, sort: \FastingSession.startTime, order: .reverse)
    private var activeSessions: [FastingSession]
    
    @State private var showNewFastingSheet = false
    @State private var showHistorySheet = false
    @State private var currentTime = Date()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var activeSession: FastingSession? {
        activeSessions.first
    }
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            
            VStack(spacing: 20) {
                if let session = activeSession {
                    activeFastingView(session: session, currentTime: currentTime)
                } else {
                    noActiveFastingView
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Fasting")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showHistorySheet = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .sheet(isPresented: $showNewFastingSheet) {
            NewFastingView()
        }
        .sheet(isPresented: $showHistorySheet) {
            FastingHistoryView()
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
    
    @ViewBuilder
    private func activeFastingView(session: FastingSession, currentTime: Date) -> some View {
        let remainingTime = max(0, session.endTime.timeIntervalSince(currentTime))
        let progressPercentage = min(1.0, max(0.0, currentTime.timeIntervalSince(session.startTime) / session.duration))
        
        VStack(spacing: 30) {
            // Countdown Circle
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    .frame(width: 250, height: 250)
                
                Circle()
                    .trim(from: 0, to: progressPercentage)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 250, height: 250)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progressPercentage)
                
                VStack(spacing: 8) {
                    Text(timeString(from: remainingTime))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("remaining")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 40)
            
            // Session Info
            VStack(spacing: 12) {
                HStack {
                    Text("Started:")
                    Spacer()
                    Text(session.startTime, style: .time)
                }
                .font(.subheadline)
                
                HStack {
                    Text("Target:")
                    Spacer()
                    Text(session.endTime, style: .time)
                }
                .font(.subheadline)
                
                HStack {
                    Text("Duration:")
                    Spacer()
                    Text(durationString(from: session.duration))
                }
                .font(.subheadline)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            
            // Action Buttons
            HStack(spacing: 16) {
                Button {
                    completeFasting(session: session, success: true)
                } label: {
                    Label("Success", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button {
                    completeFasting(session: session, success: false)
                } label: {
                    Label("Failed", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
    }
    
    private var noActiveFastingView: some View {
        VStack(spacing: 30) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 80))
                .foregroundColor(.gray)
                .padding(.top, 60)
            
            Text("No Active Fasting")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Start a new fasting session to track your progress")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                showNewFastingSheet = true
            } label: {
                Label("Start Fasting", systemImage: "play.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 200)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
            .padding(.top, 20)
        }
    }
    
    private func completeFasting(session: FastingSession, success: Bool) {
        session.status = success ? "success" : "failed"
        session.completedAt = Date()
        try? modelContext.save()
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
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

struct NewFastingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var fastingDuration: Double = 16 // hours
    @State private var startNow = true
    @State private var customStartTime = Date()
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Fasting Duration") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Int(fastingDuration)) hours")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Slider(value: $fastingDuration, in: 1...48, step: 1)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Start Time") {
                    Toggle("Start Now", isOn: $startNow)
                    
                    if !startNow {
                        DatePicker("Start Time", selection: $customStartTime)
                    }
                }
                
                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }
                
                Section {
                    Button {
                        startFasting()
                    } label: {
                        Text("Start Fasting")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("New Fasting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func startFasting() {
        let start = startNow ? Date() : customStartTime
        let end = start.addingTimeInterval(fastingDuration * 3600)
        
        let session = FastingSession(
            startTime: start,
            endTime: end,
            status: "active",
            notes: notes.isEmpty ? nil : notes
        )
        
        modelContext.insert(session)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        FastingView()
    }
    .modelContainer(for: [FastingSession.self], inMemory: true)
}
