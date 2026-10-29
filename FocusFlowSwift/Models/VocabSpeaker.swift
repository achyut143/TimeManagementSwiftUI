import Foundation
import AVFoundation

/// Reads words and sentences aloud, and can spell a word letter by letter.
@MainActor
final class VocabSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = VocabSpeaker()

    /// The text currently being read, so its button can show a "playing" state.
    @Published private(set) var speakingText: String?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    private var voice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Reads `text`. `slow` reads it more slowly, which helps with hearing each sound.
    func speak(_ text: String, slow: Bool = false) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = slow ? AVSpeechUtteranceDefaultSpeechRate * 0.6 : AVSpeechUtteranceDefaultSpeechRate * 0.9
        speakingText = text
        synthesizer.speak(utterance)
    }

    /// Says the word, spells it letter by letter, then says it again.
    func spell(_ word: String) {
        stop()
        let letters = word.map { char -> String in
            if char == " " { return "space" }
            if char == "-" { return "hyphen" }
            if char == "'" { return "apostrophe" }
            return String(char).uppercased()
        }
        let parts = [word] + letters + [word]
        speakingText = "spell:" + word
        for (index, part) in parts.enumerated() {
            let utterance = AVSpeechUtterance(string: part)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (index == 0 || index == parts.count - 1 ? 0.8 : 0.7)
            utterance.postUtteranceDelay = index == 0 || index == parts.count - 2 ? 0.4 : 0.15
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        speakingText = nil
    }

    func isSpeaking(_ text: String) -> Bool { speakingText == text }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        _Concurrency.Task { @MainActor in
            if !self.synthesizer.isSpeaking { self.speakingText = nil }
        }
    }
}
