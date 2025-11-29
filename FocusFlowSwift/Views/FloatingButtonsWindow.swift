import SwiftUI
import UIKit

class FloatingButtonsWindow: UIWindow {
    init() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            super.init(windowScene: windowScene)
        } else {
            super.init(frame: UIScreen.main.bounds)
        }
        
        self.windowLevel = .alert
        self.isHidden = false
        self.isUserInteractionEnabled = true
        self.backgroundColor = .clear
        
        let hostingController = UIHostingController(rootView: FloatingButtonsOverlay())
        hostingController.view.backgroundColor = .clear
        self.rootViewController = hostingController
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        
        // Only intercept touches on the actual buttons, not the entire window
        if hitView == self || hitView == rootViewController?.view {
            return nil
        }
        
        return hitView
    }
}

struct FloatingButtonsOverlay: View {
    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            QuickAlertButton()
            
            FloatingTimerView()
        }
    }
}

class FloatingButtonsWindowManager {
    static let shared = FloatingButtonsWindowManager()
    private var window: FloatingButtonsWindow?
    
    func show() {
        if window == nil {
            window = FloatingButtonsWindow()
        }
    }
    
    func hide() {
        window?.isHidden = true
        window = nil
    }
}
