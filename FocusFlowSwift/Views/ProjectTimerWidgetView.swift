import SwiftUI
import SwiftData

/// Stopwatch/countdown control for a project's `ProjectTimer`.
///
/// Pass `project` to scope the widget to one project (used on that project's
/// own detail screen). Leave it `nil` for "global" mode, which shows
/// whichever project currently has a running or paused timer and lets the
/// user pick a project to start one (used from Daily Notes, which has no
/// project context of its own).
///
/// The timer is a SwiftData model, so starting/pausing it from one place is
/// immediately reflected wherever else this widget is shown — including its
/// live elapsed time, since both instances observe the same underlying data.
/// The app pauses any running timer automatically when backgrounded (see
/// `MigrationWrapper` in FocusFlowSwiftApp.swift).
struct ProjectTimerWidgetView: View {
    @Environment(\.modelContext) private var modelContext

    var project: Project?
    var isDark: Bool = false

    @Query(sort: \Project.createdAt, order: .reverse) private var allProjects: [Project]
    @Query private var allTimers: [ProjectTimer]

    @State private var showProjectPicker = false
    @State private var showLogSheet = false
    @State private var showCountdownSetup = false
    @State private var countdownMinutesText = "25"
    @State private var pendingProjectForStart: Project?

    // The timer actually being displayed/controlled right now.
    private var activeTimer: ProjectTimer? {
        if let project {
            return project.timer
        }
        if let running = allTimers.first(where: { $0.isRunning }) {
            return running
        }
        return allTimers.filter { $0.accumulatedSeconds > 0 }.max { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Group {
            if let timer = activeTimer, let owner = timer.project {
                runningCard(timer: timer, project: owner)
            } else {
                startCard
            }
        }
        .sheet(isPresented: $showProjectPicker) {
            NavigationStack { projectPickerList }
        }
        .sheet(isPresented: $showLogSheet) {
            if let timer = activeTimer, let owner = timer.project {
                AddTimeEntryView(project: owner, prefillMinutes: timer.elapsedSeconds / 60) {
                    timer.reset()
                    try? modelContext.save()
                }
            }
        }
        .alert("Set Countdown", isPresented: $showCountdownSetup) {
            TextField("Minutes", text: $countdownMinutesText)
                .keyboardType(.numberPad)
            Button("Start") { startCountdown() }
            Button("Cancel", role: .cancel) { pendingProjectForStart = nil }
        } message: {
            Text("How many minutes?")
        }
    }

    // MARK: - Idle state (no active timer to show)

    @ViewBuilder
    private var startCard: some View {
        if let project {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .foregroundStyle(isDark ? .cyan : .blue)
                Text("No timer running")
                    .font(.subheadline)
                    .foregroundStyle(isDark ? .white.opacity(0.6) : .secondary)
                Spacer()
                Button {
                    beginStopwatch(for: project)
                } label: {
                    Label("Stopwatch", systemImage: "play.fill")
                }
                Button {
                    pendingProjectForStart = project
                    showCountdownSetup = true
                } label: {
                    Label("Timer", systemImage: "hourglass")
                }
            }
            .buttonStyle(.bordered)
            .tint(isDark ? .cyan : .accentColor)
        } else {
            Button {
                showProjectPicker = true
            } label: {
                Label("Start a Project Timer", systemImage: "timer")
            }
            .buttonStyle(.bordered)
            .tint(isDark ? .cyan : .accentColor)
        }
    }

    private var projectPickerList: some View {
        List(allProjects) { p in
            HStack {
                Text(p.name)
                Spacer()
                Button {
                    showProjectPicker = false
                    beginStopwatch(for: p)
                } label: {
                    Image(systemName: "stopwatch")
                }
                .buttonStyle(.borderless)
                Button {
                    showProjectPicker = false
                    pendingProjectForStart = p
                    showCountdownSetup = true
                } label: {
                    Image(systemName: "hourglass")
                }
                .buttonStyle(.borderless)
            }
        }
        .overlay {
            if allProjects.isEmpty {
                Text("No projects yet")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Start Timer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showProjectPicker = false }
            }
        }
    }

    // MARK: - Active/paused state

    @ViewBuilder
    private func runningCard(timer: ProjectTimer, project: Project) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isDark ? .white : .primary)
                Spacer()
                if timer.isRunning {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Running").font(.caption2).foregroundStyle(.green)
                    }
                }
            }

            // Mode stays switchable at any time — including mid-session — so
            // finishing (or even starting) in one mode never locks the other
            // one out. Switching preserves whatever time is already banked.
            HStack(spacing: 8) {
                modeChip(title: "Stopwatch", systemImage: "stopwatch", isSelected: !timer.isCountdown) {
                    switchToStopwatch(timer)
                }
                modeChip(title: "Countdown", systemImage: "hourglass", isSelected: timer.isCountdown) {
                    pendingProjectForStart = project
                    if let target = timer.targetMinutes {
                        countdownMinutesText = String(Int(target))
                    }
                    showCountdownSetup = true
                }
            }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(formattedTime(for: timer))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(isDark ? .white : .primary)
                    .contentTransition(.numericText())
            }

            if timer.isCountdown, let remaining = timer.remainingSeconds, remaining <= 0 {
                Text("Target reached — still counting")
                    .font(.caption2)
                    .foregroundStyle(isDark ? Color.red.opacity(0.85) : .red)
            }

            HStack(spacing: 12) {
                Button {
                    toggleRunPause(timer)
                } label: {
                    Label(runPauseLabel(for: timer), systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .tint(isDark ? .cyan : .accentColor)

                Button {
                    stopAndLog(timer)
                } label: {
                    Label("Stop & Log", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!timer.isRunning && timer.elapsedSeconds < 1)

                Spacer()
            }
        }
        .padding()
        .background(isDark ? Color.white.opacity(0.08) : Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func modeChip(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? (isDark ? Color.cyan.opacity(0.25) : Color.blue.opacity(0.2)) : (isDark ? Color.white.opacity(0.08) : Color.gray.opacity(0.12)))
                .foregroundStyle(isSelected ? (isDark ? Color.cyan : Color.blue) : (isDark ? Color.white.opacity(0.5) : Color.secondary))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func runPauseLabel(for timer: ProjectTimer) -> String {
        if timer.isRunning { return "Pause" }
        return timer.elapsedSeconds < 1 ? "Start" : "Resume"
    }

    // MARK: - Actions

    private func timerForProject(_ project: Project) -> ProjectTimer {
        if let existing = project.timer { return existing }
        let created = ProjectTimer(project: project)
        modelContext.insert(created)
        project.timer = created
        return created
    }

    private func pauseOtherTimers(except keep: ProjectTimer) {
        for t in allTimers where t !== keep && t.isRunning {
            t.pause()
        }
    }

    private func beginStopwatch(for project: Project) {
        let timer = timerForProject(project)
        pauseOtherTimers(except: timer)
        timer.isCountdown = false
        timer.targetMinutes = nil
        timer.start()
        try? modelContext.save()
    }

    // Also used to switch an existing (possibly mid-session) timer's mode —
    // never resets accumulated time, so switching modes never loses progress.
    private func startCountdown() {
        guard let project = pendingProjectForStart else { return }
        let minutes = Double(countdownMinutesText) ?? 25
        let timer = timerForProject(project)
        pauseOtherTimers(except: timer)
        timer.isCountdown = true
        timer.targetMinutes = max(minutes, 1)
        try? modelContext.save()
        pendingProjectForStart = nil
    }

    // Mode-switch counterpart to startCountdown(): flips an existing timer
    // back to stopwatch without touching whatever it has already banked.
    private func switchToStopwatch(_ timer: ProjectTimer) {
        timer.isCountdown = false
        timer.targetMinutes = nil
        try? modelContext.save()
    }

    private func toggleRunPause(_ timer: ProjectTimer) {
        if timer.isRunning {
            timer.pause()
        } else {
            pauseOtherTimers(except: timer)
            timer.start()
        }
        try? modelContext.save()
    }

    private func stopAndLog(_ timer: ProjectTimer) {
        timer.pause() // bank the final elapsed time so the log sheet sees a frozen value
        try? modelContext.save()
        showLogSheet = true
    }

    // MARK: - Formatting

    private func formattedTime(for timer: ProjectTimer) -> String {
        if timer.isCountdown, let remaining = timer.remainingSeconds, remaining > 0 {
            return Self.formatClock(remaining)
        }
        return Self.formatClock(timer.elapsedSeconds)
    }

    private static func formatClock(_ totalSeconds: Double) -> String {
        let total = Int(totalSeconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
