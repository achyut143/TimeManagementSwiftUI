import SwiftUI
import SwiftData
import Charts

/// Every exercise ever logged in a rep workout, with its best and a link to its chart.
struct ExerciseProgressList: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("workout.weightUnit") private var weightUnit = "lb"
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    let searchText: String

    @State private var exercises: [ExerciseSummary] = []

    private var filtered: [ExerciseSummary] {
        let terms = searchText.lowercased().split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return exercises }
        return exercises.filter { e in terms.allSatisfy { e.key.contains($0) } }
    }

    var body: some View {
        Group {
            if exercises.isEmpty {
                ContentUnavailableView("No progress yet", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Finish a rep workout and each exercise's progress appears here."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(filtered) { e in
                    NavigationLink {
                        ExerciseProgressView(name: e.name)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).font(.headline)
                            Text("Best: \(bestText(e.best)) · \(e.sessions) session\(e.sessions == 1 ? "" : "s") · last \(e.lastDate.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: sessions.count) { _, _ in load() }
    }

    private func load() {
        exercises = WorkoutProgress.allExercises(context: modelContext)
    }

    private func bestText(_ b: ExerciseSessionBest) -> String {
        RepLogEntry.text(b.reps, b.topWeight, timed: b.timed, unit: weightUnit)
    }
}

/// Chart and session list for one exercise.
struct ExerciseProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("workout.weightUnit") private var weightUnit = "lb"
    let name: String

    @State private var points: [ExerciseSessionBest] = []

    /// Weighted exercises chart weight; bodyweight and timed ones chart reps or seconds.
    private var usesWeight: Bool { points.contains { $0.topWeight != nil } }
    private var isTimed: Bool { points.contains(where: \.timed) }
    private var valueLabel: String { usesWeight ? "Weight (\(weightUnit))" : (isTimed ? "Seconds" : "Reps") }

    private func value(_ p: ExerciseSessionBest) -> Double {
        usesWeight ? (p.topWeight ?? 0) : Double(p.reps)
    }

    private var best: ExerciseSessionBest? {
        points.max { value($0) != value($1) ? value($0) < value($1) : $0.reps < $1.reps }
    }

    var body: some View {
        List {
            if points.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Log \(name) in a rep workout to see progress."))
            } else {
                Section {
                    HStack {
                        stat("Best", best.map(text) ?? "–")
                        Spacer()
                        stat("Last", points.last.map(text) ?? "–")
                        Spacer()
                        stat("Sessions", "\(points.count)")
                    }
                }

                Section(valueLabel) {
                    Chart(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value(valueLabel, value(p)))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", p.date), y: .value(valueLabel, value(p)))
                            .foregroundStyle(p.isPR ? Color.yellow : Color.accentColor)
                            .symbolSize(p.isPR ? 110 : 45)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                    .padding(.vertical, 8)
                    .accessibilityLabel("\(name) \(valueLabel.lowercased()) over time")
                    if points.contains(where: \.isPR) {
                        Label("Yellow points are personal records", systemImage: "trophy.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Sessions") {
                    ForEach(points.reversed()) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.date.formatted(date: .abbreviated, time: .omitted))
                                Text(p.workoutName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if p.isPR {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                                    .accessibilityLabel("Personal record")
                            }
                            Text(text(p)).monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { points = WorkoutProgress.history(of: name, context: modelContext) }
    }

    private func text(_ p: ExerciseSessionBest) -> String {
        RepLogEntry.text(p.reps, p.topWeight, timed: p.timed, unit: weightUnit)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }
}
