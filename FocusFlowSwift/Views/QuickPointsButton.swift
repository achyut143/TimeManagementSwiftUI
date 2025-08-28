import SwiftUI
import SwiftData

struct QuickPointsButton: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingOptions = false
    @State private var showingConfirmation = false
    @State private var lastAddedAmount: Double = 0
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                
                Menu {
                    Button {
                        addPoints(0.5)
                    } label: {
                        Label("Add 0.5 Points", systemImage: "plus.circle")
                    }
                    
                    Button {
                        addPoints(1.0)
                    } label: {
                        Label("Add 1 Point", systemImage: "plus.circle.fill")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.blue.gradient)
                            .frame(width: 60, height: 60)
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        
                        Image(systemName: "star.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .overlay(alignment: .top) {
            if showingConfirmation {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("+\(String(format: "%.1f", lastAddedAmount)) points added!")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 4)
                .padding(.top, 50)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private func addPoints(_ amount: Double) {
        lastAddedAmount = amount
        Reward.addUnclaimedPoints(amount, context: modelContext)
        
        // Show confirmation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showingConfirmation = true
        }
        
        // Hide confirmation after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showingConfirmation = false
            }
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

#Preview {
    QuickPointsButton()
        .modelContainer(for: Reward.self, inMemory: true)
}
