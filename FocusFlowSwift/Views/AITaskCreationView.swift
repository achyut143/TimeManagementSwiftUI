import SwiftUI
import AVFoundation
import Speech

struct AITaskCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var aiInput = ""
    @State private var isRecording = false
    @State private var audioEngine = AVAudioEngine()
    @State private var speechRecognizer = SFSpeechRecognizer()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var isProcessing = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("AI Task Creation")
                    .font(.title2)
                    .fontWeight(.medium)
                
                VStack(spacing: 16) {
                    TextEditor(text: $aiInput)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    HStack {
                        Button(action: toggleRecording) {
                            Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title)
                                .foregroundColor(isRecording ? .red : .blue)
                        }
                        .disabled(speechRecognizer == nil)
                        
                        Spacer()
                        
                        Button("Generate Tasks") {
                            generateTaskFromAI()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(aiInput.isEmpty || isProcessing)
                    }
                }
                
                if isProcessing {
                    ProgressView("Processing...")
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            requestSpeechPermission()
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else { return }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                aiInput = result.bestTranscription.formattedString
            }
            
            if error != nil || result?.isFinal == true {
                stopRecording()
            }
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        isRecording = true
    }
    
    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
    
    private func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    break
                case .denied, .restricted, .notDetermined:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func generateTaskFromAI() {
        isProcessing = true
        
        _Concurrency.Task {
            do {
                let openAI = OpenAIService()
                let tasksData = try await openAI.generateTasks(from: aiInput)
                print("Generated Tasks Data: \(tasksData)")
                
                DispatchQueue.main.async {
                    for taskData in tasksData {
                        let taskDate = self.parseDate(from: taskData.date)
                        let newTask = Task(
                            title: taskData.title,
                            taskDescription: taskData.description,
                            startTime: self.convertTo24Hour(taskData.startTime),
                            endTime: self.convertTo24Hour(taskData.endTime),
                            weight: taskData.weight,
                            date: taskDate
                        )
                        print("New Task: \(newTask)")
                        
                        self.modelContext.insert(newTask)
                    }
                    try? self.modelContext.save()
                    
                    // Post notification to refresh calendar
                    NotificationCenter.default.post(name: NSNotification.Name("TaskCreated"), object: nil)
                    
                    self.isProcessing = false
                    self.dismiss()
                }
            } catch {
                print("Error generating task: \(error)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.createTaskWithFallback()
                }
            }
        }
    }
    
    private func createTaskWithFallback() {
        let newTask = Task(
            title: aiInput.components(separatedBy: .newlines).first ?? "AI Task",
            taskDescription: "ai-generated",
            startTime: formatTime(Date()),
            endTime: formatTime(Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()),
            weight: 5.0,
            date: Date()
        )
        
        modelContext.insert(newTask)
        try? modelContext.save()
        dismiss()
    }
    

    
    private func convertTo24Hour(_ timeString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        guard let date = formatter.date(from: timeString) else {
            return timeString
        }
        
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func parseDate(from dateString: String) -> Date {
        if dateString.lowercased() == "today" {
            return Date()
        }
        if dateString.lowercased() == "tomorrow" {
            return Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString) ?? Date()
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}