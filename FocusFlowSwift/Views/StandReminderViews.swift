import SwiftUI
import UIKit

// MARK: - Settings

struct StandReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StandReminder.enabledKey) private var enabled = false
    @AppStorage(StandReminder.sitMinutesKey) private var sitMinutes = StandReminder.defaultSitMinutes
    @AppStorage(StandReminder.standMinutesKey) private var standMinutes = StandReminder.defaultStandMinutes
    @AppStorage(StandReminder.stretchEnabledKey) private var stretchEnabled = StandReminder.defaultStretchEnabled
    @AppStorage(StandReminder.stretchMinutesKey) private var stretchMinutes = StandReminder.defaultStretchMinutes

    var body: some View {
        Form {
            Section {
                Toggle("Stand & stretch reminder", isOn: Binding(
                    get: { enabled },
                    set: { StandReminder.setEnabled($0) }
                ))
            } footer: {
                Text("While on, a floating timer shows the current step. At each switch you'll be asked to acknowledge, and get a notification if the app is closed.")
            }

            Section {
                Stepper("Sit for \(sitMinutes) min", value: setting($sitMinutes), in: 5...180, step: 5)
                Stepper("Stand for \(standMinutes) min", value: setting($standMinutes), in: 5...120, step: 5)
                Toggle("Stretch after standing", isOn: setting($stretchEnabled))
                if stretchEnabled {
                    Stepper("Stretch for \(stretchMinutes) min", value: setting($stretchMinutes), in: 1...30)
                }
            } header: {
                Text("Cycle")
            } footer: {
                Text(cycleSummary)
            }

            if enabled {
                Section {
                    Button("Restart cycle (start sitting now)") {
                        StandReminder.restart()
                    }
                }
            }
        }
        .navigationTitle("Stand & Stretch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var cycleSummary: String {
        var steps = ["sit \(sitMinutes)", "stand \(standMinutes)"]
        if stretchEnabled { steps.append("stretch \(stretchMinutes)") }
        return steps.joined(separator: " → ").capitalizedFirst + " min, then repeat."
    }

    /// Routes edits through StandReminder so the current step keeps going
    /// instead of jumping, and notifications move to the new times.
    private func setting<V>(_ binding: Binding<V>) -> Binding<V> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                StandReminder.updateSettings { binding.wrappedValue = newValue }
            }
        )
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Floating pill

/// Small draggable timer shown in the floating overlay window — only while
/// the reminder is on. Tap for options, drag to move.
///
/// At each sit/stand/stretch switch it nags like the calendar-task timer in
/// Daily Notes: speaks "Time to stand. Please acknowledge." every 8 seconds
/// and shows a "Tap to acknowledge" state until tapped. Acknowledgment is
/// saved in AcknowledgmentStore, so reopening the app doesn't re-nag.
struct StandTimerPill: View {
    @AppStorage(StandReminder.enabledKey) private var enabled = false
    // Read so the pill re-renders when settings change.
    @AppStorage(StandReminder.sitMinutesKey) private var sitMinutes = StandReminder.defaultSitMinutes
    @AppStorage(StandReminder.standMinutesKey) private var standMinutes = StandReminder.defaultStandMinutes
    @AppStorage(StandReminder.stretchEnabledKey) private var stretchEnabled = StandReminder.defaultStretchEnabled
    @AppStorage(StandReminder.stretchMinutesKey) private var stretchMinutes = StandReminder.defaultStretchMinutes
    @AppStorage(StandReminder.startedAtKey) private var startedAt: Double = 0
    // Position as a fraction of the screen, so it survives rotation.
    @AppStorage("standReminder.pillX") private var pillX: Double = 0.82
    @AppStorage("standReminder.pillY") private var pillY: Double = 0.72

    @State private var now = Date()
    @State private var expanded = false
    @State private var dragOffset: CGSize = .zero
    @State private var pendingAck = false
    @State private var lastSpokenAt: Date?

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        if enabled {
            GeometryReader { geo in
                pill(status: StandReminder.status(at: now))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                        OverlayHitRegions.shared.set("standPill", rect)
                    }
                    .position(
                        x: clamp(pillX * geo.size.width + dragOffset.width, 90, geo.size.width - 90),
                        y: clamp(pillY * geo.size.height + dragOffset.height, geo.safeAreaInsets.top + 30, geo.size.height - 40)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { dragOffset = $0.translation }
                            .onEnded { value in
                                pillX = clamp(pillX + value.translation.width / geo.size.width, 0.1, 0.9)
                                pillY = clamp(pillY + value.translation.height / geo.size.height, 0.08, 0.95)
                                dragOffset = .zero
                            }
                    )
            }
            .onReceive(ticker) { date in
                now = date
                tick()
            }
            .onAppear { tick() }
            .onDisappear { stopNag() }
        } else {
            Color.clear
                .allowsHitTesting(false)
                .onAppear {
                    OverlayHitRegions.shared.set("standPill", nil)
                    stopNag()
                }
        }
    }

    // MARK: Look

    private func color(_ phase: StandReminder.Phase) -> Color {
        switch phase {
        case .sit: return .teal
        case .stand: return .orange
        case .stretch: return .purple
        }
    }

    private func icon(_ phase: StandReminder.Phase) -> String {
        switch phase {
        case .sit: return "chair.fill"
        case .stand: return "figure.stand"
        case .stretch: return "figure.flexibility"
        }
    }

    private func label(_ phase: StandReminder.Phase) -> String {
        switch phase {
        case .sit: return "Sit"
        case .stand: return "Stand"
        case .stretch: return "Stretch"
        }
    }

    private func pill(status: StandReminder.Status) -> some View {
        let tint = color(status.phase)
        return VStack(spacing: 6) {
            if pendingAck {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                    Text(StandReminder.title(for: status.phase))
                        .fontWeight(.semibold)
                }
                .font(.caption)
                Text("Tap to acknowledge · \(format(status.secondsRemaining))")
                    .font(.caption2.monospacedDigit())
            } else {
                HStack(spacing: 6) {
                    Image(systemName: icon(status.phase))
                    Text(label(status.phase))
                        .fontWeight(.semibold)
                    Text(format(status.secondsRemaining))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                }
                .font(.caption)

                if expanded {
                    let nextPhase = StandReminder.next(after: status.phase)
                    Text("Next: \(label(nextPhase)) \(StandReminder.minutes(for: nextPhase)) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("\(label(nextPhase)) now") {
                            StandReminder.skipToNextPhase()
                            expanded = false
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .tint(color(nextPhase))

                        Button {
                            stopNag()
                            StandReminder.setEnabled(false)
                            expanded = false
                        } label: {
                            Image(systemName: "power")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityLabel("Turn off stand reminder")
                    }
                }
            }
        }
        .foregroundStyle(pendingAck ? Color.white : tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if pendingAck {
                RoundedRectangle(cornerRadius: 14).fill(tint)
            } else {
                RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .fixedSize()
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            if pendingAck {
                acknowledge()
            } else {
                withAnimation(.snappy) { expanded.toggle() }
            }
        }
        .animation(.snappy, value: pendingAck)
        .animation(.snappy, value: status.phase)
    }

    // MARK: Acknowledgment nag

    private func tick() {
        let date = Date()
        let needsAck = !StandReminder.isCurrentPhaseAcknowledged(at: date)

        if needsAck && !pendingAck {
            pendingAck = true
            expanded = false
            lastSpokenAt = nil
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else if !needsAck && pendingAck {
            stopNag()
            return
        }

        guard pendingAck else { return }
        if lastSpokenAt.map({ date.timeIntervalSince($0) >= 8 }) ?? true {
            lastSpokenAt = date
            let phase = StandReminder.status(at: date).phase
            SpeechManager.shared.speak("\(StandReminder.title(for: phase)). Please acknowledge.")
        }
    }

    private func acknowledge() {
        StandReminder.acknowledgeCurrentPhase()
        stopNag()
    }

    private func stopNag() {
        guard pendingAck else { return }
        pendingAck = false
        lastSpokenAt = nil
        SpeechManager.shared.stopSpeaking()
    }

    private func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), max(lo, hi))
    }
}

/// Rects (window coordinates) inside the floating overlay window that should
/// receive touches. Everywhere else, touches pass through to the app.
final class OverlayHitRegions {
    static let shared = OverlayHitRegions()
    private var rects: [String: CGRect] = [:]
    private let lock = NSLock()

    func set(_ key: String, _ rect: CGRect?) {
        lock.lock(); defer { lock.unlock() }
        rects[key] = rect
    }

    func contains(_ point: CGPoint) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return rects.values.contains { $0.insetBy(dx: -6, dy: -6).contains(point) }
    }
}
