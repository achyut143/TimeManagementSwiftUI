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
        ZStack(alignment: .top) {
            Color.clear
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ActiveTaskBannerView()
        }
    }
}

// MARK: - Active Task Banner

struct ActiveTaskBannerView: View {
    @StateObject private var settings = AlertSettings.shared

    var body: some View {
        if settings.isPlaying || settings.isPaused {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        let secs = Int(max(0, settings.nextAlertDate.timeIntervalSince(context.date)))
                        let countdownText = settings.isPaused
                            ? "Paused"
                            : String(format: "%d:%02d", secs / 60, secs % 60)

                        HStack(spacing: 8) {
                            Image(systemName: settings.isPaused ? "pause.circle.fill" : "timer")
                                .font(.caption)
                                .foregroundColor(settings.isPaused ? .orange : .blue)

                            Text(settings.activeTaskName.isEmpty ? "Cycle running" : settings.activeTaskName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .foregroundColor(.primary)

                            Spacer()

                            Text(countdownText)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(settings.isPaused ? .orange : .blue)
                                .contentTransition(.numericText())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
                    .padding(.top, geo.safeAreaInsets.top + 4)

                    Spacer()
                }
            }
            .ignoresSafeArea()
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
