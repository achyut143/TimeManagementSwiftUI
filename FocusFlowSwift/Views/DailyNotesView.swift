import SwiftUI
import SwiftData

struct TimeEntry {
    let startMinutes: Int
    let endMinutes: Int
    let description: String
    let isFixed: Bool
    let originalLine: String
    
    var duration: Int {
        return endMinutes - startMinutes
    }
    
    func toLine() -> String {
        let startTime = minutesToTime(startMinutes)
        let endTime = minutesToTime(endMinutes)
        return "\(startTime) - \(endTime) - \(description)"
    }
    
    private func minutesToTime(_ minutes: Int) -> String {
        let adjustedMinutes = minutes >= 0 ? minutes : (minutes % (24 * 60) + 24 * 60)
        let hours = (adjustedMinutes / 60) % 24
        let mins = adjustedMinutes % 60
        return String(format: "%d:%02d", hours, mins)
    }
}

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
                        
                        Text("Use positive numbers to push times forward (+30) or negative to pull back (-15). Fixed tasks marked with **text** remain unchanged.")
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
        
        // Process each line individually while maintaining order
        var result: [String] = []
        var timeEntries: [TimeEntry] = []
        
        // First pass: collect all time entries and identify their positions
        for line in lines {
            if let entry = parseTimeEntry(line) {
                timeEntries.append(entry)
            }
        }
        
        // Apply smart time adjustment
        let adjustedEntries = smartAdjustTimeEntries(timeEntries, byMinutes: minutes)
        
        // Create a mapping of original entries to adjusted entries
        var adjustedMap: [String: [TimeEntry]] = [:]
        var adjustedIndex = 0
        
        for originalEntry in timeEntries {
            var entriesForOriginal: [TimeEntry] = []
            
            // Find all adjusted entries that came from this original entry
            while adjustedIndex < adjustedEntries.count {
                let adjustedEntry = adjustedEntries[adjustedIndex]
                if adjustedEntry.originalLine == originalEntry.originalLine {
                    entriesForOriginal.append(adjustedEntry)
                    adjustedIndex += 1
                } else {
                    break
                }
            }
            
            adjustedMap[originalEntry.originalLine] = entriesForOriginal
        }
        
        // Second pass: reconstruct with proper replacements
        for line in lines {
            if let originalEntry = parseTimeEntry(line) {
                // Replace with adjusted entries
                if let adjustedEntries = adjustedMap[originalEntry.originalLine] {
                    for adjustedEntry in adjustedEntries {
                        result.append(adjustedEntry.toLine())
                    }
                }
            } else {
                // Keep non-time lines as-is (including strikethrough)
                result.append(line)
            }
        }
        
        return result.joined(separator: "\n")
    }
    
    private func smartAdjustTimeEntries(_ entries: [TimeEntry], byMinutes minutes: Int) -> [TimeEntry] {
        guard !entries.isEmpty else { return entries }
        
        var result: [TimeEntry] = []
        
        for entry in entries {
            if entry.isFixed {
                // Fixed entries remain unchanged
                result.append(entry)
            } else {
                // Variable entries get adjusted
                let adjustedStartMinutes = entry.startMinutes + minutes
                let adjustedEndMinutes = entry.endMinutes + minutes
                
                // Check if this conflicts with any fixed task
                var conflictsWithFixed = false
                var conflictingFixedEntry: TimeEntry?
                
                for otherEntry in entries {
                    if otherEntry.isFixed && 
                       adjustedStartMinutes < otherEntry.endMinutes && 
                       adjustedEndMinutes > otherEntry.startMinutes {
                        conflictsWithFixed = true
                        conflictingFixedEntry = otherEntry
                        break
                    }
                }
                
                if conflictsWithFixed, let fixedEntry = conflictingFixedEntry {
                    // Handle conflict by adjusting the variable task to not overlap
                    
                    if adjustedStartMinutes < fixedEntry.startMinutes {
                        // Variable task starts before fixed task
                        // Truncate it to end when fixed task starts
                        let truncatedEntry = TimeEntry(
                            startMinutes: adjustedStartMinutes,
                            endMinutes: fixedEntry.startMinutes,
                            description: entry.description,
                            isFixed: false,
                            originalLine: entry.originalLine
                        )
                        result.append(truncatedEntry)
                        
                        // Calculate remaining duration and add it after the fixed task
                        let usedDuration = fixedEntry.startMinutes - adjustedStartMinutes
                        let remainingDuration = entry.duration - usedDuration
                        
                        if remainingDuration > 0 {
                            let continuedEntry = TimeEntry(
                                startMinutes: fixedEntry.endMinutes,
                                endMinutes: fixedEntry.endMinutes + remainingDuration,
                                description: "\(entry.description) (continued)",
                                isFixed: false,
                                originalLine: entry.originalLine
                            )
                            result.append(continuedEntry)
                        }
                    } else {
                        // Variable task starts during or after fixed task
                        // Move it to start after the fixed task
                        let movedEntry = TimeEntry(
                            startMinutes: fixedEntry.endMinutes,
                            endMinutes: fixedEntry.endMinutes + entry.duration,
                            description: entry.description,
                            isFixed: false,
                            originalLine: entry.originalLine
                        )
                        result.append(movedEntry)
                    }
                } else {
                    // No conflict, normal adjustment
                    let adjustedEntry = TimeEntry(
                        startMinutes: adjustedStartMinutes,
                        endMinutes: adjustedEndMinutes,
                        description: entry.description,
                        isFixed: false,
                        originalLine: entry.originalLine
                    )
                    result.append(adjustedEntry)
                }
            }
        }
        
        return result
    }
    
    private func parseTimeEntry(_ line: String) -> TimeEntry? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip strikethrough lines - check the entire line, not just if it contains ~~
        if trimmedLine.hasPrefix("~~") && trimmedLine.hasSuffix("~~") {
            return nil
        }
        
        // Also skip if the line contains ~~ anywhere (partial strikethrough)
        if trimmedLine.contains("~~") {
            return nil
        }
        
        // Pattern to match time ranges
        let pattern = #"(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*-?\s*(.+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: trimmedLine, range: NSRange(location: 0, length: trimmedLine.utf16.count)),
              let startTimeRange = Range(match.range(at: 1), in: trimmedLine),
              let endTimeRange = Range(match.range(at: 2), in: trimmedLine),
              let descriptionRange = Range(match.range(at: 3), in: trimmedLine) else {
            return nil
        }
        
        let startTimeStr = String(trimmedLine[startTimeRange])
        let endTimeStr = String(trimmedLine[endTimeRange])
        let description = String(trimmedLine[descriptionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let startMinutes = timeToMinutes(startTimeStr),
              let endMinutes = timeToMinutes(endTimeStr) else {
            return nil
        }
        
        // Check if it's a fixed task (marked with **text**)
        let isFixed = description.contains("**")
        
        return TimeEntry(
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            description: description,
            isFixed: isFixed,
            originalLine: line
        )
    }
    
    private func timeToMinutes(_ timeString: String) -> Int? {
        let components = timeString.components(separatedBy: ":")
        guard components.count == 2,
              let hours = Int(components[0]),
              let mins = Int(components[1]) else {
            return nil
        }
        return hours * 60 + mins
    }
    
    private func minutesToTime(_ minutes: Int) -> String {
        let adjustedMinutes = minutes >= 0 ? minutes : (minutes % (24 * 60) + 24 * 60)
        let hours = (adjustedMinutes / 60) % 24
        let mins = adjustedMinutes % 60
        return String(format: "%d:%02d", hours, mins)
    }
    
    private func adjustTime(_ timeString: String, byMinutes minutes: Int) -> String? {
        guard let timeMinutes = timeToMinutes(timeString) else {
            return nil
        }
        
        let adjustedMinutes = timeMinutes + minutes
        return minutesToTime(adjustedMinutes)
    }
}

#Preview {
    DailyNotesView(selectedDate: Date())
        .modelContainer(for: [DailyNote.self], inMemory: true)
}