import SwiftUI

// Global state to track if buttons should be shown
class FloatingButtonsState: ObservableObject {
    static let shared = FloatingButtonsState()
    @Published var isEnabled = true
}

struct FloatingButtonsModifier: ViewModifier {
    @StateObject private var state = FloatingButtonsState.shared
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if state.isEnabled {
                    GeometryReader { _ in
                        ZStack {
                            QuickAlertButton()
                            
                            QuickActivityButton()
                        }
                    }
                    .allowsHitTesting(true)
                }
            }
    }
}

extension View {
    func withFloatingButtons() -> some View {
        modifier(FloatingButtonsModifier())
    }
}
