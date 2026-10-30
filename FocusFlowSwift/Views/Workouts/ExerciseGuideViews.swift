import SwiftUI
import SwiftData

/// The body of one guide: what it is, steps, tips, mistakes, muscles,
/// easier/harder versions and a safety note.
struct ExerciseGuideContent: View {
    let guide: ExerciseGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if guide.unsure {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "questionmark.diamond.fill").foregroundStyle(.orange)
                    Text("The AI wasn't sure which move this name means. Check it against the program before relying on it, or tap ⋯ → Get a new explanation after renaming the exercise more clearly.")
                        .font(.footnote)
                        .wrapsFully()
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
            }
            if !guide.program.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text("\(guide.program) version")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !guide.summary.isEmpty {
                Text(guide.summary).font(.body).wrapsFully()
            }
            if !guide.muscles.isEmpty {
                WorkoutTagChips(tags: guide.muscles)
            }
            if !guide.steps.isEmpty {
                section("How to do it", icon: "list.number") {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)")
                                .font(.subheadline.bold())
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                            Text(step).font(.subheadline).wrapsFully()
                        }
                    }
                }
            }
            bullets("Tips", icon: "checkmark.circle", guide.tips, .green)
            bullets("Avoid", icon: "xmark.circle", guide.mistakes, .red)
            if !guide.easier.isEmpty || !guide.harder.isEmpty {
                section("Make it easier or harder", icon: "slider.horizontal.3") {
                    if !guide.easier.isEmpty { labeled("Easier", guide.easier) }
                    if !guide.harder.isEmpty { labeled("Harder", guide.harder) }
                }
            }
            if !guide.safety.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
                    Text(guide.safety).font(.footnote).wrapsFully()
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
            }
        }
    }

    private func section<C: View>(_ title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func bullets(_ title: String, icon: String, _ items: [String], _ color: Color) -> some View {
        if !items.isEmpty {
            section(title, icon: icon) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: icon).font(.caption).foregroundStyle(color).padding(.top, 2)
                        Text(item).font(.subheadline).wrapsFully()
                    }
                }
            }
        }
    }

    private func labeled(_ label: String, _ text: String) -> some View {
        (Text(label + ": ").bold() + Text(text)).font(.subheadline).wrapsFully()
    }
}

/// One exercise's guide. Uses the saved guide, or fetches it once if there
/// isn't one. Opened from the ⓘ button while working out.
struct ExerciseGuideSheet: View {
    let exerciseName: String
    let guideContext: ExerciseGuideContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var guides: [ExerciseGuide]
    @ObservedObject private var speaker = VocabSpeaker.shared
    @State private var loading = false
    @State private var error: String?
    @State private var confirmRegenerate = false

    private var guide: ExerciseGuide? {
        ExerciseGuideStore.find(exerciseName, program: guideContext.program, in: guides)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(guide?.name ?? exerciseName)
                        .font(.title2.bold())
                        .wrapsFully()
                    if let guide {
                        ExerciseGuideContent(guide: guide)
                    } else if loading {
                        HStack { ProgressView(); Text("Getting how-to…").foregroundStyle(.secondary) }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if let error {
                        Text(error).foregroundStyle(.red)
                        Button("Try again", action: fetch).buttonStyle(.borderedProminent)
                    } else if !ExerciseGuideStore.isGuidable(exerciseName) {
                        Text("No exercise name to look up.").foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("How to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { speaker.stop(); dismiss() }
                }
                if let guide {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            if speaker.isSpeaking(guide.spokenText) { speaker.stop() } else { speaker.speak(guide.spokenText) }
                        } label: {
                            Image(systemName: speaker.isSpeaking(guide.spokenText) ? "stop.circle" : "speaker.wave.2")
                        }
                        .accessibilityLabel("Read aloud")
                        Menu {
                            Button("Get a new explanation", systemImage: "arrow.clockwise") { confirmRegenerate = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Replace this explanation?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
                Button("Get a new one") { regenerate() }
            } message: {
                Text(guideContext.program.isEmpty
                     ? "Asks the AI again. The new explanation is saved for every workout with this exercise."
                     : "Asks the AI again. The new explanation is saved for every \(guideContext.program) workout with this exercise.")
            }
            .onAppear { if guide == nil { fetch() } }
            .onDisappear { speaker.stop() }
        }
        .presentationDetents([.medium, .large])
    }

    private func fetch() {
        guard ExerciseGuideStore.isGuidable(exerciseName), !loading else { return }
        loading = true
        error = nil
        _Concurrency.Task {
            defer { loading = false }
            do {
                try await ExerciseGuideStore.fetchMissing([exerciseName], guideContext: guideContext, context: modelContext)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func regenerate() {
        loading = true
        error = nil
        _Concurrency.Task {
            defer { loading = false }
            do {
                try await ExerciseGuideStore.regenerate(exerciseName, guideContext: guideContext, context: modelContext)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Every exercise in a workout with its guide, all on one screen. Fetches
/// only the ones not saved yet.
struct WorkoutGuideListView: View {
    let guideContext: ExerciseGuideContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var guides: [ExerciseGuide]
    @State private var expanded: Set<String> = []
    @State private var progress: (done: Int, total: Int)?
    @State private var error: String?
    @State private var openGuide: String?

    private var exercises: [String] { ExerciseGuideStore.unique(guideContext.exercises) }
    private var missing: [String] { ExerciseGuideStore.missing(exercises, program: guideContext.program, in: guides) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let progress {
                        HStack {
                            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                            Text("\(progress.done)/\(progress.total)").font(.caption.monospacedDigit())
                        }
                        Text("Getting how-tos for new exercises…").font(.caption).foregroundStyle(.secondary)
                    } else if !missing.isEmpty {
                        Button {
                            fetch()
                        } label: {
                            Label("Get how-tos for \(missing.count) exercise\(missing.count == 1 ? "" : "s")", systemImage: "sparkles")
                        }
                    } else {
                        Label("All \(exercises.count) saved, no AI needed", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    if !guideContext.program.isEmpty {
                        Text("Explained as the \(guideContext.program) program does them (from the folder this workout is in).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Expand all") { expanded = Set(exercises.map(ExerciseGuideStore.key)) }
                        Spacer()
                        Button("Collapse all") { expanded = [] }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }

                ForEach(Array(exercises.enumerated()), id: \.offset) { i, name in
                    let key = ExerciseGuideStore.key(name)
                    let guide = ExerciseGuideStore.find(name, program: guideContext.program, in: guides)
                    Section {
                        DisclosureGroup(isExpanded: Binding(
                            get: { expanded.contains(key) },
                            set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } }
                        )) {
                            if let guide {
                                ExerciseGuideContent(guide: guide)
                                    .padding(.vertical, 6)
                                Button("Open on its own", systemImage: "arrow.up.forward.square") { openGuide = name }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                            } else {
                                Text(progress != nil ? "Loading…" : "Not fetched yet").foregroundStyle(.secondary)
                            }
                        } label: {
                            HStack {
                                Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name).font(.headline).wrapsFully()
                                    if let guide, !guide.summary.isEmpty, !expanded.contains(key) {
                                        Text(guide.summary).font(.caption).foregroundStyle(.secondary).wrapsFully()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("How to: \(guideContext.workoutName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: Binding(get: { openGuide.map(GuideName.init) }, set: { openGuide = $0?.name })) { item in
                ExerciseGuideSheet(exerciseName: item.name, guideContext: guideContext)
            }
            .onAppear { if !missing.isEmpty { fetch() } }
        }
    }

    private struct GuideName: Identifiable {
        let name: String
        var id: String { name }
    }

    private func fetch() {
        guard progress == nil else { return }
        error = nil
        let todo = missing
        _Concurrency.Task {
            do {
                try await ExerciseGuideStore.fetchMissing(todo, guideContext: guideContext, context: modelContext) { done, total in
                    progress = (done, total)
                }
            } catch {
                self.error = error.localizedDescription
            }
            progress = nil
        }
    }
}

/// The ⓘ button for run screens: opens the current exercise's guide
/// without pausing the timer.
struct ExerciseGuideButton: View {
    let exerciseName: String
    let guideContext: ExerciseGuideContext?
    var tint: Color = .primary
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle.fill")
                .font(.title2)
                .foregroundStyle(tint)
        }
        .disabled(guideContext == nil || !ExerciseGuideStore.isGuidable(exerciseName))
        .accessibilityLabel("How to do \(exerciseName)")
        .sheet(isPresented: $showing) {
            if let guideContext {
                ExerciseGuideSheet(exerciseName: exerciseName, guideContext: guideContext)
            }
        }
    }
}

extension View {
    /// Let text use as many lines as it needs instead of ending in "…"
    /// (Lists and disclosure groups sometimes squeeze it onto one line).
    func wrapsFully() -> some View {
        multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
