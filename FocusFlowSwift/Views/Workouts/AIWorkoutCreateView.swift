import SwiftUI
import SwiftData

/// Paste a description of one or more workouts; AI builds them.
/// One workout opens straight in the editor; several open a review list.
struct AIWorkoutCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("workout.weightUnit") private var weightUnit = "kg"

    @State private var text = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var results: [WorkoutAIService.Result]?
    @State private var skippedParts = 0
    @State private var showCopied = false
    @State private var progress: (done: Int, total: Int)?
    @State private var skipReason: String?
    @State private var partCount = 1

    var body: some View {
        if let results, results.count == 1 {
            // The editor's Save/Cancel close this whole sheet.
            switch results[0] {
            case .tabata(let draft):
                TabataEditorView(workout: nil, prefill: draft)
            case .reps(let name, let sets, let rest):
                RepWorkoutEditorView(workout: nil, prefill: (name, sets, rest))
            }
        } else if let results {
            AIWorkoutReviewView(results: results, parts: partCount, skippedParts: skippedParts, skipReason: skipReason)
        } else {
            input
        }
    }

    private var input: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(placeholder)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Workout description")
                } footer: {
                    Text("Describe one workout or several, Tabata and rep workouts mixed. You can check each one before saving.\n\nTip: tap \"Copy format for AI\" and paste it into ChatGPT or Claude along with your workout plan. It will write the workouts in the format this app reads best.")
                }

                if isWorking, let progress, progress.total > 1 {
                    Section {
                        ProgressView(value: Double(progress.done), total: Double(progress.total)) {
                            Text("Reading workouts… part \(min(progress.done + 1, progress.total)) of \(progress.total)")
                                .font(.subheadline)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Create with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Create", action: create)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        UIPasteboard.general.string = WorkoutAIService.formatInstructions
                        withAnimation { showCopied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showCopied = false }
                        }
                    } label: {
                        Label(showCopied ? "Copied" : "Copy format for AI",
                              systemImage: showCopied ? "checkmark" : "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                    }
                    Spacer()
                    Button {
                        if let pasted = UIPasteboard.general.string { text = pasted }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .disabled(isWorking)
        }
    }

    private var placeholder: String {
        """
        e.g. Insanity warm up 1: 10s prepare, 40s work, no rest, 3 rounds with 30s between. Jog, jumping jacks, heismans, 1-2-3, butt kicks, high knees, mummy kicks.

        Upper body A. Set 1 × 3: bench press 10 reps 40 kg, bent-over row 10 reps 30 kg. Set 2 × 2: shoulder press 12 × 15 kg, bicep curl 12 × 10 kg.
        """
    }

    private func create() {
        errorMessage = nil
        isWorking = true
        let description = text
        let unit = weightUnit
        // `Task` is the app's task model here, so use the concurrency one by its full name.
        _Concurrency.Task {
            do {
                let built = try await WorkoutAIService().createWorkouts(from: description, weightUnit: unit) { done, total in
                    progress = (done, total)
                }
                await MainActor.run {
                    isWorking = false
                    progress = nil
                    skippedParts = built.skippedParts
                    skipReason = built.firstError
                    partCount = built.parts
                    results = built.workouts
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    progress = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

/// Review several AI-built workouts: tick which to keep, tap one to check
/// and save it in the editor, or save all ticked ones at once.
private struct AIWorkoutReviewView: View {
    private struct Item: Identifiable {
        let id = UUID()
        var result: WorkoutAIService.Result
        var include = true
        var saved = false
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Item]
    @State private var editingID: UUID?
    let parts: Int
    let skippedParts: Int
    let skipReason: String?

    init(results: [WorkoutAIService.Result], parts: Int = 1, skippedParts: Int = 0, skipReason: String? = nil) {
        self.parts = parts
        _items = State(initialValue: results.map { Item(result: $0) })
        self.skippedParts = skippedParts
        self.skipReason = skipReason
    }

    private var pending: [Item] { items.filter { $0.include && !$0.saved } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($items) { $item in
                        HStack(spacing: 12) {
                            Button {
                                item.include.toggle()
                            } label: {
                                Image(systemName: item.saved ? "checkmark.seal.fill" : (item.include ? "checkmark.circle.fill" : "circle"))
                                    .font(.title3)
                                    .foregroundStyle(item.saved ? .green : (item.include ? Color.accentColor : .secondary))
                            }
                            .buttonStyle(.borderless)
                            .disabled(item.saved)
                            .accessibilityLabel(item.include ? "Don't save" : "Save")

                            Button {
                                editingID = item.id
                            } label: {
                                HStack {
                                    Image(systemName: item.result.kind.icon)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.result.name.ifEmpty("Untitled workout"))
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(item.saved ? "Saved" : "\(item.result.kind.title) · \(item.result.summary)")
                                            .font(.subheadline)
                                            .foregroundStyle(item.saved ? .green : .secondary)
                                    }
                                    Spacer()
                                    if !item.saved {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(item.saved)
                        }
                    }
                } header: {
                    Text("\(items.count) workouts found" + (parts > 1 ? " in \(parts) parts" : ""))
                } footer: {
                    Text("Tap a workout to check or change it before saving.")
                }

                if combinableTabatas.count >= 2 {
                    Section {
                        Button {
                            combineTabatas()
                        } label: {
                            Label("Combine \(combinableTabatas.count) Tabatas into one", systemImage: "square.stack.3d.down.right")
                        }
                    } footer: {
                        Text("Makes one Tabata whose parts run back to back, e.g. a warm up followed by circuits. Untick any you want to keep separate first.")
                    }
                }

                if skippedParts > 0 {
                    Section {
                        Label("\(skippedParts) part\(skippedParts == 1 ? "" : "s") of your text couldn't be read, so some workouts may be missing. Check the list, and paste any missing workout again on its own.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        if let skipReason {
                            Text("Reason: \(skipReason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Review workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(items.contains(where: \.saved) ? "Close" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(pending.isEmpty ? "Done" : "Save all (\(pending.count))") {
                        saveAll()
                        dismiss()
                    }
                    .bold()
                }
            }
            .sheet(item: editingBinding) { item in
                editor(for: item)
            }
        }
    }

    private var editingBinding: Binding<Item?> {
        Binding(
            get: { items.first { $0.id == editingID } },
            set: { editingID = $0?.id }
        )
    }

    @ViewBuilder
    private func editor(for item: Item) -> some View {
        let markSaved = {
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].saved = true }
        }
        switch item.result {
        case .tabata(let draft):
            TabataEditorView(workout: nil, prefill: draft, onSaved: markSaved)
        case .reps(let name, let sets, let rest):
            RepWorkoutEditorView(workout: nil, prefill: (name, sets, rest), onSaved: markSaved)
        }
    }

    /// Ticked, unsaved Tabatas.
    private var combinableTabatas: [Item] {
        items.filter { $0.include && !$0.saved && $0.result.kind == .tabata }
    }

    /// Merges the ticked Tabatas into one multi-part Tabata, in list order.
    private func combineTabatas() {
        let group = combinableTabatas
        guard group.count >= 2, let firstIndex = items.firstIndex(where: { $0.id == group[0].id }) else { return }
        let names = group.map { $0.result.name }
        let shared = Self.sharedPrefix(names)
        var parts: [TabataPart] = []
        for item in group {
            guard case .tabata(let draft) = item.result else { continue }
            var remainder = String(item.result.name.dropFirst(shared.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:·,.").union(.whitespaces))
            if remainder.isEmpty { remainder = item.result.name }
            for (i, var part) in draft.parts.enumerated() {
                part.id = UUID()
                if part.name.isEmpty {
                    part.name = draft.parts.count > 1 ? "\(remainder) \(i + 1)" : remainder
                }
                parts.append(part)
            }
        }
        let title = shared.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:·,.").union(.whitespaces))
        let merged = TabataDraft(name: title.isEmpty ? names[0] : title, parts: parts)
        let groupIDs = Set(group.map(\.id))
        var newItems = items
        newItems[firstIndex].result = .tabata(merged)
        newItems.removeAll { groupIDs.contains($0.id) && $0.id != items[firstIndex].id }
        items = newItems
    }

    /// Longest shared start of the names, cut back to a whole word.
    static func sharedPrefix(_ names: [String]) -> String {
        guard var prefix = names.first else { return "" }
        for name in names.dropFirst() {
            while !name.lowercased().hasPrefix(prefix.lowercased()) { prefix.removeLast() }
        }
        if names.contains(where: { $0.count > prefix.count && !($0.dropFirst(prefix.count).first?.isWhitespace ?? true) }),
           let lastSpace = prefix.lastIndex(of: " ") {
            prefix = String(prefix[..<lastSpace])
        }
        return prefix
    }

    private func saveAll() {
        for (n, item) in pending.enumerated() {
            let fallbackName = "\(item.result.kind.title) workout \(n + 1)"
            switch item.result {
            case .tabata(let draft):
                let workout = TabataWorkout(name: "")
                workout.apply(draft)
                if workout.name.isEmpty { workout.name = fallbackName }
                modelContext.insert(workout)
            case .reps(let name, let sets, let rest):
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                let workout = RepWorkout(name: trimmed.isEmpty ? fallbackName : trimmed)
                workout.sets = sets
                workout.restBetweenSetsSeconds = rest
                modelContext.insert(workout)
            }
        }
        try? modelContext.save()
    }
}
