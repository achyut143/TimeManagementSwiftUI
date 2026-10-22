import SwiftUI
import SwiftData

/// Rep workout without a timer: tap Next when each exercise is done.
struct RepRunView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("workout.weightUnit") private var weightUnit = "lb"

    let workoutID: UUID
    let name: String
    let steps: [RepStep]
    let restSeconds: Int
    let onExit: (Bool) -> Void

    @State private var index = 0
    @State private var actualReps: [Int]
    @State private var actualWeights: [Double?]
    @State private var startedAt: Date?
    @State private var restEnd: Date?
    @State private var now = Date()
    @State private var lastRestBeep: Int?
    @State private var showStopConfirm = false
    @State private var images: [UUID: UIImage] = [:]
    /// What was done last time for each step, from history.
    @State private var lastTime: [RepLogEntry?] = []
    @State private var result: (completed: Bool, seconds: Int, log: [RepLogEntry])?

    private let audio = WorkoutAudio.shared
    private let clock = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    init(workout: RepWorkout, onExit: @escaping (Bool) -> Void) {
        workoutID = workout.id
        name = workout.name
        let steps = RepStep.steps(for: workout.sets)
        self.steps = steps
        restSeconds = workout.restBetweenSetsSeconds
        self.onExit = onExit
        _actualReps = State(initialValue: steps.map(\.exercise.reps))
        _actualWeights = State(initialValue: steps.map(\.exercise.weight))
    }

    var body: some View {
        Group {
            if let result {
                WorkoutFinishedView(title: name, completed: result.completed, durationSeconds: result.seconds) {
                    onExit(result.completed)
                } details: {
                    RepLogSummary(log: result.log, unit: weightUnit)
                }
            } else if steps.isEmpty {
                ContentUnavailableView("No exercises", systemImage: "dumbbell",
                                       description: Text("Add exercises to this workout first."))
                    .overlay(alignment: .topTrailing) {
                        Button("Close") { onExit(false) }.padding()
                    }
            } else {
                runner
            }
        }
        .onAppear(perform: start)
        .onDisappear { if result == nil { audio.end() } }
        .onReceive(clock) { tick($0) }
    }

    // MARK: Screen

    private var step: RepStep { steps[min(index, steps.count - 1)] }
    private var isLast: Bool { index == steps.count - 1 }
    private var restRemaining: Int? {
        guard let restEnd else { return nil }
        return max(0, Int(restEnd.timeIntervalSince(now).rounded(.up)))
    }

    private var runner: some View {
        VStack(spacing: 20) {
            HStack {
                Button { showStopConfirm = true } label: {
                    Image(systemName: "xmark").font(.title3.weight(.semibold))
                }
                .accessibilityLabel("Stop")
                Text(name).font(.headline).lineLimit(1)
                Spacer()
                WorkoutSoundToggles(showBeeps: restSeconds > 0)
            }

            ProgressView(value: Double(index), total: Double(max(1, steps.count)))

            Text(step.position)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let rest = restRemaining {
                restPanel(rest)
            } else {
                exercisePanel
            }

            Spacer()

            HStack(spacing: 16) {
                Button { goBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .disabled(index == 0 && restEnd == nil)
                .frame(maxWidth: 120)

                Button { next() } label: {
                    Text(restEnd != nil ? "Skip rest" : (isLast ? "Finish" : "Next"))
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .confirmationDialog("Stop this workout?", isPresented: $showStopConfirm, titleVisibility: .visible) {
            Button("Stop workout", role: .destructive) { finish(completed: false) }
        }
    }

    private var exercisePanel: some View {
        VStack(spacing: 16) {
            WorkoutRunImage(image: step.exercise.imageID.flatMap { images[$0] }, maxHeight: 180)

            Text(step.exercise.name)
                .font(.system(size: 40, weight: .heavy))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(2)

            HStack(alignment: .firstTextBaseline, spacing: 28) {
                VStack {
                    Text("\(step.exercise.reps)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                    Text("reps").foregroundStyle(.secondary)
                }
                if let w = WorkoutFormat.weight(step.exercise.weight, unit: weightUnit) {
                    VStack {
                        Text(w).font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("weight").foregroundStyle(.secondary)
                    }
                }
            }

            if !step.exercise.note.isEmpty {
                Text(step.exercise.note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // What was actually done; the saved plan stays unchanged.
            GroupBox("What I did") {
                if let last = lastTime.indices.contains(index) ? lastTime[index] : nil {
                    HStack {
                        Label("Last time: \(performance(last.actualReps, last.actualWeight))", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                HStack {
                    Stepper("\(actualReps[index]) reps", value: $actualReps[index], in: 0...500)
                }
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("–", text: WeightText.binding($actualWeights[index]))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text(weightUnit).foregroundStyle(.secondary)
                }
                // Quick progressive-overload bump.
                HStack(spacing: 10) {
                    Spacer()
                    Button("−\(stepText)") { bumpWeight(-weightStep) }
                    Button("+\(stepText)") { bumpWeight(weightStep) }
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
            }
        }
    }

    private var weightStep: Double { weightUnit == "lb" ? 5 : 2.5 }
    private var stepText: String { weightUnit == "lb" ? "5 lb" : "2.5 kg" }

    private func bumpWeight(_ delta: Double) {
        let current = actualWeights[index] ?? 0
        let next = max(0, current + delta)
        actualWeights[index] = next == 0 ? nil : next
    }

    private func performance(_ reps: Int, _ weight: Double?) -> String {
        if let w = WorkoutFormat.weight(weight, unit: weightUnit) { return "\(reps) × \(w)" }
        return "\(reps) reps"
    }

    private func restPanel(_ seconds: Int) -> some View {
        VStack(spacing: 12) {
            Text("Rest").font(.title2.weight(.semibold)).foregroundStyle(.blue)
            Text(WorkoutFormat.clock(seconds))
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .monospacedDigit()
            WorkoutRunImage(image: step.exercise.imageID.flatMap { images[$0] }, maxHeight: 140)
            Text("Next: \(step.exercise.name), \(step.exercise.reps) reps")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Actions

    private func start() {
        guard startedAt == nil, !steps.isEmpty else { return }
        startedAt = Date()
        images = WorkoutPictureStore.images(steps.map(\.exercise.imageID), context: modelContext)
        // Suggest last time's weight: start each exercise from it instead of the plan.
        let lookup = RepHistoryLookup(workoutID: workoutID, context: modelContext)
        lastTime = steps.map { lookup.last(name: $0.exercise.name, setIndex: $0.setIndex, round: $0.round) }
        for i in steps.indices {
            if let weight = lastTime[i]?.actualWeight, weight > 0 {
                actualWeights[i] = weight
            }
        }
        UIApplication.shared.isIdleTimerDisabled = true
        audio.begin()
        audio.speak(cue(for: steps[0]))
    }

    private func cue(for step: RepStep) -> String {
        "\(step.exercise.name), \(step.exercise.reps) reps."
    }

    private func next() {
        hideKeyboard()
        if restEnd != nil {
            endRest()
            return
        }
        guard !isLast else {
            finish(completed: true)
            return
        }
        index += 1
        // Rest after each round of a set, before the next round or set starts.
        if restSeconds > 0 && step.exerciseIndex == 0 {
            restEnd = Date().addingTimeInterval(Double(restSeconds))
            now = Date()
            lastRestBeep = nil
            audio.speak("Rest. Next: \(cue(for: step))")
        } else {
            audio.speak(cue(for: step))
        }
    }

    private func goBack() {
        hideKeyboard()
        if restEnd != nil {
            restEnd = nil
        }
        guard index > 0 else { return }
        index -= 1
        audio.speak(cue(for: step))
    }

    private func endRest() {
        restEnd = nil
        audio.beep(final: true)
        audio.speak(cue(for: step))
    }

    private func tick(_ date: Date) {
        audio.ensureRunning()
        guard restEnd != nil else { return }
        now = date
        guard let left = restRemaining else { return }
        if (1...3).contains(left), left != lastRestBeep {
            lastRestBeep = left
            audio.beep()
        }
        if left == 0 { endRest() }
    }

    private func finish(completed: Bool) {
        guard result == nil else { return }
        restEnd = nil
        // Log what was done: everything when completed, earlier exercises when stopped.
        let doneCount = completed ? steps.count : index
        let log = (0..<doneCount).map { i in
            RepLogEntry(name: steps[i].exercise.name, setIndex: steps[i].setIndex, round: steps[i].round,
                        plannedReps: steps[i].exercise.reps, plannedWeight: steps[i].exercise.weight,
                        actualReps: actualReps[i], actualWeight: actualWeights[i])
        }
        WorkoutRecorder.record(kind: .reps, workoutID: workoutID, name: name, startedAt: startedAt,
                               completed: completed, log: log, context: modelContext)
        if completed {
            audio.speak("Workout complete.")
            audio.endSoon()
        } else {
            audio.end()
        }
        let seconds = Int(Date().timeIntervalSince(startedAt ?? Date()))
        result = (completed, seconds, log)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Planned vs actual table, used on the finish screen and in history.
struct RepLogSummary: View {
    let log: [RepLogEntry]
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Planned vs actual").font(.headline)
            ForEach(log) { entry in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.subheadline.weight(.medium))
                        Text("Set \(entry.setIndex + 1), round \(entry.round)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(line(entry.actualReps, entry.actualWeight))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(differs(entry) ? .orange : .primary)
                        Text("plan " + line(entry.plannedReps, entry.plannedWeight))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
        }
    }

    private func line(_ reps: Int, _ weight: Double?) -> String {
        if let w = WorkoutFormat.weight(weight, unit: unit) { return "\(reps) × \(w)" }
        return "\(reps) reps"
    }

    private func differs(_ e: RepLogEntry) -> Bool {
        e.actualReps != e.plannedReps || (e.actualWeight ?? 0) != (e.plannedWeight ?? 0)
    }
}
