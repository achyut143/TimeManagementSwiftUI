import SwiftUI
import SwiftData

/// Full-screen Tabata timer.
struct TabataRunView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var timer: TabataTimer
    @State private var showStopConfirm = false
    @State private var result: (completed: Bool, seconds: Int)?
    @State private var images: [UUID: UIImage] = [:]

    let workoutID: UUID
    let name: String
    /// Called with true when the workout completed, false when stopped.
    let onExit: (Bool) -> Void

    init(workout: TabataWorkout, onExit: @escaping (Bool) -> Void) {
        workoutID = workout.id
        name = workout.name
        self.onExit = onExit
        _timer = State(initialValue: TabataTimer(draft: workout.draft))
    }

    var body: some View {
        Group {
            if let result {
                WorkoutFinishedView(title: name, completed: result.completed, durationSeconds: result.seconds) {
                    onExit(result.completed)
                } details: {
                    EmptyView()
                }
            } else {
                runner
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            images = WorkoutPictureStore.images(timer.intervals.map(\.imageID), context: modelContext)
            timer.onFinish = { finish(completed: true) }
            timer.start()
        }
        .onDisappear { timer.stop() }
    }

    private var runner: some View {
        let interval = timer.current
        // Work shows this cycle's picture; prepare and rest show the next one.
        let image = interval?.imageID.flatMap { images[$0] }
        return ZStack {
            phaseColor(interval?.phase).ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: interval?.phase)

            VStack(spacing: 16) {
                HStack {
                    Text(name).font(.headline).lineLimit(1)
                    Spacer()
                    WorkoutSoundToggles()
                }

                if let interval, interval.partCount > 1 {
                    Text("PART \(interval.part + 1) OF \(interval.partCount) · \(interval.partName)")
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.2), in: Capsule())
                }

                // Cycle and round in big text, readable from across the room.
                HStack(alignment: .top) {
                    statBlock("CYCLE", "\(interval?.cycle ?? 0)/\(interval?.cycles ?? 0)")
                    Spacer()
                    statBlock("ROUND", "\(interval?.round ?? 0)/\(interval?.rounds ?? 0)")
                }

                Text("Total left \(WorkoutFormat.clock(timer.totalRemaining))")
                    .font(.headline)
                    .monospacedDigit()
                    .opacity(0.85)

                Spacer()

                Text(phaseTitle(interval))
                    .font(.title3.weight(.semibold))
                    .textCase(.uppercase)
                    .opacity(0.85)
                Text(interval?.phase == .work ? interval?.exercise ?? "" : interval?.phase.title ?? "")
                    .font(.system(size: 46, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)

                WorkoutRunImage(image: image, maxHeight: 180)
                    .opacity(interval?.phase == .work ? 1 : 0.75)

                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: timer.progress)
                    Text(WorkoutFormat.clock(Int(timer.remaining.rounded(.up))))
                        .font(.system(size: image == nil ? 72 : 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: image == nil ? 280 : 190, maxHeight: image == nil ? 280 : 190)

                if let next = timer.nextExercise {
                    Text("Next: \(next)")
                        .font(.title3.weight(.medium))
                }
                if timer.isPaused {
                    Text("Paused").font(.headline).padding(.horizontal, 12).padding(.vertical, 4)
                        .background(.black.opacity(0.25), in: Capsule())
                }

                Spacer()

                HStack(spacing: 28) {
                    controlButton("backward.end.fill", label: "Back") { timer.goBack() }
                    controlButton(timer.isPaused ? "play.fill" : "pause.fill", label: timer.isPaused ? "Resume" : "Pause", large: true) {
                        timer.togglePause()
                    }
                    controlButton("forward.end.fill", label: "Skip") { timer.skipForward() }
                    controlButton("stop.fill", label: "Stop") { showStopConfirm = true }
                }
            }
            .padding()
            .foregroundStyle(.white)
        }
        .confirmationDialog("Stop this workout?", isPresented: $showStopConfirm, titleVisibility: .visible) {
            Button("Stop workout", role: .destructive) {
                timer.stop()
                finish(completed: false)
            }
        }
    }

    private func finish(completed: Bool) {
        guard result == nil else { return }
        let seconds = Int(Date().timeIntervalSince(timer.startedAt ?? Date()))
        WorkoutRecorder.record(kind: .tabata, workoutID: workoutID, name: name, startedAt: timer.startedAt,
                               completed: completed, context: modelContext)
        result = (completed, seconds)
    }

    private func phaseTitle(_ interval: TabataInterval?) -> String {
        guard let interval else { return "" }
        switch interval.phase {
        case .prepare: return "Get ready"
        case .work: return "Work"
        case .rest: return interval.isRoundBreak ? "Round \(interval.round) done" : "Rest"
        }
    }

    private func phaseColor(_ phase: TabataPhase?) -> Color {
        switch phase {
        case .prepare: return Color(red: 0.95, green: 0.6, blue: 0.1)
        case .work: return Color(red: 0.86, green: 0.2, blue: 0.24)
        case .rest: return Color(red: 0.16, green: 0.5, blue: 0.85)
        case nil: return .gray
        }
    }

    private func statBlock(_ title: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.subheadline.weight(.semibold)).opacity(0.85)
            Text(value)
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(_ icon: String, label: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(large ? .title : .title3)
                .frame(width: large ? 76 : 56, height: large ? 76 : 56)
                .background(.white.opacity(large ? 0.3 : 0.18), in: Circle())
        }
        .accessibilityLabel(label)
    }
}
