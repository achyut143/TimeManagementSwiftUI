import SwiftUI
import SwiftData

/// Paste a description of one or more workouts; AI builds them.
/// One workout opens straight in the editor; several open a review list.
struct AIWorkoutCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("workout.weightUnit") private var weightUnit = "lb"

    @State private var text = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var results: [WorkoutAIService.Result]?
    @State private var skippedParts = 0
    @State private var showCopied = false
    @State private var progress: (done: Int, total: Int)?
    @State private var skipReason: String?
    @State private var partCount = 1

    enum Mode: String, CaseIterable, Identifiable {
        case name = "From a name", describe = "Paste a description"
        var id: String { rawValue }
    }
    @AppStorage("workout.aiCreateMode") private var modeRaw = Mode.name.rawValue
    @State private var workoutName = ""
    @State private var namedKind: WorkoutAIService.NamedKind = .auto
    @State private var details = ""
    @State private var stage = ""
    /// The AI's note and web sources when built from a name.
    @State private var aiInfo: WorkoutAIService.WrittenInfo?
    @AppStorage("workout.aiCreateUseWeb") private var useWeb = true

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .name }

    var body: some View {
        if let results, results.count == 1, !(aiInfo?.hasSomethingToShow ?? false) {
            // The editor's Save/Cancel close this whole sheet.
            switch results[0] {
            case .tabata(let draft):
                TabataEditorView(workout: nil, prefill: draft)
            case .reps(let name, let sets, let rest):
                RepWorkoutEditorView(workout: nil, prefill: (name, sets, rest))
            }
        } else if let results {
            AIWorkoutReviewView(results: results, parts: partCount, skippedParts: skippedParts, skipReason: skipReason, aiInfo: aiInfo)
        } else {
            input
        }
    }

    private var input: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Create", selection: $modeRaw) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .name {
                    nameSections
                } else {
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
                }

                if isWorking && !stage.isEmpty {
                    Section {
                        HStack { ProgressView(); Text(stage).font(.subheadline) }
                    }
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
                        Button("Create", action: mode == .name ? createFromName : create)
                            .disabled((mode == .name ? workoutName : text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if mode == .describe {
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
            }
            .disabled(isWorking)
        }
    }

    private var placeholder: String {
        """
        e.g. Insanity warm up 1: 10s prepare, 40s work, no rest, 3 rounds with 30s between. Jog, jumping jacks, heismans, 1-2-3, butt kicks, high knees, mummy kicks.

        Upper body A. Set 1 × 3: bench press 10 reps 90 lb, bent-over row 10 reps 65 lb. Set 2 × 2: shoulder press 12 × 35 lb, bicep curl 12 × 25 lb.
        """
    }

    @ViewBuilder
    private var nameSections: some View {
        Section {
            TextField("e.g. Body Beast Total Body", text: $workoutName)
                .textInputAutocapitalization(.words)
                .submitLabel(.go)
                .onSubmit { if !workoutName.isEmpty { createFromName() } }
            Picker("Type", selection: $namedKind) {
                ForEach(WorkoutAIService.NamedKind.allCases) { Text($0.rawValue).tag($0) }
            }
            TextField("Anything else? (optional) e.g. beginner, no jumping", text: $details, axis: .vertical)
            Toggle("Look it up on the web", isOn: $useWeb)
        } header: {
            Text("Workout or program day")
        } footer: {
            Text("Type a workout's name, like \"Body Beast Total Body\", \"Insanity Plyometric Cardio Circuit\" or \"P90X Chest and Back\". The AI writes it as a real rep or Tabata workout you can run. You check every exercise before saving.\n\nWith \"Look it up on the web\" on, the AI searches for the program's routine first and lists the pages it used. It tells you when it isn't sure, so compare it with the program if exact moves matter.")
        }
    }

    /// Name → AI writes the workout as text → the usual reader builds it.
    private func createFromName() {
        errorMessage = nil
        aiInfo = nil
        isWorking = true
        stage = useWeb ? "Looking up \(workoutName.trimmingCharacters(in: .whitespaces)) on the web…"
                       : "Writing \(workoutName.trimmingCharacters(in: .whitespaces))…"
        let web = useWeb
        let name = workoutName.trimmingCharacters(in: .whitespaces)
        let kind = namedKind
        let extra = details
        let unit = weightUnit
        _Concurrency.Task {
            do {
                let written = try await WorkoutAIService().writeWorkout(named: name, kind: kind, details: extra,
                                                                        weightUnit: unit, useWeb: web)
                await MainActor.run {
                    text = written.text
                    aiInfo = written.info
                    stage = "Building the workout…"
                }
                let built = try await WorkoutAIService().createWorkouts(from: written.text, weightUnit: unit) { done, total in
                    progress = (done, total)
                }
                await MainActor.run {
                    isWorking = false
                    stage = ""
                    progress = nil
                    skippedParts = built.skippedParts
                    skipReason = built.firstError
                    partCount = built.parts
                    results = built.workouts
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    stage = ""
                    progress = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func create() {
        errorMessage = nil
        aiInfo = nil
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
    /// Folder and tags for everything saved from this screen.
    @State private var saveFolderID: UUID?
    @State private var saveTags: [String] = []
    let parts: Int
    let skippedParts: Int
    let skipReason: String?
    let aiInfo: WorkoutAIService.WrittenInfo?

    init(results: [WorkoutAIService.Result], parts: Int = 1, skippedParts: Int = 0, skipReason: String? = nil,
         aiInfo: WorkoutAIService.WrittenInfo? = nil) {
        self.parts = parts
        self.aiInfo = aiInfo
        _items = State(initialValue: results.map { Item(result: $0) })
        self.skippedParts = skippedParts
        self.skipReason = skipReason
    }

    private var pending: [Item] { items.filter { $0.include && !$0.saved } }

    var body: some View {
        NavigationStack {
            List {
                if let aiInfo, aiInfo.hasSomethingToShow {
                    Section {
                        if let note = aiInfo.note {
                            Label(note, systemImage: "questionmark.diamond.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                        if aiInfo.webFailed {
                            Label("Web search wasn't available, so this was written from what the AI already knows. Check it against the program.",
                                  systemImage: "wifi.exclamationmark")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        } else if aiInfo.usedWeb && aiInfo.sources.isEmpty {
                            Label("Looked up on the web.", systemImage: "globe").font(.subheadline)
                        }
                        ForEach(aiInfo.sources, id: \.self) { source in
                            if let url = URL(string: source) {
                                Link(destination: url) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "link")
                                        Text(url.host() ?? source).lineLimit(1)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                    } header: {
                        Text(aiInfo.sources.isEmpty ? "About this workout" : "Sources")
                    } footer: {
                        Text("Check the exercises, sets and reps before saving.")
                    }
                }
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

                WorkoutFolderAndTagsSection(folderID: $saveFolderID, tags: $saveTags)

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
            TabataEditorView(workout: nil, prefill: draft, folderID: saveFolderID, tags: saveTags, onSaved: markSaved)
        case .reps(let name, let sets, let rest):
            RepWorkoutEditorView(workout: nil, prefill: (name, sets, rest), folderID: saveFolderID, tags: saveTags, onSaved: markSaved)
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
                workout.folderID = saveFolderID
                workout.tags = WorkoutTags.clean(saveTags)
                modelContext.insert(workout)
            case .reps(let name, let sets, let rest):
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                let workout = RepWorkout(name: trimmed.isEmpty ? fallbackName : trimmed)
                workout.sets = sets
                workout.restBetweenSetsSeconds = rest
                workout.folderID = saveFolderID
                workout.tags = WorkoutTags.clean(saveTags)
                modelContext.insert(workout)
            }
        }
        try? modelContext.save()
    }
}
