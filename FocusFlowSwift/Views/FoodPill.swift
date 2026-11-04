import SwiftUI
import SwiftData
import UIKit

/// Floating countdown to the next food break, shown above every screen.
/// Tap to expand, drag to move.
///
/// When a break starts it turns solid green and nags like the routine pill:
/// speaks "Lunch time… Please acknowledge." every 8 seconds until tapped,
/// marked, or snoozed.
struct FoodPill: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [FoodEntry]
    @Query private var breaks: [FoodBreak]

    @AppStorage(FoodSettings.showPillKey) private var showPill = true
    @AppStorage(FoodUrge.startedAtKey) private var urgeStarted = 0.0
    @AppStorage(FoodSettings.pillXKey) private var pillX: Double = 0.5
    @AppStorage(FoodSettings.pillYKey) private var pillY: Double = 0.84
    @AppStorage(FoodSettings.lastSnoozeKey) private var lastSnooze = 20

    @State private var now = Date()
    @State private var expanded = false
    @State private var dragOffset: CGSize = .zero
    @State private var pendingAck: FoodSlot?
    @State private var lastSpokenAt: Date?

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        if showPill && !breaks.isEmpty {
            GeometryReader { geo in
                pill
                    .fixedSize()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                        OverlayHitRegions.shared.set("foodPill", rect)
                    }
                    .position(
                        x: clamp(pillX * geo.size.width + dragOffset.width, 120, geo.size.width - 120),
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
                    OverlayHitRegions.shared.set("foodPill", nil)
                    stopNag()
                }
        }
    }

    // MARK: Pill

    @ViewBuilder
    private var pill: some View {
        let due = FoodRules.dueSlot(at: now, entries: entries, breaks: breaks)
        let next = FoodRules.nextSlot(after: now, entries: entries, breaks: breaks)
        let urge = FoodUrge.state(at: now)
        let nagging = pendingAck != nil
        let tint: Color = due != nil ? .green : (urgeStarted > 0 ? .orange : .teal)

        VStack(alignment: .leading, spacing: 6) {
            if let slot = pendingAck {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                    Text("\(slot.name) time").fontWeight(.semibold)
                }
                .font(.caption)
                Text(slot.food.isEmpty ? "Nothing planned" : slot.food).font(.caption2).lineLimit(2)
                Text("Tap to acknowledge").font(.caption2.bold())
                breakActions(slot, onDark: true)
            } else if urgeStarted > 0, case .waiting(let left) = urge {
                line(icon: "hourglass", title: "Craving · wait", value: FoodHomeView.countdown(left), detail: nil)
                cravingActions(next: next, waiting: true)
            } else if urgeStarted > 0, case .done = urge {
                line(icon: "questionmark.circle", title: "Still want it?", value: "", detail: nil)
                cravingActions(next: next, waiting: false)
            } else if let due {
                line(icon: due.icon, title: "\(due.name) time", value: "", detail: due.food.isEmpty ? "Nothing planned" : due.food)
                breakActions(due, onDark: false)
            } else if let next {
                line(icon: next.icon, title: next.name, value: "in " + FoodHomeView.countdown(Int(next.time.timeIntervalSince(now))),
                     detail: next.food.isEmpty ? "Not planned" : next.food)
                if next.isSnoozed {
                    Text("Snoozed from \(next.plannedTime.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if expanded {
                    snoozeRow(next, onDark: false)
                    idleActions
                }
            } else {
                line(icon: "fork.knife", title: "No more breaks today", value: "", detail: nil)
                if expanded { idleActions }
            }
        }
        .foregroundStyle(nagging ? Color.white : tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 300, alignment: .leading)
        .background {
            if nagging {
                RoundedRectangle(cornerRadius: 14).fill(Color.green)
            } else {
                RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.6), lineWidth: due != nil ? 2 : 1))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            if let slot = pendingAck {
                FoodRules.acknowledge(slot)
                stopNag()
            } else {
                withAnimation(.snappy) { expanded.toggle() }
            }
        }
        .animation(.snappy, value: nagging)
    }

    private func line(icon: String, title: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).fontWeight(.semibold).lineLimit(1)
                if !value.isEmpty {
                    Text(value).monospacedDigit().fontWeight(.semibold).contentTransition(.numericText())
                }
            }
            .font(.caption)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.primary).lineLimit(expanded ? 3 : 1)
            }
        }
    }

    // MARK: Actions

    /// For a break that has started: mark it, or snooze it.
    private func breakActions(_ slot: FoodSlot, onDark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !slot.food.isEmpty { small("Ate it", onDark ? .white : .green) { mark(slot, .eaten) } }
                small("Other", onDark ? .white : .red) { swap(slot) }
                small("Skip", onDark ? .white : .gray) { mark(slot, .skipped) }
            }
            snoozeRow(slot, onDark: onDark)
        }
    }

    private func cravingActions(next: FoodSlot?, waiting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if waiting, let next {
                Text("Next food: \(next.name) at \(next.time.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                small("Resisted", .green) { FoodUrge.finish(resisted: true, context: modelContext) }
                small("I ate", .red) {
                    let trigger = FoodUrge.trigger
                    FoodUrge.finish(resisted: false, context: modelContext)
                    presentLog(.unplanned(day: Date().startOfDay, trigger: trigger))
                }
                small("Cancel", .gray) { FoodUrge.cancel() }
            }
        }
    }

    private var idleActions: some View {
        HStack(spacing: 6) {
            small("Craving", .orange) { FoodUrge.start() }
            small("+ Unplanned", .red) { presentLog(.unplanned(day: Date().startOfDay, trigger: "")) }
            small("✕", .gray) {
                expanded = false
                showPill = false
            }
            small("Open", .teal) {
                expanded = false
                FoodPresenter.present { close in
                    NavigationStack {
                        FoodHomeView()
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done", action: close) } }
                    }
                }
            }
        }
    }

    /// 💤 5m · 10m · last custom · Custom.
    private func snoozeRow(_ slot: FoodSlot, onDark: Bool) -> some View {
        let quick = Array(Set([5, 10, lastSnooze])).sorted()
        return HStack(spacing: 6) {
            Image(systemName: "zzz").font(.caption2)
            ForEach(quick, id: \.self) { minutes in
                small("\(minutes)m", onDark ? .white : .gray) { snooze(slot, minutes) }
            }
            small("Custom", onDark ? .white : .gray) {
                expanded = false
                let from = max(slot.time, Date())
                FoodPresenter.present { close in
                    NavigationStack {
                        RoutineSnoozeSheet(stepName: slot.name, from: from, initial: lastSnooze) { minutes in
                            lastSnooze = minutes
                            snooze(slot, minutes)
                            close()
                        } onCancel: { close() }
                    }
                }
            }
        }
        .accessibilityLabel("Snooze \(slot.name)")
    }

    private func small(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption2.bold())
            .buttonStyle(.bordered)
            .tint(color)
            .controlSize(.small)
    }

    private func mark(_ slot: FoodSlot, _ status: FoodEntryStatus) {
        FoodRules.mark(slot, status, day: slot.time.startOfDay, breaks: breaks, context: modelContext)
        stopNag()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func snooze(_ slot: FoodSlot, _ minutes: Int) {
        FoodRules.snooze(slot, minutes: minutes, day: slot.plannedTime.startOfDay, breaks: breaks, context: modelContext)
        stopNag()
        expanded = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func swap(_ slot: FoodSlot) {
        FoodRules.acknowledge(slot)
        stopNag()
        let day = slot.plannedTime.startOfDay
        let entry = slot.entry ?? FoodRules.materialize(day, breaks: breaks, context: modelContext)
            .first { $0.breakID == slot.id }
        if let entry { presentLog(.swap(entry)) }
    }

    private func presentLog(_ mode: FoodLogSheet.Mode) {
        expanded = false
        FoodPresenter.present { close in
            NavigationStack { FoodLogSheet(mode: mode, onClose: close) }
        }
    }

    // MARK: Acknowledgment nag

    private func tick() {
        let date = Date()
        let slot = FoodRules.needingAcknowledgment(at: date, entries: entries, breaks: breaks)

        if let slot, pendingAck == nil {
            pendingAck = slot
            expanded = false
            lastSpokenAt = nil
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else if slot == nil, pendingAck != nil {
            stopNag()
            return
        }

        guard let current = pendingAck else { return }
        if lastSpokenAt.map({ date.timeIntervalSince($0) >= 8 }) ?? true {
            lastSpokenAt = date
            let food = current.food.isEmpty ? "" : " \(current.food)."
            SpeechManager.shared.speak("\(current.name) time.\(food) Please acknowledge.")
        }
    }

    private func stopNag() {
        guard pendingAck != nil else { return }
        pendingAck = nil
        lastSpokenAt = nil
        SpeechManager.shared.stopSpeaking()
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), max(lo, hi))
    }
}

/// Shows a sheet over whatever the app is showing, from the floating window
/// (which can't present sheets itself, since it only takes touches on the pills).
@MainActor
enum FoodPresenter {
    /// Returns false when there's no window to present on yet.
    @discardableResult
    static func present<V: View>(_ make: (_ close: @escaping () -> Void) -> V) -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let windows = scene?.windows.filter { !($0 is FloatingButtonsWindow) } ?? []
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first,
              var top = window.rootViewController else { return false }
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }

        let host = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
        let close: () -> Void = { [weak host] in host?.dismiss(animated: true) }
        host.rootView = AnyView(make(close).modelContainer(FocusFlowSwiftApp.sharedContainer))
        top.present(host, animated: true)
        return true
    }
}
