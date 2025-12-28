import SwiftUI
import SwiftData

struct DailyNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var dailyNotes: [DailyNote]
    @State private var notesText: String = ""
    @State private var adjustmentMinutes: String = ""
    @State private var editorKey: UUID = UUID() // Force editor refresh
    let selectedDate: Date
    
    private var todayNote: DailyNote? {
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        return dailyNotes.first { Calendar.current.isDate($0.date, inSameDayAs: startOfDay) }
    }
    
    private func getNoteForDate(_ date: Date) -> DailyNote? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return dailyNotes.first { Calendar.current.isDate($0.date, inSameDayAs: startOfDay) }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Time Adjustment") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Adjust times by (minutes):")
                            TextField("+30 or -15", text: $adjustmentMinutes)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 100)
                            Button("Apply") {
                                adjustTimesInNotes()
                            }
                            .disabled(adjustmentMinutes.isEmpty)
                        }
                        
                        // Quick adjustment buttons
                        HStack(spacing: 8) {
                            Text("Quick:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("-30") {
                                adjustmentMinutes = "-30"
                                adjustTimesInNotes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("-15") {
                                adjustmentMinutes = "-15"
                                adjustTimesInNotes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("+15") {
                                adjustmentMinutes = "15"
                                adjustTimesInNotes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("+30") {
                                adjustmentMinutes = "30"
                                adjustTimesInNotes()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Text("Use positive numbers to push times forward (+30) or negative to pull back (-15)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Daily Notes") {
                    RichTextEditor(text: $notesText)
                        .frame(height: 300)
                        .id(editorKey) // Force refresh when key changes
                }
            }
            .navigationTitle("Daily Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNotes()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadNotesForDate(selectedDate)
            }
            .onChange(of: selectedDate) { _, _ in
                loadNotesForDate(selectedDate)
            }
        }
    }
    
    private func loadNotesForDate(_ date: Date) {
        if let existingNote = getNoteForDate(date) {
            notesText = existingNote.content
        } else {
            notesText = ""
        }
        // Refresh editor when loading new content
        editorKey = UUID()
    }
    
    private func saveNotes() {
        if let existingNote = getNoteForDate(selectedDate) {
            existingNote.updateContent(notesText)
        } else if !notesText.isEmpty {
            let newNote = DailyNote(date: selectedDate, content: notesText)
            modelContext.insert(newNote)
        }
        
        try? modelContext.save()
    }
    
    private func adjustTimesInNotes() {
        guard let minutes = Int(adjustmentMinutes) else { 
            print("Invalid minutes input: \(adjustmentMinutes)")
            return 
        }
        
        // Find START and END tags
        let startTag = "START"
        let endTag = "END"
        
        guard let startRange = notesText.range(of: startTag),
              let endRange = notesText.range(of: endTag) else {
            print("Could not find START and END tags")
            return
        }
        
        // Extract content between START and END
        let contentStart = startRange.upperBound
        let contentEnd = endRange.lowerBound
        let content = String(notesText[contentStart..<contentEnd])
        
        print("Content to process: '\(content)'")
        
        // Parse and adjust times
        let adjustedContent = adjustTimeRanges(in: content, byMinutes: minutes)
        
        print("Adjusted content: '\(adjustedContent)'")
        
        // Replace the content between START and END
        let beforeStart = String(notesText[..<startRange.lowerBound])
        let afterEnd = String(notesText[endRange.upperBound...])
        
        notesText = beforeStart + startTag + adjustedContent + endTag + afterEnd
        
        // Force the editor to refresh by changing its key
        editorKey = UUID()
    }
    
    private func adjustTimeRanges(in content: String, byMinutes minutes: Int) -> String {
        let lines = content.components(separatedBy: .newlines)
        var adjustedLines: [String] = []
        
        for line in lines {
            let adjustedLine = adjustTimeRangeInLine(line, byMinutes: minutes)
            adjustedLines.append(adjustedLine)
        }
        
        return adjustedLines.joined(separator: "\n")
    }
    
    private func adjustTimeRangeInLine(_ line: String, byMinutes minutes: Int) -> String {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pattern to match time ranges with flexible format:
        // "12:30 - 1:00 - work" or "12:30 - 1:00 work" or "12:30- 1:00 work"
        let pattern = #"(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*-?\s*(.+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            print("Failed to create regex")
            return line
        }
        
        let range = NSRange(location: 0, length: trimmedLine.utf16.count)
        let matches = regex.matches(in: trimmedLine, options: [], range: range)
        
        guard let match = matches.first else {
            print("No match found for line: '\(trimmedLine)'")
            return line
        }
        
        print("Found match in line: '\(trimmedLine)'")
        
        guard let startTimeRange = Range(match.range(at: 1), in: trimmedLine),
              let endTimeRange = Range(match.range(at: 2), in: trimmedLine),
              let descriptionRange = Range(match.range(at: 3), in: trimmedLine) else {
            print("Failed to extract ranges from match")
            return line
        }
        
        let startTimeStr = String(trimmedLine[startTimeRange])
        let endTimeStr = String(trimmedLine[endTimeRange])
        let description = String(trimmedLine[descriptionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("Extracted: start='\(startTimeStr)', end='\(endTimeStr)', desc='\(description)'")
        
        guard let adjustedStartTime = adjustTime(startTimeStr, byMinutes: minutes),
              let adjustedEndTime = adjustTime(endTimeStr, byMinutes: minutes) else {
            print("Failed to adjust times")
            return line
        }
        
        let result = "\(adjustedStartTime) - \(adjustedEndTime) - \(description)"
        print("Adjusted line: '\(result)'")
        return result
    }
    
    private func adjustTime(_ timeString: String, byMinutes minutes: Int) -> String? {
        let components = timeString.components(separatedBy: ":")
        guard components.count == 2,
              let hours = Int(components[0]),
              let mins = Int(components[1]) else {
            print("Failed to parse time: '\(timeString)'")
            return nil
        }
        
        let totalMinutes = hours * 60 + mins + minutes
        
        // Handle negative times by wrapping to previous day
        let adjustedTotalMinutes = totalMinutes >= 0 ? totalMinutes : (totalMinutes % (24 * 60) + 24 * 60)
        
        let newHours = (adjustedTotalMinutes / 60) % 24
        let newMins = adjustedTotalMinutes % 60
        
        let result = String(format: "%d:%02d", newHours, newMins)
        print("Adjusted '\(timeString)' by \(minutes) minutes to '\(result)'")
        return result
    }
}

#Preview {
    DailyNotesView(selectedDate: Date())
        .modelContainer(for: [DailyNote.self], inMemory: true)
}