import SwiftUI
import SwiftData

struct FloatingTimerView: View {
    @Query(filter: #Predicate<FastingSession> { $0.status == "active" }, sort: \FastingSession.startTime, order: .reverse)
    private var activeSessions: [FastingSession]
    
    @State private var position: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 80, y: 100)
    @State private var isDragging = false
    @State private var currentTime = Date()
    @State private var isExpanded = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var activeSession: FastingSession? {
        activeSessions.first
    }
    
    var body: some View {
        if let session = activeSession {
            ZStack {
                if isExpanded {
                    expandedView(session: session)
                } else {
                    compactView(session: session)
                }
            }
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        position = value.location
                    }
                    .onEnded { _ in
                        isDragging = false
                        snapToEdge()
                    }
            )
            .onReceive(timer) { _ in
                currentTime = Date()
            }
        }
    }
    
    private func compactView(session: FastingSession) -> some View {
        let remainingTime = max(0, session.endTime.timeIntervalSince(currentTime))
        let progressPercentage = min(1.0, max(0.0, currentTime.timeIntervalSince(session.startTime) / session.duration))
        
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        }) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: progressPercentage)
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                    
                    Text(formatTimeCompact(remainingTime))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
            .frame(width: 60, height: 60)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .scaleEffect(isDragging ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func expandedView(session: FastingSession) -> some View {
        let remainingTime = max(0, session.endTime.timeIntervalSince(currentTime))
        let progressPercentage = min(1.0, max(0.0, currentTime.timeIntervalSince(session.startTime) / session.duration))
        
        return VStack(spacing: 8) {
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                Spacer()
                
                Image(systemName: "fork.knife")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 4) {
                Text("Fasting")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                
                Text(formatTimeRemaining(remainingTime))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                
                Text("remaining")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            Divider()
                .background(.white.opacity(0.3))
            
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Started")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(session.startTime, style: .time)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Target")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(session.endTime, style: .time)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.3))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: geometry.size.width * progressPercentage, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        )
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
    }
    
    private func formatTimeCompact(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        
        if hours > 0 {
            return String(format: "%dh%dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
    
    private func formatTimeRemaining(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func snapToEdge() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let margin: CGFloat = 40
        
        // Snap to nearest edge horizontally
        if position.x < screenWidth / 2 {
            position.x = margin
        } else {
            position.x = screenWidth - margin
        }
        
        // Keep within vertical bounds
        position.y = max(margin, min(screenHeight - margin, position.y))
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            // Animation will use the updated position
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()
        
        FloatingTimerView()
    }
    .modelContainer(for: [FastingSession.self], inMemory: true)
}
