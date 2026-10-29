import SwiftUI
import SwiftData

/// Pick a level and focus, then get 5 new AI-chosen words each run.
/// Every word is saved straight away.
struct VocabGenerateView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var savedWords: [VocabWord]

    @AppStorage("vocab.level") private var levelRaw = VocabLevel.b1.rawValue
    @AppStorage("vocab.focus") private var focusRaw = VocabFocus.general.rawValue
    @AppStorage("vocab.tone") private var toneRaw = VocabTone.mixed.rawValue
    @State private var topic = ""

    @State private var latestWords: [VocabWord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showQuiz = false
    @State private var quizQuestions: [VocabQuestion] = []

    private var level: VocabLevel { VocabLevel(rawValue: levelRaw) ?? .b1 }
    private var focus: VocabFocus { VocabFocus(rawValue: focusRaw) ?? .general }
    private var tone: VocabTone { VocabTone(rawValue: toneRaw) ?? .mixed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                levelPicker
                focusPicker

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sentence style").font(.headline)
                    Picker("Sentence style", selection: $toneRaw) {
                        ForEach(VocabTone.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Topic (optional)").font(.headline)
                    TextField("e.g. job interviews, travel, cooking", text: $topic)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                }

                Button(action: generate) {
                    HStack {
                        if isLoading { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                        Text(isLoading ? "Finding words…" : (latestWords.isEmpty ? "Generate 5 words" : "Generate 5 more"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(isLoading ? Color.gray : Color.purple))
                    .foregroundStyle(.white)
                }
                .disabled(isLoading)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if !latestWords.isEmpty {
                    HStack {
                        Text("New words (saved)").font(.headline)
                        Spacer()
                        Button("Quiz me on these") {
                            quizQuestions = VocabQuizBuilder.build(pool: latestWords, all: savedWords,
                                                                   count: latestWords.count * 2,
                                                                   kinds: VocabQuestionKind.allCases, weakFirst: false)
                            showQuiz = true
                        }
                            .font(.subheadline.bold())
                            .disabled(savedWords.count < 4)
                    }
                    ForEach(latestWords) { word in
                        VocabWordCard(word: word)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Learn new words")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .navigationDestination(isPresented: $showQuiz) {
            VocabQuizView(questions: quizQuestions, levelsLabel: level.rawValue, modeLabel: "New words")
        }
    }

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Level").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(VocabLevel.allCases) { option in
                    Button { levelRaw = option.rawValue } label: {
                        VStack(spacing: 2) {
                            Text(option.rawValue).font(.headline)
                            Text(option.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(level == option ? Color.purple : Color(.secondarySystemGroupedBackground)))
                        .foregroundStyle(level == option ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(level.promptHint.prefix(1).uppercased() + level.promptHint.dropFirst() + ".")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var focusPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VocabFocus.allCases) { option in
                        Button { focusRaw = option.rawValue } label: {
                            Label(option.rawValue, systemImage: option.icon)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule()
                                    .fill(focus == option ? Color.purple : Color(.secondarySystemGroupedBackground)))
                                .foregroundStyle(focus == option ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func generate() {
        errorMessage = nil
        isLoading = true
        let avoid = savedWords.sorted { $0.createdAt < $1.createdAt }.map(\.word)
        let level = level, focus = focus, tone = tone, topic = topic
        _Concurrency.Task {
            defer { isLoading = false }
            do {
                let drafts = try await VocabularyAIService().generateWords(
                    level: level, focus: focus, tone: tone, topic: topic, avoid: avoid)
                let words = drafts.map { d in
                    VocabWord(word: d.word.trimmingCharacters(in: .whitespaces),
                              partOfSpeech: d.part_of_speech ?? "",
                              pronunciation: d.pronunciation ?? "",
                              syllables: d.syllables ?? "",
                              definition: d.definition,
                              sentences: d.sentences ?? [],
                              synonyms: d.synonyms ?? [],
                              antonyms: d.antonyms ?? [],
                              collocations: d.collocations ?? [],
                              memoryTip: d.memory_tip ?? "",
                              level: level, focus: focus)
                }
                words.forEach { modelContext.insert($0) }
                try? modelContext.save()
                latestWords = words
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
