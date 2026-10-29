import SwiftUI
import SwiftData

/// Hub for the vocabulary game: learn new words, review saved ones,
/// take quizzes and look back at past scores.
struct VocabularyHomeView: View {
    @Query(sort: \VocabWord.createdAt, order: .reverse) private var words: [VocabWord]
    @Query(sort: \VocabTestResult.date, order: .reverse) private var results: [VocabTestResult]
    @ObservedObject private var speaker = VocabSpeaker.shared

    /// A saved word to review each day; changes daily.
    private var wordOfTheDay: VocabWord? {
        guard !words.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return words[day % words.count]
    }

    private var averageScore: Double? {
        guard !results.isEmpty else { return nil }
        return results.map(\.score).reduce(0, +) / Double(results.count)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    stat("\(words.count)", "Words")
                    stat("\(words.filter(\.isMastered).count)", "Mastered")
                    stat("\(results.count)", "Tests")
                    stat(averageScore.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", "Avg score")
                }
                .padding(.vertical, 4)
            }

            Section {
                NavigationLink { VocabGenerateView() } label: {
                    menuRow("sparkles", .purple, "Learn new words", "AI picks 5 words for your level")
                }
                NavigationLink { VocabLibraryView() } label: {
                    menuRow("books.vertical", .blue, "My words", "Review every word you've saved")
                }
                NavigationLink { VocabQuizSetupView() } label: {
                    menuRow("checklist", .green, "Take a quiz", "Multiple-choice test on your words")
                }
                NavigationLink { VocabResultsView() } label: {
                    menuRow("chart.line.uptrend.xyaxis", .orange, "Test history", "Every score you've earned")
                }
            }

            if let word = wordOfTheDay {
                Section("Word of the day") {
                    NavigationLink { VocabWordDetailView(word: word) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(word.word).font(.title3.bold())
                                VocabLevelBadge(level: word.level)
                                Spacer()
                                VocabSpeakButton(text: word.word)
                            }
                            Text(word.definition)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("How to learn well") {
                tip("Say each word and sentence out loud after the speaker.")
                tip("Write your own sentence with each new word.")
                tip("Quiz yourself again after 1 day, 3 days and 1 week — spaced review makes words stick.")
                tip("Use \"Focus on weak words\" in quizzes to practise the ones you miss.")
            }
        }
        .navigationTitle("Vocabulary")
        .onDisappear { speaker.stop() }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func menuRow(_ icon: String, _ color: Color, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(color))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func tip(_ text: String) -> some View {
        Label(text, systemImage: "lightbulb")
            .font(.subheadline)
    }
}

// MARK: - Shared pieces

struct VocabLevelBadge: View {
    let level: VocabLevel

    var body: some View {
        Text(level.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch level {
        case .a1, .a2: return .green
        case .b1, .b2: return .blue
        case .c1, .c2: return .purple
        }
    }
}

/// Reads `text` aloud. Tap again to stop.
struct VocabSpeakButton: View {
    let text: String
    var slow = false
    @ObservedObject private var speaker = VocabSpeaker.shared

    var body: some View {
        Button {
            if speaker.isSpeaking(text) { speaker.stop() } else { speaker.speak(text, slow: slow) }
        } label: {
            Image(systemName: speaker.isSpeaking(text) ? "stop.circle.fill" : (slow ? "tortoise.fill" : "speaker.wave.2.fill"))
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(slow ? "Speak slowly" : "Speak")
    }
}

/// Says the word, spells it letter by letter, then says it again.
struct VocabSpellButton: View {
    let word: String
    @ObservedObject private var speaker = VocabSpeaker.shared

    var body: some View {
        Button {
            if speaker.isSpeaking("spell:" + word) { speaker.stop() } else { speaker.spell(word) }
        } label: {
            Image(systemName: speaker.isSpeaking("spell:" + word) ? "stop.circle.fill" : "character.textbox")
                .font(.body)
                .foregroundStyle(.indigo)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Spell it out")
    }
}

/// Everything about one word: meaning, pronunciation, sentences with speak
/// buttons, synonyms, collocations and a memory tip.
struct VocabWordCard: View {
    @Bindable var word: VocabWord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.word).font(.title2.bold())
                Spacer()
                VocabSpeakButton(text: word.word)
                VocabSpeakButton(text: word.word, slow: true)
                VocabSpellButton(word: word.word)
                Button { word.isFavorite.toggle() } label: {
                    Image(systemName: word.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(word.isFavorite ? "Remove from favorites" : "Add to favorites")
            }

            HStack(spacing: 8) {
                VocabLevelBadge(level: word.level)
                if !word.partOfSpeech.isEmpty {
                    Text(word.partOfSpeech).font(.caption.italic()).foregroundStyle(.secondary)
                }
                if !word.pronunciation.isEmpty {
                    Text("/\(word.pronunciation)/").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !word.syllables.isEmpty {
                Text("Spelling: \(word.syllables)")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(word.definition).font(.body)

            if !word.sentences.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to use it").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(Array(word.sentences.enumerated()), id: \.offset) { _, sentence in
                        HStack(alignment: .top, spacing: 6) {
                            Text(highlighted(sentence))
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VocabSpeakButton(text: sentence)
                        }
                    }
                }
            }

            if !word.synonyms.isEmpty {
                chips("Similar", word.synonyms, .green)
            }
            if !word.antonyms.isEmpty {
                chips("Opposite", word.antonyms, .red)
            }
            if !word.collocations.isEmpty {
                chips("Often used with", word.collocations, .blue)
            }
            if !word.memoryTip.isEmpty {
                Label(word.memoryTip, systemImage: "brain.head.profile")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    /// Shows the word in bold inside its example sentence.
    private func highlighted(_ sentence: String) -> AttributedString {
        var text = AttributedString(sentence)
        if let range = VocabQuizBuilder.wordRange(of: word.word, in: sentence),
           let lower = AttributedString.Index(range.lowerBound, within: text),
           let upper = AttributedString.Index(range.upperBound, within: text) {
            text[lower..<upper].font = .subheadline.bold()
        }
        return text
    }

    private func chips(_ title: String, _ items: [String], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            VocabFlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(color.opacity(0.12)))
                }
            }
        }
    }
}

struct VocabWordDetailView: View {
    let word: VocabWord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VocabWordCard(word: word)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Progress").font(.headline)
                    Text(progressText).font(.subheadline).foregroundStyle(.secondary)
                    Text("Added \(word.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(word.focus.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(word.word)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progressText: String {
        guard word.timesTested > 0 else { return "Not tested yet." }
        let percent = Int(((word.accuracy ?? 0) * 100).rounded())
        return "\(word.masteryLabel) · \(word.timesCorrect) of \(word.timesTested) right (\(percent)%)"
    }
}

/// Wraps its children onto new lines when they don't fit.
struct VocabFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
