import SwiftUI

struct QuickAlertButton: View {
    @StateObject private var settings = AlertSettings.shared
    @State private var position: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 80, y: UIScreen.main.bounds.height - 200)
    @State private var isDragging = false
    @State private var timeRemaining: TimeInterval = 0
    @State private var isExpanded = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if settings.isPlaying {
            ZStack {
                if isExpanded {
                    expandedView
                } else {
                    compactView
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
                updateTimeRemaining()
            }
            .onAppear {
                updateTimeRemaining()
            }
        }
    }
    
    private var compactView: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: settings.isPaused ? "pause.circle.fill" : "bell.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                
                if !settings.isPaused {
                    Text(formatTimeCompact(timeRemaining))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                } else {
                    Text("Paused")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 60, height: 60)
            .background(
                Circle()
                    .fill(settings.isPaused ? Color.orange : (timeRemaining <= 30 ? Color.red : Color.green))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .scaleEffect(isDragging ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var expandedView: some View {
        VStack(spacing: 8) {
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
                
                Image(systemName: settings.isPaused ? "pause.circle.fill" : "bell.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }
            
            if settings.useCycles {
                let cycleProgress = settings.getCurrentCycleProgress()
                
                VStack(spacing: 4) {
                    Text("\(cycleProgress.current)/\(cycleProgress.total)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Cycle Progress")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                VStack(spacing: 4) {
                    Text("\(settings.counter)\(settings.targetIntervals.map { "/\($0)" } ?? "")")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Intervals")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            
            if !settings.isPaused {
                Divider()
                    .background(.white.opacity(0.3))
                
                VStack(spacing: 4) {
                    Text(formatTimeRemaining(timeRemaining))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    
                    Text("Until Next Alert")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                Text("Paused")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            if settings.useCycles && !settings.cyclePhases.isEmpty && settings.currentCycleIndex < settings.cyclePhases.count {
                Divider()
                    .background(.white.opacity(0.3))
                
                Text(settings.cyclePhases[settings.currentCycleIndex].name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 140)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(settings.isPaused ? Color.orange : (timeRemaining <= 30 ? Color.red : Color.green))
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        )
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
    }
    
    private func updateTimeRemaining() {
        if settings.isPlaying && !settings.isPaused {
            timeRemaining = max(0, settings.nextAlertDate.timeIntervalSinceNow)
        } else {
            timeRemaining = 0
        }
    }
    
    private func formatTimeCompact(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatTimeRemaining(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
        
        QuickAlertButton()
    }
}
