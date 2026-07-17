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

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

// MARK: - Insights Section (Chat)

struct InsightsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [Task]
    @Query private var okrs: [TaskOKR]

    @State private var selectedTaskKeys: Set<String> = []
    @State private var showTaskPicker = false
    @State private var fromDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate: Date = Date()
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var errorMessage: String? = nil
    @FocusState private var inputFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

    private var items: [RepeatTaskItem] { uniqueRepeatItems(from: allTasks) }

    private var taskSelectionLabel: String {
        if selectedTaskKeys.isEmpty { return "All Tasks" }
        if selectedTaskKeys.count == 1, let key = selectedTaskKeys.first,
           let item = items.first(where: { $0.id == key }) { return item.displayTitle }
        return "\(selectedTaskKeys.count) Habits"
    }

    var body: some View {
        VStack(spacing: 0) {
            configCard
            Divider()

            if messages.isEmpty {
                placeholderView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { msg in
                                ChatBubbleView(message: msg)
                                    .id(msg.id)
                            }
                            if isSending {
                                TypingIndicatorView()
                                    .id("typing")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation { proxy.scrollTo(messages.last?.id) }
                    }
                    .onChange(of: isSending) { _, sending in
                        if sending { withAnimation { proxy.scrollTo("typing") } }
                    }
                }
            }

            if let error = errorMessage {
                errorBanner(error)
            }

            inputBar
        }
        .padding(.bottom, keyboardHeight)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { n in
            guard let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let duration = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
            let bottomInset = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?.safeAreaInsets.bottom ?? 0
            withAnimation(.easeOut(duration: duration)) {
                keyboardHeight = frame.height - bottomInset
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { n in
            let duration = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                keyboardHeight = 0
            }
        }
    }

    // MARK: Config card

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Context")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if !messages.isEmpty {
                    Button {
                        messages = []
                        errorMessage = nil
                    } label: {
                        Label("Clear Chat", systemImage: "trash")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                // Task picker
                Button { showTaskPicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                        Text(taskSelectionLabel)
                            .font(.subheadline)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.indigo.opacity(0.1))
                    .foregroundColor(.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showTaskPicker) {
                    TaskPickerSheet(items: items, selectedKeys: $selectedTaskKeys)
                }

                Spacer()

                DatePicker("", selection: $fromDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                Text("–").foregroundColor(.secondary)
                DatePicker("", selection: $toDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            DateRangeShiftControl(start: $fromDate, end: $toDate)
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Placeholder

    private var placeholderView: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundColor(.indigo.opacity(0.3))
            Text("Ask About Your Habits")
                .font(.title3).fontWeight(.semibold)
            Text("Ask anything — completion trends, streaks, what to improve, or comparisons across habits.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 36)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(["What's my best streak this month?",
                         "Which habit do I skip most often?",
                         "How are my habits correlated?"], id: \.self) { suggestion in
                    Button {
                        inputText = suggestion
                        send()
                    } label: {
                        HStack {
                            Image(systemName: "sparkle").font(.caption2)
                            Text(suggestion).font(.subheadline)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.indigo.opacity(0.25), lineWidth: 1))
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
        .padding()
    }

    // MARK: Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(message).font(.caption).foregroundColor(.primary)
            Spacer()
            Button { errorMessage = nil } label: {
                Image(systemName: "xmark").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if inputFocused {
                Button {
                    inputFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .transition(.opacity.combined(with: .scale))
            }

            TextField("Ask about your habits…", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .focused($inputFocused)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(canSend ? .indigo : .secondary.opacity(0.4))
            }
            .disabled(!canSend)
        }
        .animation(.easeInOut(duration: 0.2), value: inputFocused)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Divider() }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: Send action

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        inputFocused = false
        errorMessage = nil

        let userMsg = ChatMessage(role: .user, text: text)
        messages.append(userMsg)
        isSending = true

        let context = buildContext()
        let apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
        let history = messages

        _Concurrency.Task {
            do {
                let reply = try await InsightGeneratorService.chat(
                    systemContext: context,
                    messages: history,
                    apiKey: apiKey
                )
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, text: reply))
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSending = false
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

// MARK: - Chat Bubble View

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundColor(.indigo)
                    .frame(width: 24, height: 24)
                    .background(Color.indigo.opacity(0.1))
                    .clipShape(Circle())
            }

            Text(message.text)
                .font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(message.role == .user ? Color.indigo : Color(.systemBackground))
                .foregroundColor(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(message.role == .assistant ? 0.05 : 0), radius: 3, y: 1)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.horizontal)
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .padding(.horizontal)
        .onAppear { phase = 1 }
    }
}

// MARK: - Insight Generator Service

enum InsightGeneratorService {

    static func chat(systemContext: String, messages: [ChatMessage], apiKey: String) async throws -> String {
        let systemPrompt = """
        You are a data-driven productivity analyst. The user's habit and task data is provided below.
        Answer questions specifically and concisely based on this data. Reference actual numbers and dates.
        If the data doesn't contain enough information to answer, say so clearly.

        ---
        \(systemContext)
        """

        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for msg in messages {
            apiMessages.append(["role": msg.role == .user ? "user" : "assistant", "content": msg.text])
        }

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": apiMessages,
            "max_tokens": 600,
            "temperature": 0.4
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
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
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
