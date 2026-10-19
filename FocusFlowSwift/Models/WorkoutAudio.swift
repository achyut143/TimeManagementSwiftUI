import AVFoundation
import SwiftUI

/// Voice cues, beeps and background keep-alive for running workouts.
///
/// While a workout runs, an audio engine plays silence so iOS keeps the app
/// (and its timer) running when the phone locks. Music is lowered only while
/// the voice speaks, then restored.
final class WorkoutAudio: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = WorkoutAudio()

    @AppStorage("workout.voiceOn") var voiceOn = true
    @AppStorage("workout.beepsOn") var beepsOn = true

    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let silenceNode = AVAudioPlayerNode()
    private let beepNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var shortBeep: AVAudioPCMBuffer?
    private var longBeep: AVAudioPCMBuffer?
    private var isActive = false
    private var isDucking = false

    private override init() {
        super.init()
        synthesizer.delegate = self
        engine.attach(silenceNode)
        engine.attach(beepNode)
        engine.connect(silenceNode, to: engine.mainMixerNode, format: format)
        engine.connect(beepNode, to: engine.mainMixerNode, format: format)
        shortBeep = tone(frequency: 880, duration: 0.15)
        longBeep = tone(frequency: 1320, duration: 0.45)
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }

    // MARK: Lifecycle

    private var generation = 0

    func begin() {
        generation += 1
        isActive = true
        configureSession(duck: false)
        ensureRunning()
    }

    func end() {
        isActive = false
        synthesizer.stopSpeaking(at: .immediate)
        silenceNode.stop()
        beepNode.stop()
        engine.stop()
        // Back to the app's normal session (see FocusFlowSwiftApp).
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        isDucking = false
    }

    /// Ends after the last cue has had time to play, unless a new workout
    /// (e.g. the next one in a routine) has begun meanwhile.
    func endSoon(after delay: Double = 3) {
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == token else { return }
            self.end()
        }
    }

    /// Called every timer tick: restarts the engine if something else
    /// (an alert, a call) stopped it, so the app stays alive in the background.
    func ensureRunning() {
        guard isActive else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        if engine.isRunning && !silenceNode.isPlaying, let silence = silenceBuffer() {
            silenceNode.scheduleBuffer(silence, at: nil, options: .loops)
            silenceNode.play()
        }
    }

    // MARK: Cues

    func speak(_ text: String) {
        guard voiceOn, !text.isEmpty else { return }
        if !isDucking { configureSession(duck: true) }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1
        synthesizer.speak(utterance)
    }

    /// Short beep for the 3-2-1 countdown; long beep at the change of phase.
    func beep(final: Bool = false) {
        guard beepsOn, let buffer = final ? longBeep : shortBeep else { return }
        ensureRunning()
        guard engine.isRunning else { return }
        beepNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !beepNode.isPlaying { beepNode.play() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Restore music volume once nothing more is queued.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isDucking, !self.synthesizer.isSpeaking else { return }
            self.configureSession(duck: false)
        }
    }

    // MARK: Session

    /// Ducking only applies on activation, so the session is briefly
    /// re-activated to switch it on or off. The engine restarts right after,
    /// far too quickly for iOS to suspend the app.
    private func configureSession(duck: Bool) {
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = duck ? [.mixWithOthers, .duckOthers] : [.mixWithOthers]
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: duck ? .voicePrompt : .default, options: options)
        try? session.setActive(true)
        isDucking = duck
        if isActive || wasRunning {
            try? engine.start()
            ensureRunning()
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard isActive,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        configureSession(duck: false)
    }

    // MARK: Buffers

    private var cachedSilence: AVAudioPCMBuffer?

    private func silenceBuffer() -> AVAudioPCMBuffer? {
        if let cachedSilence { return cachedSilence }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100) else { return nil }
        buffer.frameLength = 44_100 // one second of zeros
        cachedSilence = buffer
        return buffer
    }

    private func tone(frequency: Double, duration: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let fade = Int(format.sampleRate * 0.01)
        for i in 0..<Int(frames) {
            // Short fade in/out avoids clicks.
            let envelope = min(1, Double(min(i, Int(frames) - i)) / Double(fade))
            samples[i] = Float(sin(2 * .pi * frequency * Double(i) / format.sampleRate) * 0.6 * envelope)
        }
        return buffer
    }
}
