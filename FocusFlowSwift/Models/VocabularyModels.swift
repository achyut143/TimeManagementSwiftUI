import Foundation
import SwiftData

/// CEFR levels, the common international standard for language ability.
enum VocabLevel: String, CaseIterable, Identifiable, Codable {
    case a1 = "A1", a2 = "A2", b1 = "B1", b2 = "B2", c1 = "C1", c2 = "C2"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .a1: return "Beginner"
        case .a2: return "Elementary"
        case .b1: return "Intermediate"
        case .b2: return "Upper intermediate"
        case .c1: return "Advanced"
        case .c2: return "Proficient"
        }
    }

    /// Told to the AI so it picks words of the right difficulty.
    var promptHint: String {
        switch self {
        case .a1: return "very common everyday words a beginner learns first"
        case .a2: return "common words for simple daily situations"
        case .b1: return "useful words for work, travel and opinions, beyond the basics"
        case .b2: return "words for clear, detailed speech and writing on many topics"
        case .c1: return "precise, less common words used by fluent speakers in work and study"
        case .c2: return "sophisticated, nuanced words used by highly educated native speakers"
        }
    }
}

/// What the words should help with.
enum VocabFocus: String, CaseIterable, Identifiable, Codable {
    case general = "General"
    case conversation = "Everyday conversation"
    case workplace = "Workplace & business"
    case academic = "Academic"
    case persuasion = "Persuasion & presenting"
    case emotions = "Emotions & feelings"
    case phrasal = "Phrasal verbs"
    case idioms = "Idioms & expressions"
    case connectors = "Linking words"
    case tech = "Technology"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "textformat.abc"
        case .conversation: return "bubble.left.and.bubble.right"
        case .workplace: return "briefcase"
        case .academic: return "graduationcap"
        case .persuasion: return "megaphone"
        case .emotions: return "heart"
        case .phrasal: return "arrow.triangle.branch"
        case .idioms: return "quote.bubble"
        case .connectors: return "link"
        case .tech: return "cpu"
        }
    }

    var promptHint: String {
        switch self {
        case .general: return "a useful mix of nouns, verbs, adjectives and adverbs"
        case .conversation: return "words native speakers use in casual daily conversation"
        case .workplace: return "words for meetings, emails, negotiation and professional communication"
        case .academic: return "words from the Academic Word List used in essays, reports and lectures"
        case .persuasion: return "words for persuading, presenting ideas and public speaking"
        case .emotions: return "precise words to describe feelings, moods and reactions"
        case .phrasal: return "common phrasal verbs (verb + particle); the 'word' is the whole phrasal verb"
        case .idioms: return "common idioms and fixed expressions; the 'word' is the whole expression"
        case .connectors: return "linking words and discourse markers that make speech and writing flow"
        case .tech: return "words used when talking about technology, software and the internet"
        }
    }
}

/// Formal or informal style of the example sentences.
enum VocabTone: String, CaseIterable, Identifiable, Codable {
    case mixed = "Mixed", formal = "Formal", casual = "Casual"
    var id: String { rawValue }
}

@Model
final class VocabWord {
    var id: UUID = UUID()
    var word: String = ""
    var partOfSpeech: String = ""
    /// Simple sound-it-out guide, e.g. "uh-BIK-wih-tus".
    var pronunciation: String = ""
    var syllables: String = ""
    var definition: String = ""
    var sentences: [String] = []
    var synonyms: [String] = []
    var antonyms: [String] = []
    /// Words it is often used with, e.g. "make a decision".
    var collocations: [String] = []
    var memoryTip: String = ""
    var levelRaw: String = VocabLevel.b1.rawValue
    var focusRaw: String = VocabFocus.general.rawValue
    var createdAt: Date = Date()
    var timesCorrect: Int = 0
    var timesWrong: Int = 0
    var lastTestedAt: Date?
    var isFavorite: Bool = false

    init(word: String, partOfSpeech: String, pronunciation: String, syllables: String,
         definition: String, sentences: [String], synonyms: [String], antonyms: [String],
         collocations: [String], memoryTip: String, level: VocabLevel, focus: VocabFocus) {
        self.id = UUID()
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.pronunciation = pronunciation
        self.syllables = syllables
        self.definition = definition
        self.sentences = sentences
        self.synonyms = synonyms
        self.antonyms = antonyms
        self.collocations = collocations
        self.memoryTip = memoryTip
        self.levelRaw = level.rawValue
        self.focusRaw = focus.rawValue
        self.createdAt = Date()
    }

    var level: VocabLevel { VocabLevel(rawValue: levelRaw) ?? .b1 }
    var focus: VocabFocus { VocabFocus(rawValue: focusRaw) ?? .general }
    var timesTested: Int { timesCorrect + timesWrong }

    /// 0–1; nil when never tested.
    var accuracy: Double? {
        timesTested == 0 ? nil : Double(timesCorrect) / Double(timesTested)
    }

    /// Learned once answered right at least 3 times with 80%+ accuracy.
    var isMastered: Bool {
        timesCorrect >= 3 && (accuracy ?? 0) >= 0.8
    }

    var masteryLabel: String {
        if timesTested == 0 { return "New" }
        if isMastered { return "Mastered" }
        return (accuracy ?? 0) >= 0.5 ? "Learning" : "Needs practice"
    }
}

/// Kinds of quiz question.
enum VocabQuestionKind: String, CaseIterable, Identifiable, Codable {
    case meaning = "Word → meaning"
    case word = "Meaning → word"
    case fillBlank = "Fill the blank"
    case listen = "Listen & spell"
    case synonym = "Synonym"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .meaning: return "book"
        case .word: return "character.cursor.ibeam"
        case .fillBlank: return "text.insert"
        case .listen: return "ear"
        case .synonym: return "equal.circle"
        }
    }
}

/// One answered question, kept inside a test result.
struct VocabAnswerRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var word: String
    var kind: VocabQuestionKind
    var prompt: String
    var correctAnswer: String
    var chosenAnswer: String
    var isCorrect: Bool
}

@Model
final class VocabTestResult {
    var id: UUID = UUID()
    var date: Date = Date()
    var totalQuestions: Int = 0
    var correctCount: Int = 0
    var durationSeconds: Int = 0
    /// Comma-separated levels tested, e.g. "B1, B2", or "All".
    var levelsLabel: String = "All"
    var modeLabel: String = ""
    var answersData: Data = Data()

    init(date: Date, answers: [VocabAnswerRecord], durationSeconds: Int, levelsLabel: String, modeLabel: String) {
        self.id = UUID()
        self.date = date
        self.totalQuestions = answers.count
        self.correctCount = answers.filter(\.isCorrect).count
        self.durationSeconds = durationSeconds
        self.levelsLabel = levelsLabel
        self.modeLabel = modeLabel
        self.answersData = (try? JSONEncoder().encode(answers)) ?? Data()
    }

    var answers: [VocabAnswerRecord] {
        (try? JSONDecoder().decode([VocabAnswerRecord].self, from: answersData)) ?? []
    }

    var score: Double {
        totalQuestions == 0 ? 0 : Double(correctCount) / Double(totalQuestions)
    }
}
