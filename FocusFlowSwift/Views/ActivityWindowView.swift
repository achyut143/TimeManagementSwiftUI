import SwiftUI

struct ActivityWindowView: View {
    let activity: ScheduledActivity
    @Binding var notes: String
    let onComplete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentTime = Date()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Activity Header
                VStack(spacing: 8) {
                    Text(activity.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("Window is now open!")
                        .font(.headline)
                        .foregroundColor(.green)
                }
                .padding(.top, 40)
                
                // Countdown Timer
                if let windowEnd = activity.currentWindowEndTime() {
                    let remaining = max(0, windowEnd.timeIntervalSince(currentTime))
                    
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 15)
                                .frame(width: 200, height: 200)
                            
                            Circle()
                                .trim(from: 0, to: remaining / activity.windowDuration)
                                .stroke(
                                    LinearGradient(
                                        colors: [.green, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                                )
                                .frame(width: 200, height: 200)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: remaining)
                            
                            VStack(spacing: 4) {
                                Text(timeString(from: remaining))
                                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                                
                                Text("remaining")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("Window closes at \(windowEnd, style: .time)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Notes Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Notes (Optional)")
                        .font(.headline)
                    
                    TextEditor(text: $notes)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button {
                        onComplete()
                    } label: {
                        Label("Mark as Used", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Close Window")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationBarHidden(true)
        }
        .onReceive(timer) { _ in
            currentTime = Date()
            
            // Auto-close if window has ended
            if let windowEnd = activity.currentWindowEndTime(), currentTime > windowEnd {
                dismiss()
            }
        }
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ActivityWindowView(
        activity: ScheduledActivity(
            name: "Instagram",
            scheduledTimes: [Date()],
            windowDuration: 600
        ),
        notes: .constant(""),
        onComplete: {}
    )
}