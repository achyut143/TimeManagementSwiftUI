import SwiftUI
import Speech
import AVFoundation

/// A pending lap: the running schedule slot plus the minute it's being cut at.
/// Captured when "Create Lap" is tapped, so time spent naming the lap doesn't
/// move the split point.
struct LapDraft: Identifiable {
    let id = UUID()
    let startMinutes: Int
    let splitMinutes: Int
    let endMinutes: Int
    let taskName: String
    let startLabel: String
    let splitLabel: String
    let endLabel: String
    // Which schedule block (START…END or BEGIN…STOP) the slot lives in
    var kind: ScheduleKind = .main
}

// MARK: - Dictation

/// Live speech-to-text for a single text field.
final class SpeechDictation: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording { stop() } else { requestPermissionsAndStart() }
    }

    private func requestPermissionsAndStart() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.errorMessage = "Allow Speech Recognition in Settings to dictate."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.errorMessage = "Allow Microphone access in Settings to dictate."
                            return
                        }
                        self.start()
                    }
                }
            }
        }
    }

    private func start() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            // No usable input (e.g. simulator without a mic) — installTap would crash.
            guard format.sampleRate > 0 else {
                errorMessage = "No microphone available."
                restorePlaybackSession()
                return
            }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            transcript = ""
            errorMessage = nil
            isRecording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.isRecording else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }
        } catch {
            errorMessage = "Couldn't start the microphone."
            stop()
        }
    }

    func stop() {
        let wasActive = isRecording || audioEngine.isRunning
        isRecording = false
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        if wasActive { restorePlaybackSession() }
    }

    /// Back to the app-wide session set up in FocusFlowSwiftApp, so spoken
    /// alerts keep working after the mic is released.
    private func restorePlaybackSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

// MARK: - Lap Name Sheet

/// Asks for the name of the finished part of a split task, typed or dictated.
struct LapNameSheet: View {
    let draft: LapDraft
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var dictation = SpeechDictation()
    @State private var name = ""
    // What was in the field when dictation started — the transcript is appended to it.
    @State private var nameBeforeDictation = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField(draft.taskName, text: $name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(save)
                        Button(action: toggleDictation) {
                            Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title)
                                .foregroundColor(dictation.isRecording ? .red : .cyan)
                        }
                        .buttonStyle(.plain)
                    }
                    if dictation.isRecording {
                        Label("Listening…", systemImage: "waveform")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    if let error = dictation.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("Lap: \(draft.startLabel) - \(draft.splitLabel)")
                } footer: {
                    Text("\(draft.splitLabel) - \(draft.endLabel) stays \"\(draft.taskName)\". Leave the name empty to keep it for the lap too.")
                }
            }
            .navigationTitle("Name This Lap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { nameFocused = true }
        .onDisappear { dictation.stop() }
        .onChange(of: dictation.transcript) { _, transcript in
            guard dictation.isRecording, !transcript.isEmpty else { return }
            name = nameBeforeDictation.isEmpty ? transcript : "\(nameBeforeDictation) \(transcript)"
        }
    }

    private func toggleDictation() {
        if !dictation.isRecording {
            nameBeforeDictation = name.trimmingCharacters(in: .whitespaces)
        }
        dictation.toggle()
    }

    private func save() {
        dictation.stop()
        onSave(name)
        dismiss()
    }
}
