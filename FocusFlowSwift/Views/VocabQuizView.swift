import SwiftUI
import SwiftData

// MARK: - Questions

struct VocabQuestion: Identifiable {
    let id = UUID()
    let word: VocabWord
    let kind: VocabQuestionKind
    /// Main text shown to the learner.
    let prompt: String
    let options: [String]
    let answer: String
}

/// Builds multiple-choice questions from saved words. Wrong options come
/// from the learner's other saved words.
enum VocabQuizBuilder {
    /// `pool` is the words to test; `all` is every saved word (for wrong options).
    static func build(pool: [VocabWord], all: [VocabWord], count: Int,
                      kinds: [VocabQuestionKind], weakFirst: Bool) -> [VocabQuestion] {
        guard !pool.isEmpty, !kinds.isEmpty else { return [] }

        var ordered: [VocabWord]
        if weakFirst {
            // Lowest accuracy first; untested words count as halfway.
            ordered = pool.shuffled().sorted { ($0.accuracy ?? 0.5) < ($1.accuracy ?? 0.5) }
        } else {
            ordered = pool.shuffled()
        }

        var questions: [VocabQuestion] = []
        var round = 0
        // Go around the words more than once (with other question kinds) if
        // more questions are wanted than there are words.
        while questions.count < count && round < kinds.count * 2 {
            for word in ordered where questions.count < count {
                let preferred = kinds.shuffled()
                for kind in preferred {
                    if questions.contains(where: { $0.word.id == word.id && $0.kind == kind }) { continue }
                    if let question = make(kind, for: word, all: all) {
                        questions.append(question)
                        break
                    }
                }
            }
            round += 1
            ordered.shuffle()
        }
        return questions
    }

    static func make(_ kind: VocabQuestionKind, for word: VocabWord, all: [VocabWord]) -> VocabQuestion? {
        let others = all.filter { $0.id != word.id && $0.word.lowercased() != word.word.lowercased() }.shuffled()

        func options(_ answer: String, _ wrong: [String]) -> [String]? {
            var seen = Set([answer.lowercased()])
            var picked: [String] = []
            for item in wrong where picked.count < 3 {
                let key = item.lowercased()
                guard !item.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                picked.append(item)
            }
            guard picked.count >= 2 else { return nil }
            return (picked + [answer]).shuffled()
        }

        switch kind {
        case .meaning:
            guard let opts = options(word.definition, others.map(\.definition)) else { return nil }
            return VocabQuestion(word: word, kind: kind, prompt: word.word, options: opts, answer: word.definition)

        case .word:
            guard let opts = options(word.word, others.map(\.word)) else { return nil }
            return VocabQuestion(word: word, kind: kind, prompt: word.definition, options: opts, answer: word.word)

        case .fillBlank:
            for sentence in word.sentences.shuffled() {
                guard let range = wordRange(of: word.word, in: sentence) else { continue }
                // Lowercase it so a capital letter (start of sentence) doesn't give it away.
                let found = String(sentence[range])
                let shown = word.word == word.word.lowercased() ? found.lowercased() : found
                var blanked = sentence
                blanked.replaceSubrange(range, with: "_____")
                // Other words in roughly the same form as the one in the sentence.
                guard let opts = options(shown, others.map(\.word)) else { return nil }
                return VocabQuestion(word: word, kind: kind, prompt: blanked, options: opts, answer: shown)
            }
            return nil

        case .listen:
            let wrong = misspellings(of: word.word)
            guard wrong.count >= 2, let opts = options(word.word, wrong) else { return nil }
            return VocabQuestion(word: word, kind: kind, prompt: word.word, options: opts, answer: word.word)

        case .synonym:
            guard let synonym = word.synonyms.filter({ $0.lowercased() != word.word.lowercased() }).randomElement() else { return nil }
            let mine = Set((word.synonyms + [word.word]).map { $0.lowercased() })
            let wrong = (others.flatMap(\.synonyms) + others.map(\.word)).filter { !mine.contains($0.lowercased()) }.shuffled()
            guard let opts = options(synonym, wrong) else { return nil }
            return VocabQuestion(word: word, kind: kind, prompt: word.word, options: opts, answer: synonym)
        }
    }

    /// Where the word (or a form of it, like "decided" for "decide") appears
    /// in a sentence.
    static func wordRange(of word: String, in sentence: String) -> Range<String.Index>? {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        // Exact word first, then a word that starts with its stem.
        let stem = NSRegularExpression.escapedPattern(for: String(word.prefix(max(4, word.count - 2))))
        for pattern in ["\\b\(escaped)\\b", "\\b\(stem)[A-Za-z]*\\b"] {
            if let range = sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return range
            }
        }
        return nil
    }

    /// Believable wrong spellings: doubled or single letters, swapped
    /// letters, common vowel mix-ups.
    static func misspellings(of word: String) -> [String] {
        let chars = Array(word)
        let lower = word.lowercased()
        var results = Set<String>()
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

        // Double letter → single, single consonant → double.
        for i in 1..<max(chars.count - 1, 1) where chars[i].isLetter {
            if chars[i] == chars[i - 1] {
                var c = chars; c.remove(at: i); results.insert(String(c))
            } else if !vowels.contains(Character(chars[i].lowercased())) {
                var c = chars; c.insert(chars[i], at: i); results.insert(String(c))
            }
        }
        // Swap two neighbouring letters.
        for i in 1..<max(chars.count - 1, 1) where chars[i].isLetter && chars[i + 1].isLetter && chars[i] != chars[i + 1] {
            var c = chars; c.swapAt(i, i + 1); results.insert(String(c))
        }
        // Common vowel and ending mix-ups.
        let swaps = [("ie", "ei"), ("ei", "ie"), ("ance", "ence"), ("ence", "ance"), ("able", "ible"), ("ible", "able"),
                     ("ant", "ent"), ("ent", "ant"), ("ous", "ious"), ("tion", "sion"), ("sion", "tion"), ("ph", "f"), ("c", "s")]
        for (from, to) in swaps where lower.contains(from) {
            results.insert(word.replacingOccurrences(of: from, with: to, options: .caseInsensitive))
        }
        // Change one vowel.
        for (i, ch) in chars.enumerated() where i > 0 && vowels.contains(Character(ch.lowercased())) {
            for v in vowels where v != Character(ch.lowercased()) {
                var c = chars; c[i] = v; results.insert(String(c))
            }
        }
        results.remove(word)
        return Array(results).shuffled()
    }
}

// MARK: - Quiz screen

struct VocabQuizView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var speaker = VocabSpeaker.shared

    @State private var questions: [VocabQuestion]
    let levelsLabel: String
    let modeLabel: String

    @State private var index = 0
    @State private var chosen: String?
    @State private var answers: [VocabAnswerRecord] = []
    @State private var startedAt = Date()
    @State private var finished = false
    @State private var savedResult: VocabTestResult?

    init(questions: [VocabQuestion], levelsLabel: String, modeLabel: String) {
        _questions = State(initialValue: questions)
        self.levelsLabel = levelsLabel
        self.modeLabel = modeLabel
    }

    var body: some View {
        Group {
            if questions.isEmpty {
                ContentUnavailableView("Not enough words", systemImage: "questionmark.circle",
                                       description: Text("Save at least 4 words to build a quiz."))
            } else if finished {
                summary
            } else {
                questionView(questions[index])
            }
        }
        .navigationTitle(finished ? "Results" : "Question \(min(index + 1, questions.count)) of \(questions.count)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!finished && !answers.isEmpty)
        .toolbar {
            if !finished && !answers.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("End") { finish() }
                }
            }
        }
        .onDisappear { speaker.stop() }
    }

    // MARK: Question

    private func questionView(_ q: VocabQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProgressView(value: Double(index), total: Double(questions.count))

                Label(q.kind.rawValue, systemImage: q.kind.icon)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                promptView(q)

                VStack(spacing: 10) {
                    ForEach(q.options, id: \.self) { option in
                        Button { choose(option, for: q) } label: {
                            HStack {
                                Text(option)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let chosen {
                                    if option == q.answer {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    } else if option == chosen {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                    }
                                }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(optionColor(option, q)))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .disabled(chosen != nil)
                    }
                }

                if chosen != nil {
                    feedback(q)
                    Button(action: next) {
                        Text(index + 1 < questions.count ? "Next" : "See results")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding()
        }
        .onAppear { autoSpeak(q) }
        .onChange(of: index) { _, _ in
            if index < questions.count { autoSpeak(questions[index]) }
        }
    }

    @ViewBuilder
    private func promptView(_ q: VocabQuestion) -> some View {
        switch q.kind {
        case .meaning:
            Text("What does this mean?").font(.headline)
            HStack {
                Text(q.prompt).font(.largeTitle.bold())
                VocabSpeakButton(text: q.prompt)
            }
        case .word:
            Text("Which word matches this meaning?").font(.headline)
            Text(q.prompt).font(.title3)
        case .fillBlank:
            Text("Which word fills the blank?").font(.headline)
            Text(q.prompt).font(.title3)
        case .listen:
            Text("Listen, then pick the correct spelling.").font(.headline)
            HStack(spacing: 16) {
                Button { speaker.speak(q.prompt) } label: {
                    Label("Play", systemImage: "speaker.wave.2.fill")
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                }
                Button { speaker.speak(q.prompt, slow: true) } label: {
                    Label("Slow", systemImage: "tortoise.fill")
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            Text(q.word.definition).font(.subheadline).foregroundStyle(.secondary)
        case .synonym:
            Text("Which word has a similar meaning?").font(.headline)
            HStack {
                Text(q.prompt).font(.largeTitle.bold())
                VocabSpeakButton(text: q.prompt)
            }
        }
    }

    private func feedback(_ q: VocabQuestion) -> some View {
        let right = chosen == q.answer
        return VStack(alignment: .leading, spacing: 8) {
            Label(right ? "Correct!" : "Not quite", systemImage: right ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(right ? .green : .red)
            HStack {
                Text(q.word.word).font(.title3.bold())
                VocabSpeakButton(text: q.word.word)
                VocabSpellButton(word: q.word.word)
            }
            Text(q.word.definition).font(.subheadline)
            if let sentence = q.word.sentences.first {
                HStack(alignment: .top) {
                    Text("“\(sentence)”").font(.subheadline.italic()).foregroundStyle(.secondary)
                    VocabSpeakButton(text: sentence)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill((right ? Color.green : Color.red).opacity(0.08)))
    }

    private func optionColor(_ option: String, _ q: VocabQuestion) -> Color {
        guard let chosen else { return Color(.secondarySystemBackground) }
        if option == q.answer { return Color.green.opacity(0.18) }
        if option == chosen { return Color.red.opacity(0.18) }
        return Color(.secondarySystemBackground)
    }

    private func autoSpeak(_ q: VocabQuestion) {
        if q.kind == .listen { speaker.speak(q.prompt) }
    }

    private func choose(_ option: String, for q: VocabQuestion) {
        chosen = option
        let right = option == q.answer
        if right { q.word.timesCorrect += 1 } else { q.word.timesWrong += 1 }
        q.word.lastTestedAt = Date()
        answers.append(VocabAnswerRecord(word: q.word.word, kind: q.kind, prompt: q.prompt,
                                         correctAnswer: q.answer, chosenAnswer: option, isCorrect: right))
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(right ? .success : .error)
    }

    private func next() {
        chosen = nil
        if index + 1 < questions.count { index += 1 } else { finish() }
    }

    private func finish() {
        speaker.stop()
        if !answers.isEmpty && savedResult == nil {
            let result = VocabTestResult(date: Date(), answers: answers,
                                         durationSeconds: Int(Date().timeIntervalSince(startedAt)),
                                         levelsLabel: levelsLabel, modeLabel: modeLabel)
            modelContext.insert(result)
            try? modelContext.save()
            savedResult = result
        }
        finished = true
    }

    // MARK: Summary

    private var summary: some View {
        let correct = answers.filter(\.isCorrect).count
        let missed = answers.filter { !$0.isCorrect }
        let score = answers.isEmpty ? 0 : Double(correct) / Double(answers.count)
        return List {
            Section {
                VStack(spacing: 6) {
                    Text("\(Int((score * 100).rounded()))%")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(score >= 0.8 ? .green : (score >= 0.5 ? .orange : .red))
                    Text("\(correct) of \(answers.count) correct")
                        .font(.headline)
                    Text(message(for: score))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }

            if !missed.isEmpty {
                Section("Review these") {
                    ForEach(missed) { record in
                        VocabAnswerRow(record: record)
                    }
                }
                Section {
                    Button {
                        retryMissed()
                    } label: {
                        Label("Practise missed words again", systemImage: "arrow.counterclockwise")
                    }
                }
            }

            Section {
                Button("Done") { dismiss() }
            }
        }
    }

    private func message(for score: Double) -> String {
        switch score {
        case 0.9...: return "Excellent! Try a harder level or new words."
        case 0.7..<0.9: return "Good work. Review the missed words and try again tomorrow."
        case 0.5..<0.7: return "Getting there. Read the example sentences out loud, then retry."
        default: return "Keep going — repetition is how words stick."
        }
    }

    /// Starts a new round with only the words that were missed.
    private func retryMissed() {
        let missedWords = Set(answers.filter { !$0.isCorrect }.map { $0.word.lowercased() })
        let pool = Dictionary(questions.map { ($0.word.word.lowercased(), $0.word) }, uniquingKeysWith: { a, _ in a })
            .filter { missedWords.contains($0.key) }.map(\.value)
        let allWords = (try? modelContext.fetch(FetchDescriptor<VocabWord>())) ?? questions.map(\.word)
        questions = VocabQuizBuilder.build(pool: pool, all: allWords, count: pool.count,
                                           kinds: VocabQuestionKind.allCases, weakFirst: false)
        index = 0
        chosen = nil
        answers = []
        savedResult = nil
        startedAt = Date()
        finished = false
    }
}

struct VocabAnswerRow: View {
    let record: VocabAnswerRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: record.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(record.isCorrect ? .green : .red)
                Text(record.word).font(.headline)
                Spacer()
                Text(record.kind.rawValue).font(.caption2).foregroundStyle(.secondary)
                VocabSpeakButton(text: record.word)
            }
            if record.kind != .meaning && record.kind != .listen && record.kind != .synonym {
                Text(record.prompt).font(.caption).foregroundStyle(.secondary)
            }
            Text("Answer: \(record.correctAnswer)").font(.subheadline)
            if !record.isCorrect {
                Text("You chose: \(record.chosenAnswer)").font(.subheadline).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Quiz setup

struct VocabQuizSetupView: View {
    @Query(sort: \VocabWord.createdAt, order: .reverse) private var words: [VocabWord]

    @AppStorage("vocab.quiz.count") private var questionCount = 10
    @AppStorage("vocab.quiz.weakFirst") private var weakFirst = true
    @State private var levels: Set<VocabLevel> = []
    @State private var kinds: Set<VocabQuestionKind> = Set(VocabQuestionKind.allCases)
    @State private var onlyFavorites = false
    @State private var skipMastered = false
    @State private var questions: [VocabQuestion] = []
    @State private var showQuiz = false

    private var pool: [VocabWord] {
        words.filter { word in
            (levels.isEmpty || levels.contains(word.level))
                && (!onlyFavorites || word.isFavorite)
                && (!skipMastered || !word.isMastered)
        }
    }

    var body: some View {
        Form {
            Section {
                Text("\(pool.count) word\(pool.count == 1 ? "" : "s") match")
                    .font(.headline)
                if words.count < 4 {
                    Text("Save at least 4 words first (you have \(words.count)).")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Levels (none selected = all)") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 8) {
                    ForEach(VocabLevel.allCases) { level in
                        let count = words.filter { $0.level == level }.count
                        Button {
                            if levels.contains(level) { levels.remove(level) } else { levels.insert(level) }
                        } label: {
                            VStack(spacing: 0) {
                                Text(level.rawValue).font(.headline)
                                Text("\(count)").font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(levels.contains(level) ? Color.green : Color(.tertiarySystemFill)))
                            .foregroundStyle(levels.contains(level) ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Question types") {
                ForEach(VocabQuestionKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { kinds.contains(kind) },
                        set: { on in if on { kinds.insert(kind) } else if kinds.count > 1 { kinds.remove(kind) } }
                    )) {
                        Label(kind.rawValue, systemImage: kind.icon)
                    }
                }
            }

            Section("Options") {
                Picker("Questions", selection: $questionCount) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle("Focus on weak words", isOn: $weakFirst)
                Toggle("Skip mastered words", isOn: $skipMastered)
                Toggle("Favorites only", isOn: $onlyFavorites)
            }

            Section {
                Button {
                    questions = VocabQuizBuilder.build(pool: pool, all: words, count: questionCount,
                                                       kinds: Array(kinds), weakFirst: weakFirst)
                    showQuiz = true
                } label: {
                    Label("Start quiz", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(words.count < 4 || pool.isEmpty)
            }
        }
        .navigationTitle("Quiz setup")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showQuiz) {
            VocabQuizView(questions: questions, levelsLabel: levelsLabel,
                          modeLabel: kinds.count == VocabQuestionKind.allCases.count
                            ? "Mixed" : kinds.map(\.rawValue).sorted().joined(separator: ", "))
        }
    }

    private var levelsLabel: String {
        levels.isEmpty ? "All" : levels.map(\.rawValue).sorted().joined(separator: ", ")
    }
}
