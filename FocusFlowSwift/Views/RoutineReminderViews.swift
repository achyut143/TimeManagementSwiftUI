import SwiftUI
import UIKit

extension RoutineStep {
    static let palette: [String: Color] = [
        "teal": .teal, "orange": .orange, "purple": .purple, "blue": .blue,
        "indigo": .indigo, "green": .green, "mint": .mint, "cyan": .cyan,
        "brown": .brown, "pink": .pink, "red": .red, "yellow": .yellow,
    ]

    var color: Color { Self.palette[colorName] ?? .accentColor }
}

// MARK: - Settings

struct RoutineReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RoutineReminder.enabledKey) private var enabled = false
    @AppStorage(RoutineReminder.stepsKey) private var stepsRaw = ""

    @AppStorage(SavedRoutinePreset.storageKey) private var savedPresetsRaw = ""

    @State private var editingStep: RoutineStep?
    @State private var showResetConfirm = false
    @State private var showSavePreset = false
    @State private var newPresetName = ""
    @State private var presetToOverwrite: SavedRoutinePreset?

    private var savedPresets: [SavedRoutinePreset] { SavedRoutinePreset.load(savedPresetsRaw) }

    // `stepsRaw` is read so the list refreshes; the source of truth is
    // RoutineReminder.steps (which also seeds the defaults on first use).
    private var steps: [RoutineStep] {
        _ = stepsRaw
        return RoutineReminder.steps
    }

    var body: some View {
        List {
            Section {
                Toggle("Routine reminder", isOn: Binding(
                    get: { enabled },
                    set: { RoutineReminder.setEnabled($0) }
                ))
            } footer: {
                Text("Runs the steps below in order, then repeats. A floating timer shows the current step, and steps with a bell ask you to acknowledge when they start.")
            }

            Section {
                ForEach(steps) { step in
                    Button {
                        editingStep = step
                    } label: {
                        stepRow(step)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    var list = steps
                    list.remove(atOffsets: offsets)
                    save(list)
                }
                .onMove { from, to in
                    var list = steps
                    list.move(fromOffsets: from, toOffset: to)
                    save(list)
                }

                Menu {
                    ForEach(RoutineStep.templates, id: \.name) { template in
                        Button {
                            save(steps + [RoutineStep.from(template: template)])
                        } label: {
                            Label("\(template.name) · \(template.minutes) min", systemImage: template.icon)
                        }
                    }
                } label: {
                    Label("Add step", systemImage: "plus.circle.fill")
                }
            } header: {
                HStack {
                    Text("Sequence")
                    Spacer()
                    EditButton()
                        .font(.caption)
                        .textCase(nil)
                }
            } footer: {
                Text(summary)
            }

            Section {
                Button {
                    newPresetName = ""
                    showSavePreset = true
                } label: {
                    Label("Save current as preset…", systemImage: "square.and.arrow.down")
                }

                ForEach(savedPresets) { preset in
                    Button {
                        save(preset.freshSteps)
                    } label: {
                        presetRow(name: preset.name, detail: preset.summary, icon: "person.crop.circle")
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    var list = savedPresets
                    list.remove(atOffsets: offsets)
                    savedPresetsRaw = SavedRoutinePreset.encode(list)
                }

                ForEach(RoutinePreset.all) { preset in
                    Button {
                        save(preset.steps)
                    } label: {
                        presetRow(name: preset.name,
                                  detail: preset.stepNames.map { "\($0.1)" }.joined(separator: "/") + " min",
                                  icon: "sparkles")
                    }
                    .buttonStyle(.plain)
                }

                Button("Reset to default", role: .destructive) {
                    showResetConfirm = true
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("Tap a preset to use it. Swipe left on one you saved to delete it.")
            }

            if enabled {
                Section {
                    Button("Restart from first step") {
                        RoutineReminder.restart()
                    }
                }
            }
        }
        .navigationTitle("Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $editingStep) { step in
            NavigationStack {
                RoutineStepEditor(step: step) { updated in
                    save(steps.map { $0.id == updated.id ? updated : $0 })
                }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Reset to Sit 30 · Stand 30 · Stretch 5?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { save(RoutinePreset.defaultSteps) }
        }
        .alert("Save Preset", isPresented: $showSavePreset) {
            TextField("Name", text: $newPresetName)
            Button("Cancel", role: .cancel) { }
            Button("Save") { savePreset() }
        } message: {
            Text(summary)
        }
        .alert("Replace \"\(presetToOverwrite?.name ?? "")\"?",
               isPresented: Binding(get: { presetToOverwrite != nil }, set: { if !$0 { presetToOverwrite = nil } })) {
            Button("Cancel", role: .cancel) { presetToOverwrite = nil }
            Button("Replace", role: .destructive) {
                if let existing = presetToOverwrite {
                    storePreset(name: existing.name, replacing: existing.id)
                }
                presetToOverwrite = nil
            }
        } message: {
            Text("You already have a preset with this name.")
        }
    }

    private func presetRow(name: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text(name)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? steps.map(\.name).joined(separator: " · ") : name
        if let existing = savedPresets.first(where: { $0.name.caseInsensitiveCompare(finalName) == .orderedSame }) {
            // Ask after this alert has closed.
            DispatchQueue.main.async { presetToOverwrite = existing }
            return
        }
        storePreset(name: finalName, replacing: nil)
    }

    private func storePreset(name: String, replacing id: UUID?) {
        var list = savedPresets
        let preset = SavedRoutinePreset(id: id ?? UUID(), name: name, steps: steps)
        if let id, let i = list.firstIndex(where: { $0.id == id }) {
            list[i] = preset
        } else {
            list.append(preset)
        }
        savedPresetsRaw = SavedRoutinePreset.encode(list)
    }

    private func stepRow(_ step: RoutineStep) -> some View {
        HStack(spacing: 12) {
            Image(systemName: step.icon)
                .foregroundStyle(step.color)
                .frame(width: 28)
            Text(step.name)
            if step.remind {
                Image(systemName: "bell.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(step.minutes) min")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var summary: String {
        steps.map { "\($0.name) \($0.minutes)" }.joined(separator: " → ") + " min, then repeat."
    }

    /// Saves through RoutineReminder so the current step keeps going instead
    /// of jumping, and notifications move to the new times.
    private func save(_ list: [RoutineStep]) {
        RoutineReminder.updateSteps(list)
        // updateSteps writes to UserDefaults; mirror into @AppStorage so the
        // list refreshes immediately.
        stepsRaw = RoutineReminder.encode(RoutineReminder.steps)
    }
}

struct RoutineStepEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var step: RoutineStep
    let onSave: (RoutineStep) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $step.name)
                Stepper("\(step.minutes) min", value: $step.minutes, in: 1...240)
                Toggle("Remind & ask to acknowledge", isOn: $step.remind)
            } footer: {
                Text("Turn off for steps like Work, where you don't need a nudge when they start.")
            }

            Section("Look") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(RoutineStep.templates, id: \.name) { template in
                        let selected = template.icon == step.icon
                        Button {
                            step.icon = template.icon
                            step.colorName = template.colorName
                        } label: {
                            Image(systemName: template.icon)
                                .font(.title3)
                                .foregroundStyle(template.color)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(template.color.opacity(selected ? 0.25 : 0.08))
                                )
                                .overlay(Circle().stroke(selected ? template.color : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(template.name)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Edit Step")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    step.name = step.name.trimmingCharacters(in: .whitespaces)
                    if step.name.isEmpty { step.name = "Step" }
                    onSave(step)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Floating pill

/// Small draggable timer shown in the floating overlay window — only while
/// the routine is on. Tap for options, drag to move.
///
/// When a step with "remind" starts, it nags like the calendar-task timer in
/// Daily Notes: speaks "Stretch time. Please acknowledge." every 8 seconds
/// and shows a "Tap to acknowledge" state until tapped. Acknowledgment is
/// saved in AcknowledgmentStore, so reopening the app doesn't re-nag.
struct RoutineTimerPill: View {
    @AppStorage(RoutineReminder.enabledKey) private var enabled = false
    // Read so the pill re-renders when the sequence changes.
    @AppStorage(RoutineReminder.stepsKey) private var stepsRaw = ""
    @AppStorage(RoutineReminder.startedAtKey) private var startedAt: Double = 0
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
                pill(status: RoutineReminder.status(at: now))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                        OverlayHitRegions.shared.set("routinePill", rect)
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
                    OverlayHitRegions.shared.set("routinePill", nil)
                    stopNag()
                }
        }
    }

    private func pill(status: RoutineReminder.Status) -> some View {
        let step = status.step
        let tint = step.color
        return VStack(spacing: 6) {
            if pendingAck {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                    Text(RoutineReminder.title(for: step))
                        .fontWeight(.semibold)
                }
                .font(.caption)
                Text("Tap to acknowledge · \(format(status.secondsRemaining))")
                    .font(.caption2.monospacedDigit())
            } else {
                HStack(spacing: 6) {
                    Image(systemName: step.icon)
                    Text(step.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(format(status.secondsRemaining))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                }
                .font(.caption)

                if expanded {
                    let next = RoutineReminder.nextStep(after: status.index)
                    Text("Next: \(next.name) \(next.minutes) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("\(next.name) now") {
                            RoutineReminder.skipToNextStep()
                            expanded = false
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .tint(next.color)

                        Button {
                            stopNag()
                            RoutineReminder.setEnabled(false)
                            expanded = false
                        } label: {
                            Image(systemName: "power")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityLabel("Turn off routine reminder")
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
        .animation(.snappy, value: step.id)
    }

    // MARK: Acknowledgment nag

    private func tick() {
        let date = Date()
        let needsAck = RoutineReminder.needsAcknowledgment(at: date)

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
            let step = RoutineReminder.status(at: date).step
            SpeechManager.shared.speak("\(RoutineReminder.title(for: step)). Please acknowledge.")
        }
    }

    private func acknowledge() {
        RoutineReminder.acknowledgeCurrentStep()
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
