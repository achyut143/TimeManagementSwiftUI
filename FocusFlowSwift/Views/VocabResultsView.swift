import SwiftUI
import SwiftData
import Charts

/// Every saved quiz result, with a score trend chart.
struct VocabResultsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabTestResult.date, order: .reverse) private var results: [VocabTestResult]

    private var average: Double {
        results.isEmpty ? 0 : results.map(\.score).reduce(0, +) / Double(results.count)
    }

    var body: some View {
        List {
            if results.isEmpty {
                ContentUnavailableView("No tests yet", systemImage: "checklist",
                                       description: Text("Take a quiz and your scores will show up here."))
            } else {
                Section {
                    HStack(spacing: 0) {
                        stat("\(results.count)", "Tests")
                        stat("\(Int((average * 100).rounded()))%", "Average")
                        stat("\(Int(((results.map(\.score).max() ?? 0) * 100).rounded()))%", "Best")
                        stat("\(results.map(\.totalQuestions).reduce(0, +))", "Questions")
                    }
                    if results.count >= 2 {
                        Chart(results.reversed()) { result in
                            LineMark(x: .value("Date", result.date), y: .value("Score", result.score * 100))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Date", result.date), y: .value("Score", result.score * 100))
                        }
                        .chartYScale(domain: 0...100)
                        .chartYAxis { AxisMarks(values: [0, 50, 100]) { AxisGridLine(); AxisValueLabel() } }
                        .frame(height: 160)
                        .padding(.vertical, 6)
                    }
                }

                Section("All tests") {
                    ForEach(results) { result in
                        NavigationLink { VocabResultDetailView(result: result) } label: {
                            row(result)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { modelContext.delete(results[index]) }
                        try? modelContext.save()
                    }
                }
            }
        }
        .navigationTitle("Test history")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ result: VocabTestResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.bold())
                Text("Levels: \(result.levelsLabel) · \(result.modeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int((result.score * 100).rounded()))%")
                    .font(.headline)
                    .foregroundStyle(result.score >= 0.8 ? .green : (result.score >= 0.5 ? .orange : .red))
                Text("\(result.correctCount)/\(result.totalQuestions)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct VocabResultDetailView: View {
    let result: VocabTestResult

    var body: some View {
        List {
            Section {
                LabeledContent("Score", value: "\(result.correctCount) of \(result.totalQuestions) (\(Int((result.score * 100).rounded()))%)")
                LabeledContent("Levels", value: result.levelsLabel)
                LabeledContent("Questions", value: result.modeLabel)
                LabeledContent("Time", value: Duration.seconds(result.durationSeconds)
                    .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
            }
            Section("Answers") {
                ForEach(result.answers) { VocabAnswerRow(record: $0) }
            }
        }
        .navigationTitle(result.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}
