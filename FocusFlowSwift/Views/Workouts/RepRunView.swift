import SwiftUI
import SwiftData

/// Rep workout without a timer: tap Next when each exercise is done.
///
/// Progress is saved after every step, so the workout can be left
/// ("Pause & leave") and continued later, and it can be edited while it
/// runs: exercises already done keep their logged numbers.
struct RepRunView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("workout.weightUnit") private var weightUnit = "lb"

    let workout: RepWorkout
    let onExit: (Bool) -> Void

    @State private var steps: [RepStep] = []
    @State private var restSeconds = 0
    @State private var index = 0
    /// Steps finished so far, by RepStep.key.
    @State private var done: Set<String> = []
    /// Numbers entered for a step, by RepStep.key. Missing = suggested default.
    @State private var values: [String: PausedRepRun.Value] = [:]
    /// What was done last time for each step, by RepStep.key.
    @State private var lastTime: [String: RepLogEntry] = [:]
    @State private var images: [UUID: UIImage] = [:]

    @State private var firstStarted: Date?
    @State private var activeBefore: Double = 0
    @State private var segmentStart = Date()

    @State private var restEnd: Date?
    @State private var exerciseEnd: Date?
    @State private var now = Date()
    @State private var lastRestBeep: Int?
    @State private var lastExerciseBeep: Int?
    @State private var showStopConfirm = false
    @State private var editing = false
    @State private var didStart = false
    @State private var result: (completed: Bool, seconds: Int, log: [RepLogEntry], records: [(name: String, detail: String)])?

    private let audio = WorkoutAudio.shared
    private let clock = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    init(workout: RepWorkout, onExit: @escaping (Bool) -> Void) {
        self.workout = workout
        self.onExit = onExit
    }

    var body: some View {
        Group {
            if let result {
                WorkoutFinishedView(title: workout.name, completed: result.completed, durationSeconds: result.seconds) {
                    onExit(result.completed)
                } details: {
                    if !result.records.isEmpty {
                        PersonalRecordList(records: result.records)
                    }
                    RepLogSummary(log: result.log, unit: weightUnit)
                }
            } else if didStart && steps.isEmpty {
                ContentUnavailableView("No exercises", systemImage: "dumbbell",
                                       description: Text("Add exercises to this workout first."))
                    .overlay(alignment: .topTrailing) {
                        Button("Close") { onExit(false) }.padding()
                    }
            } else if !steps.isEmpty {
                runner
            }
        }
        .onAppear(perform: start)
        .onDisappear {
            if result == nil {
                saveProgress()
                audio.end()
            }
        }
        .onReceive(clock) { tick($0) }
        // Save when the app goes to the background, in case it gets closed.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if result == nil { saveProgress() }
        }
        .sheet(isPresented: $editing, onDismiss: rebuildAfterEdit) {
            RepWorkoutEditorView(workout: workout)
        }
    }

    // MARK: Screen

    private var step: RepStep { steps[min(index, steps.count - 1)] }
    private var isLast: Bool { index >= steps.count - 1 }
    private var restRemaining: Int? {
        guard let restEnd else { return nil }
        return max(0, Int(restEnd.timeIntervalSince(now).rounded(.up)))
    }
    private var exerciseRemaining: Int? {
        guard let exerciseEnd else { return nil }
        return max(0, Int(exerciseEnd.timeIntervalSince(now).rounded(.up)))
    }

    private var runner: some View {
        VStack(spacing: 20) {
            HStack {
                Menu {
                    Button("Pause & leave", systemImage: "pause.circle") { pauseAndLeave() }
                    Button("Edit workout", systemImage: "pencil") {
                        saveProgress()
                        restEnd = nil
                        exerciseEnd = nil
                        editing = true
                    }
                    Divider()
                    Button("Finish now", systemImage: "flag.checkered") { showStopConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title2)
                }
                .accessibilityLabel("Workout options")
                Text(workout.name).font(.headline).lineLimit(1)
                Spacer()
                WorkoutSoundToggles(showBeeps: true)
            }

            ProgressView(value: Double(done.count), total: Double(max(1, steps.count)))

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
        .confirmationDialog("Finish this workout now?", isPresented: $showStopConfirm, titleVisibility: .visible) {
            Button("Finish and save") { finish(completed: false) }
            Button("Pause & leave instead") { pauseAndLeave() }
        } message: {
            Text("Finishing saves what you've done so far to history. To come back to it later, pause instead.")
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
                if let seconds = step.exercise.timedSeconds {
                    VStack {
                        Text(WorkoutFormat.clock(exerciseRemaining ?? seconds))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(exerciseEnd != nil ? Color.accentColor : .primary)
                        Button {
                            toggleExerciseTimer(seconds)
                        } label: {
                            Label(exerciseEnd == nil ? "Start timer" : "Stop timer",
                                  systemImage: exerciseEnd == nil ? "play.fill" : "stop.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    VStack {
                        Text("\(step.exercise.reps)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                        Text("reps").foregroundStyle(.secondary)
                    }
                }
                if let w = WorkoutFormat.weight(step.exercise.weight, unit: weightUnit) {
                    VStack {
                        Text(w).font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("weight").foregroundStyle(.secondary)
                    }
                }
            }

            if !step.exercise.displayNote.isEmpty {
                Text(step.exercise.displayNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // What was actually done; the saved plan stays unchanged.
            GroupBox("What I did") {
                if let last = lastTime[step.key] {
                    HStack {
                        Label("Last time: \(last.actualText(unit: weightUnit))", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                HStack {
                    let timed = step.exercise.timedSeconds != nil
                    Stepper(timed ? "\(repsBinding.wrappedValue) sec" : "\(repsBinding.wrappedValue) reps",
                            value: repsBinding, in: 0...3600, step: timed ? 5 : 1)
                }
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("–", text: WeightText.binding(weightBinding))
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

    private func restPanel(_ seconds: Int) -> some View {
        VStack(spacing: 12) {
            Text("Rest").font(.title2.weight(.semibold)).foregroundStyle(.blue)
            Text(WorkoutFormat.clock(seconds))
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .monospacedDigit()
            WorkoutRunImage(image: step.exercise.imageID.flatMap { images[$0] }, maxHeight: 140)
            Text("Next: \(step.exercise.name), \(step.exercise.amountText)")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Values

    /// Suggested numbers before anything is entered: last time's weight
    /// (or the plan's), and the planned reps or seconds.
    private func defaultValue(_ s: RepStep) -> PausedRepRun.Value {
        let lastWeight = lastTime[s.key]?.actualWeight
        return PausedRepRun.Value(reps: s.exercise.timedSeconds ?? s.exercise.reps,
                                  weight: (lastWeight ?? 0) > 0 ? lastWeight : s.exercise.weight)
    }

    private func value(_ s: RepStep) -> PausedRepRun.Value { values[s.key] ?? defaultValue(s) }

    private var repsBinding: Binding<Int> {
        let s = step
        return Binding(get: { value(s).reps }, set: { var v = value(s); v.reps = $0; values[s.key] = v })
    }

    private var weightBinding: Binding<Double?> {
        let s = step
        return Binding(get: { value(s).weight }, set: { var v = value(s); v.weight = $0; values[s.key] = v })
    }

    private var weightStep: Double { weightUnit == "lb" ? 5 : 2.5 }
    private var stepText: String { weightUnit == "lb" ? "5 lb" : "2.5 kg" }

    private func bumpWeight(_ delta: Double) {
        let next = max(0, (weightBinding.wrappedValue ?? 0) + delta)
        weightBinding.wrappedValue = next == 0 ? nil : next
    }

    // MARK: Start, pause, edit

    private func start() {
        guard !didStart else { return }
        didStart = true
        loadSteps()
        segmentStart = Date()
        if let saved = PausedRunStore.load(workout.id) {
            // Continue a paused run.
            done = Set(saved.doneKeys)
            values = saved.values
            activeBefore = saved.activeSeconds
            firstStarted = saved.firstStarted
            index = saved.currentKey.flatMap { key in steps.firstIndex { $0.key == key } } ?? firstOpenIndex()
        } else {
            firstStarted = Date()
        }
        guard !steps.isEmpty else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        audio.begin()
        audio.speak(done.isEmpty ? cue(for: step) : "Welcome back. \(cue(for: step))")
        saveProgress()
    }

    private func loadSteps() {
        steps = RepStep.steps(for: workout.sets)
        restSeconds = workout.restBetweenSetsSeconds
        images = WorkoutPictureStore.images(steps.map(\.exercise.imageID), context: modelContext)
        let lookup = RepHistoryLookup(workoutID: workout.id, context: modelContext)
        var last: [String: RepLogEntry] = [:]
        for s in steps {
            if let entry = lookup.last(name: s.exercise.name, setIndex: s.setIndex, round: s.round) { last[s.key] = entry }
        }
        lastTime = last
    }

    private func firstOpenIndex() -> Int {
        steps.firstIndex { !done.contains($0.key) } ?? max(0, steps.count - 1)
    }

    /// After editing: keep everything logged, drop removed exercises, and
    /// carry on from the same exercise (or the first one not done yet).
    private func rebuildAfterEdit() {
        let currentKey = steps.indices.contains(index) ? steps[index].key : nil
        loadSteps()
        let keys = Set(steps.map(\.key))
        done = done.intersection(keys)
        values = values.filter { keys.contains($0.key) }
        index = currentKey.flatMap { key in steps.firstIndex { $0.key == key } } ?? firstOpenIndex()
        saveProgress()
        if !steps.isEmpty { audio.speak(cue(for: step)) }
    }

    private var activeSeconds: Double { activeBefore + Date().timeIntervalSince(segmentStart) }

    private func saveProgress() {
        guard result == nil, !steps.isEmpty else { return }
        PausedRunStore.save(PausedRepRun(workoutID: workout.id, doneKeys: Array(done), values: values,
                                         currentKey: steps[min(index, steps.count - 1)].key,
                                         activeSeconds: activeSeconds, firstStarted: firstStarted ?? Date(),
                                         savedAt: Date()))
    }

    private func pauseAndLeave() {
        restEnd = nil
        exerciseEnd = nil
        saveProgress()
        onExit(false)
    }

    // MARK: Actions

    private func cue(for step: RepStep) -> String {
        if let seconds = step.exercise.timedSeconds { return "\(step.exercise.name), \(seconds) seconds." }
        return "\(step.exercise.name), \(step.exercise.reps) reps."
    }

    private func toggleExerciseTimer(_ seconds: Int) {
        if exerciseEnd != nil {
            exerciseEnd = nil
            return
        }
        now = Date()
        lastExerciseBeep = nil
        exerciseEnd = Date().addingTimeInterval(Double(seconds))
        audio.speak("Go.")
    }

    private func next() {
        hideKeyboard()
        exerciseEnd = nil
        if restEnd != nil {
            endRest()
            return
        }
        // Mark this exercise done with the numbers shown.
        values[step.key] = value(step)
        done.insert(step.key)
        guard !isLast else {
            finish(completed: true)
            return
        }
        index += 1
        saveProgress()
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
        exerciseEnd = nil
        if restEnd != nil {
            restEnd = nil
        }
        guard index > 0 else { return }
        index -= 1
        saveProgress()
        audio.speak(cue(for: step))
    }

    private func endRest() {
        restEnd = nil
        audio.beep(final: true)
        audio.speak(cue(for: step))
    }

    private func tick(_ date: Date) {
        audio.ensureRunning()
        if exerciseEnd != nil {
            now = date
            if let left = exerciseRemaining {
                if (1...3).contains(left), left != lastExerciseBeep {
                    lastExerciseBeep = left
                    audio.beep()
                }
                if left == 0 {
                    exerciseEnd = nil
                    audio.beep(final: true)
                    audio.speak("Time.")
                }
            }
            return
        }
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
        exerciseEnd = nil
        // Log every exercise marked done, in workout order.
        let log = steps.filter { done.contains($0.key) }.map { s in
            let v = value(s)
            return RepLogEntry(name: s.exercise.name, setIndex: s.setIndex, round: s.round,
                               plannedReps: s.exercise.timedSeconds ?? s.exercise.reps,
                               plannedWeight: s.exercise.weight,
                               actualReps: v.reps, actualWeight: v.weight,
                               timed: s.exercise.timedSeconds != nil ? true : nil)
        }
        let seconds = Int(activeSeconds)
        // Compare with history before this session is saved.
        let records = WorkoutProgress.newRecords(in: log, context: modelContext, unit: weightUnit)
        // Duration counts only active time, not time spent away while paused.
        WorkoutRecorder.record(kind: .reps, workoutID: workout.id, name: workout.name,
                               startedAt: Date().addingTimeInterval(-Double(seconds)),
                               completed: completed, log: log, prNames: records.map(\.name), context: modelContext)
        PausedRunStore.clear(workout.id)
        if completed {
            let prText = records.isEmpty ? "" : " New personal record on \(records.map(\.name).joined(separator: ", "))."
            audio.speak("Workout complete.\(prText)")
            audio.endSoon()
        } else {
            audio.end()
        }
        result = (completed, seconds, log, records)
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
                        Text(entry.actualText(unit: unit))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(differs(entry) ? .orange : .primary)
                        Text("plan " + entry.plannedText(unit: unit))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
        }
    }

    private func differs(_ e: RepLogEntry) -> Bool {
        e.actualReps != e.plannedReps || (e.actualWeight ?? 0) != (e.plannedWeight ?? 0)
    }
}

/// "New personal record" list on the finish screen and in history.
struct PersonalRecordList: View {
    let records: [(name: String, detail: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(records.count == 1 ? "New personal record" : "\(records.count) new personal records",
                  systemImage: "trophy.fill")
                .font(.headline)
                .foregroundStyle(.yellow)
            ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                HStack {
                    Text(record.name).font(.subheadline.weight(.medium))
                    Spacer()
                    Text(record.detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}
