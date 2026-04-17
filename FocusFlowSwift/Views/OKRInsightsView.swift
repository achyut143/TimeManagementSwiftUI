import SwiftUI
import SwiftData

// MARK: - Top-Level View

struct OKRInsightsView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                Text("OKRs").tag(0)
                Text("AI Insights").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            if selectedTab == 0 {
                OKRListSection()
            } else {
                InsightsSection()
            }
        }
        .navigationTitle("OKRs & Insights")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Unique Repeat Task helper

struct RepeatTaskItem: Identifiable {
    let id: String          // lowercase-trimmed key
    let displayTitle: String
    let interval: Int
}

func uniqueRepeatItems(from tasks: [Task]) -> [RepeatTaskItem] {
    var seen: [String: Task] = [:]
    for t in tasks {
        guard t.repeatAgain != nil else { continue }
        let key = t.title.lowercased().trimmingCharacters(in: .whitespaces)
        if seen[key] == nil { seen[key] = t }
    }
    return seen.map { key, t in
        RepeatTaskItem(id: key, displayTitle: t.title, interval: t.repeatAgain ?? 1)
    }.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
}

// MARK: - OKR List Section

struct OKRListSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [Task]
    @Query private var okrs: [TaskOKR]
    @State private var editingOKR: TaskOKR? = nil

    private var items: [RepeatTaskItem] { uniqueRepeatItems(from: allTasks) }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                List(items) { item in
                    OKRRowView(item: item, okr: okrFor(item.id))
                        .contentShape(Rectangle())
                        .onTapGesture { tapped(item) }
                }
                .listStyle(.insetGrouped)
            }
        }
        .sheet(item: $editingOKR) { okr in
            OKREditSheet(okr: okr)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath.circle")
                .font(.system(size: 52))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No Repeat Tasks")
                .font(.title3).fontWeight(.semibold)
            Text("Tasks with a repeat interval will appear here so you can set OKRs for them.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func okrFor(_ key: String) -> TaskOKR? {
        okrs.first { $0.taskTitle == key }
    }

    private func tapped(_ item: RepeatTaskItem) {
        let key = item.id
        if let existing = okrFor(key) {
            editingOKR = existing
        } else {
            let newOKR = TaskOKR(taskTitle: key, displayTitle: item.displayTitle, repeatInterval: item.interval)
            modelContext.insert(newOKR)
            try? modelContext.save()
            editingOKR = newOKR
        }
    }
}

// MARK: - OKR Row

private struct OKRRowView: View {
    let item: RepeatTaskItem
    let okr: TaskOKR?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.indigo)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.subheadline).fontWeight(.semibold)
                Text("Every \(item.interval) day\(item.interval == 1 ? "" : "s")")
                    .font(.caption2).foregroundColor(.secondary)

                if let okr, !okr.objective.isEmpty {
                    Text(okr.objective)
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                        .padding(.top, 1)
                }
            }

            Spacer()

            Image(systemName: (okr != nil && !okr!.objective.isEmpty) ? "checkmark.circle.fill" : "plus.circle")
                .foregroundColor((okr != nil && !okr!.objective.isEmpty) ? .green : .indigo.opacity(0.6))
                .font(.title3)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - OKR Edit Sheet

struct OKREditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var okr: TaskOKR

    @State private var objective: String = ""
    @State private var keyResults: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Every \(okr.repeatInterval) day\(okr.repeatInterval == 1 ? "" : "s")")
                        .font(.caption).foregroundColor(.secondary)
                } header: {
                    Text(okr.displayTitle)
                }

                Section("Objective") {
                    TextField("What do you want to achieve with this habit?",
                              text: $objective, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Key Results") {
                    TextField("How will you measure success? (one per line)",
                              text: $keyResults, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle("Edit OKR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                objective  = okr.objective
                keyResults = okr.keyResults
            }
        }
    }

    private func save() {
        okr.update(objective: objective.trimmingCharacters(in: .whitespacesAndNewlines),
                   keyResults: keyResults.trimmingCharacters(in: .whitespacesAndNewlines))
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Insights Section

struct InsightsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [Task]
    @Query private var okrs: [TaskOKR]
    @Query private var savedInsights: [TaskInsight]

    /// Empty set = all tasks. Non-empty = only the selected task keys.
    @State private var selectedTaskKeys: Set<String> = []
    @State private var showTaskPicker = false
    @State private var fromDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate: Date = Date()
    @State private var insightCountText: String = "20"
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil
    @FocusState private var countFieldFocused: Bool

    private var items: [RepeatTaskItem] { uniqueRepeatItems(from: allTasks) }

    /// Stable cache key: "all" or sorted keys joined by "|"
    private var cacheKey: String {
        selectedTaskKeys.isEmpty ? "all" : selectedTaskKeys.sorted().joined(separator: "|")
    }

    private var taskSelectionLabel: String {
        if selectedTaskKeys.isEmpty { return "All Tasks" }
        if selectedTaskKeys.count == 1, let key = selectedTaskKeys.first,
           let item = items.first(where: { $0.id == key }) { return item.displayTitle }
        return "\(selectedTaskKeys.count) Habits"
    }

    private var currentInsight: TaskInsight? {
        savedInsights.first { $0.matches(taskTitle: cacheKey, fromDate: fromDate, toDate: toDate) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                configCard
                generateButton
                if let error = errorMessage {
                    errorCard(error)
                }
                if let insight = currentInsight {
                    insightsCard(insight)
                } else if !isGenerating {
                    placeholderCard
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: Config card

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configure")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            // Task multi-select
            Button { showTaskPicker = true } label: {
                HStack {
                    Text("Habits")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(taskSelectionLabel)
                        .font(.subheadline)
                        .foregroundColor(.indigo)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .onChange(of: selectedTaskKeys) { _, _ in errorMessage = nil }
            .sheet(isPresented: $showTaskPicker) {
                TaskPickerSheet(items: items, selectedKeys: $selectedTaskKeys)
            }

            // Date range
            HStack {
                DatePicker("From", selection: $fromDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: fromDate) { _, _ in errorMessage = nil }
                Divider().frame(height: 20)
                DatePicker("To", selection: $toDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: toDate) { _, _ in errorMessage = nil }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Insight count
            HStack {
                Text("Insights to generate")
                    .font(.subheadline)
                Spacer()
                TextField("20", text: $insightCountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($countFieldFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { countFieldFocused = false }
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(width: 56)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding()
    }

    // MARK: Generate button

    private var generateButton: some View {
        Button(action: generate) {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: currentInsight == nil ? "sparkles" : "arrow.clockwise")
                }
                Text(isGenerating ? "Generating…" :
                     currentInsight == nil ? "Generate Insights" : "Generate New Insights")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isGenerating ? Color.indigo.opacity(0.6) : Color.indigo)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isGenerating)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: Error card

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(message).font(.caption).foregroundColor(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: Insights card

    private func insightsCard(_ insight: TaskInsight) -> some View {
        let all = insight.insights
        let observations = all.filter { !$0.hasPrefix("→ ") }
        let improvements = all.filter { $0.hasPrefix("→ ") }
                               .map { String($0.dropFirst(2)) } // strip "→ "

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(all.count) total · \(observations.count) insights · \(improvements.count) improvements")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("Generated \(insight.generatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundColor(.secondary)
            }

            if !observations.isEmpty {
                insightGroup(title: "Insights", icon: "chart.bar.fill", color: .indigo, lines: observations)
            }
            if !improvements.isEmpty {
                insightGroup(title: "Improvements", icon: "arrow.up.right.circle.fill", color: .green, lines: improvements)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func insightGroup(title: String, icon: String, color: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(color).font(.caption)
                Text(title)
                    .font(.caption).fontWeight(.semibold).foregroundColor(color).textCase(.uppercase)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(idx + 1)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(color.opacity(0.7))
                        .frame(width: 20, alignment: .trailing)
                        .padding(.top, 2)
                    Text(line)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 3)
                if idx < lines.count - 1 { Divider() }
            }
        }
        .padding(12)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Placeholder card

    private var placeholderCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundColor(.indigo.opacity(0.3))
            Text("No Insights Yet")
                .font(.title3).fontWeight(.semibold)
            Text("Select a task and date range, then tap Generate Insights.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: Generate action

    private func generate() {
        let count = max(1, min(200, Int(insightCountText.trimmingCharacters(in: .whitespaces)) ?? 20))
        insightCountText = "\(count)"
        isGenerating = true
        errorMessage = nil

        let context = buildContext()
        let apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
        let taskKeySnapshot = cacheKey
        let fromSnapshot = fromDate
        let toSnapshot = toDate
        // Capture model context explicitly so the async closure uses the live reference,
        // not a potentially stale copy from the captured struct.
        let mc = modelContext

        _Concurrency.Task {
            do {
                let selectedCount = selectedTaskKeys.isEmpty ? items.count : selectedTaskKeys.count
                let results = try await InsightGeneratorService.generate(
                    context: context,
                    count: count,
                    apiKey: apiKey,
                    isMultiHabit: selectedCount > 1
                )
                await MainActor.run {
                    do {
                        // Check for an existing record for the same task + date range
                        let existingKey = taskKeySnapshot.lowercased().trimmingCharacters(in: .whitespaces)
                        let fromDay = Calendar.current.startOfDay(for: fromSnapshot)
                        let toDay   = Calendar.current.startOfDay(for: toSnapshot)
                        let existing = savedInsights.first {
                            $0.taskTitle == existingKey
                            && Calendar.current.isDate($0.fromDate, inSameDayAs: fromDay)
                            && Calendar.current.isDate($0.toDate, inSameDayAs: toDay)
                        }
                        if let existing {
                            existing.update(insights: results, insightCount: count)
                        } else {
                            let record = TaskInsight(taskTitle: taskKeySnapshot, fromDate: fromSnapshot,
                                                     toDate: toSnapshot, insightCount: count, insights: results)
                            mc.insert(record)
                        }
                        try mc.save()
                    } catch {
                        errorMessage = "Save failed: \(error.localizedDescription)"
                    }
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    // MARK: Context builder

    private func buildContext() -> String {
        let keys: [String] = selectedTaskKeys.isEmpty ? items.map(\.id) : selectedTaskKeys.sorted()
        if keys.count == 1 { return buildSingleTaskContext(keys[0]) }
        return buildCorrelatedContext(keys)
    }

    private func buildCorrelatedContext(_ keys: [String]) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        let cal = Calendar.current
        let fromDay = cal.startOfDay(for: fromDate)
        let toDay   = cal.startOfDay(for: toDate)

        // Build per-key lookup: key -> [startOfDay -> Task]
        var byKeyAndDate: [String: [Date: Task]] = [:]
        var displayTitles: [String: String] = [:]
        for key in keys {
            var dateMap: [Date: Task] = [:]
            for t in allTasks {
                guard t.repeatAgain != nil else { continue }
                let tKey = t.title.lowercased().trimmingCharacters(in: .whitespaces)
                guard tKey == key, let d = t.date else { continue }
                let day = cal.startOfDay(for: d)
                guard day >= fromDay && day <= toDay else { continue }
                dateMap[day] = t
                displayTitles[key] = t.title
            }
            byKeyAndDate[key] = dateMap
        }

        let allDates = Set(byKeyAndDate.values.flatMap(\.keys)).sorted()
        let titles = keys.compactMap { displayTitles[$0] }

        var lines: [String] = []
        lines.append("Multi-Habit Correlation Analysis")
        lines.append("Range: \(df.string(from: fromDate)) – \(df.string(from: toDate))")
        lines.append("Habits: \(titles.joined(separator: " | "))")
        lines.append("")

        // Day-by-day joint status table
        lines.append("Day-by-Day Status (use this to find correlations between habits):")
        for day in allDates {
            let dateStr = df.string(from: day)
            let cols = keys.map { key -> String in
                let title = displayTitles[key] ?? key
                guard let t = byKeyAndDate[key]?[day] else { return "\(title): —" }
                let s: String
                if t.completed      { s = "✅" }
                else if t.notCompleted { s = "❌" }
                else if t.reassign  { s = "🔄" }
                else                { s = "⏳" }
                let note = t.notes.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
                return "\(title): \(s)\(note)"
            }.joined(separator: " | ")
            lines.append("  \(dateStr): \(cols)")
        }
        lines.append("")

        // Per-day points across all tasks
        lines.append(buildPointsContext())
        lines.append("")

        // Individual summaries for per-habit metrics (without redundant points block)
        lines.append("Individual Summaries:")
        for key in keys {
            lines.append(buildSingleTaskContext(key))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func buildSingleTaskContext(_ key: String) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        let okr = okrs.first { $0.taskTitle == key }

        let matchingInRange = allTasks.filter { t in
            guard t.repeatAgain != nil else { return false }
            let tKey = t.title.lowercased().trimmingCharacters(in: .whitespaces)
            guard tKey == key else { return false }
            if let d = t.date { return d >= Calendar.current.startOfDay(for: fromDate) && d <= Calendar.current.startOfDay(for: toDate) }
            return false
        }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        let displayTitle = matchingInRange.first?.title ?? okr?.displayTitle ?? key
        let interval = matchingInRange.first?.repeatAgain ?? okr?.repeatInterval ?? 1

        var lines: [String] = []
        lines.append("Task: \"\(displayTitle)\" (repeats every \(interval) day\(interval == 1 ? "" : "s"))")
        lines.append("")
        lines.append("OKR:")
        lines.append("Objective: \(okr?.objective.isEmpty == false ? okr!.objective : "Not set")")
        lines.append("Key Results:\n\(okr?.keyResults.isEmpty == false ? okr!.keyResults : "Not set")")
        lines.append("")

        lines.append("Completion History (\(df.string(from: fromDate)) – \(df.string(from: toDate))):")
        var completed = 0, missed = 0
        for t in matchingInRange {
            let dateStr = t.date.map { df.string(from: $0) } ?? "?"
            let status: String
            if t.completed { status = "✅ Completed"; completed += 1 }
            else if t.notCompleted { status = "❌ Missed"; missed += 1 }
            else if t.reassign { status = "🔄 Reassigned" }
            else { status = "⏳ Pending" }
            var entry = "  \(dateStr): \(status)"
            if let n = t.notes, !n.isEmpty { entry += " | Notes: \(n)" }
            lines.append(entry)
        }
        if !matchingInRange.isEmpty {
            let total = matchingInRange.count
            let pct = Int(Double(completed) / Double(total) * 100)
            lines.append("  Summary: \(total) instances | Completed: \(completed) (\(pct)%) | Missed: \(missed)")
        } else {
            lines.append("  No instances found in this date range.")
        }
        lines.append("")
        lines.append(buildPointsContext())
        return lines.joined(separator: "\n")
    }

    /// Builds a per-day points summary (all tasks, not just selected habits).
    private func buildPointsContext() -> String {
        let cal = Calendar.current
        let fromDay = cal.startOfDay(for: fromDate)
        let toDay   = cal.startOfDay(for: toDate)
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        // Group all tasks by day
        var byDay: [Date: [Task]] = [:]
        for t in allTasks {
            guard let d = t.date else { continue }
            let day = cal.startOfDay(for: d)
            guard day >= fromDay && day <= toDay else { continue }
            byDay[day, default: []].append(t)
        }

        guard !byDay.isEmpty else { return "Points data: none in this date range." }

        var lines: [String] = ["Daily Points (all tasks — earned vs available):"]
        var totalEarned = 0.0, totalAvailable = 0.0

        for day in byDay.keys.sorted() {
            let tasks = byDay[day]!
            let available = tasks.reduce(0.0) { $0 + $1.weight }
            let earned    = tasks.filter { $0.completed }.reduce(0.0) { $0 + $1.weight }
            let pct = available > 0 ? Int(earned / available * 100) : 0
            lines.append("  \(df.string(from: day)): \(String(format: "%.1f", earned)) / \(String(format: "%.1f", available)) pts (\(pct)%)")
            totalEarned    += earned
            totalAvailable += available
        }

        let overallPct = totalAvailable > 0 ? Int(totalEarned / totalAvailable * 100) : 0
        lines.append("  Total: \(String(format: "%.1f", totalEarned)) / \(String(format: "%.1f", totalAvailable)) pts (\(overallPct)%)")
        return lines.joined(separator: "\n")
    }

}

// MARK: - Insight Generator Service

enum InsightGeneratorService {
    static func generate(context: String, count: Int, apiKey: String, isMultiHabit: Bool = false) async throws -> [String] {
        let correlationBlock = isMultiHabit ? """

        CROSS-HABIT CORRELATIONS (use the Day-by-Day Status table):
        - On days Habit A was completed, what % of the time was Habit B also completed?
        - Which habit most often drags the other down when missed?
        - Do the habits reinforce each other or are they independent?
        - Which day combinations (both done / both missed / split) are most common?
        """ : ""

        let halfCount = count / 2
        let improveCount = count - halfCount

        let systemPrompt = """
        You are a data-driven productivity analyst. Analyze the habit/task data below.

        Generate exactly \(count) one-liners in two groups:

        GROUP 1 — OBSERVATIONS (\(halfCount) lines, plain text):
        Metric-based facts from the data. Lead with a specific number or date. Cover different angles:
        - Overall completion rate vs OKR target
        - Longest streak and when it broke
        - Current streak status
        - Consecutive-miss patterns
        - Best vs worst period
        - Momentum trend (first half of range vs second half)
        - Gap since last completion
        - Recurring themes in task notes
        - Points earned vs available per day and overall (use the Daily Points section)
        - Days with high points earn vs days the habit was missed (correlation)\(correlationBlock)

        GROUP 2 — IMPROVEMENTS (\(improveCount) lines, each MUST start with "→ "):
        One specific, actionable change — start with a verb. Must be concrete and specific to this habit:
        - A scheduling tweak based on when misses cluster
        - A friction-reduction idea based on the miss pattern
        - A micro-habit or trigger to protect streaks
        - A recovery tactic for after consecutive misses
        - An OKR-aligned focus shift

        Rules:
        - Max 18 words per line
        - Observations: must reference actual numbers/dates — no generic statements
        - Improvements: must start with "→ " exactly — no exceptions
        - No two lines cover the same angle
        - Output all \(halfCount) observations first, then all \(improveCount) improvements

        Return ONLY a flat JSON array of strings in order (observations first, then improvements):
        ["observation 1", ..., "→ improvement 1", ...]
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": context]
        ]

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": min(4000, count * 60),
            "temperature": 0.3
        ]

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let raw = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "InsightGenerator", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(raw)"])
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else { throw OpenAIError.noResponse }

        return parseInsightsArray(from: content)
    }

    private static func parseInsightsArray(from text: String) -> [String] {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let fence = cleaned.range(of: "```") {
                cleaned = String(cleaned[..<fence.lowerBound])
            }
        }

        guard let start = cleaned.firstIndex(of: "["),
              let end = cleaned.lastIndex(of: "]") else {
            // Fallback: split on newlines if not JSON
            return cleaned.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let jsonStr = String(cleaned[start...end])
        guard let jsonData = jsonStr.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: jsonData) else {
            return []
        }
        return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

// MARK: - Task Multi-Select Sheet

struct TaskPickerSheet: View {
    let items: [RepeatTaskItem]
    @Binding var selectedKeys: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                // "All Tasks" row — selecting it clears individual selections
                HStack {
                    Text("All Tasks")
                        .font(.subheadline)
                    Spacer()
                    if selectedKeys.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.indigo)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedKeys.removeAll() }

                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayTitle)
                                .font(.subheadline)
                            Text("Every \(item.interval) day\(item.interval == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedKeys.contains(item.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.indigo)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedKeys.contains(item.id) {
                            selectedKeys.remove(item.id)
                        } else {
                            selectedKeys.insert(item.id)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Habits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OKRInsightsView()
    }
    .modelContainer(for: [Task.self, TaskOKR.self, TaskInsight.self, DailyNote.self], inMemory: true)
}
