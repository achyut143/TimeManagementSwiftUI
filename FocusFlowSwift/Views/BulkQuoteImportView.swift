import SwiftUI
import SwiftData

struct BulkQuoteImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var pastedText = ""
    @State private var extractedQuotes: [GeneratedQuote] = []
    @State private var isExtracting = false
    @State private var extractionError: String?
    @State private var showPreview = false

    // Chapter assignment
    @State private var overrideChapter = false
    @State private var useExistingChapter = true
    @State private var selectedChapterIndex = 0   // index into existingChapters
    @State private var customChapterName = ""

    // Existing chapters derived from the book
    var existingChapters: [(number: Int, name: String)] {
        var byNumber: [Int: String] = [:]
        for quote in (book.quotes ?? []) {
            guard let n = quote.chapterNumber else { continue }
            if byNumber[n] == nil {
                byNumber[n] = quote.chapterName ?? "Chapter \(n)"
            }
        }
        return byNumber.map { (number: $0.key, name: $0.value) }.sorted { $0.number < $1.number }
    }

    // Auto next chapter number = last existing + 1 (or 1 if none)
    var nextChapterNumber: Int {
        (existingChapters.map(\.number).max() ?? 0) + 1
    }

    // The chapter that will be applied when saving
    var resolvedChapter: (number: Int?, name: String?) {
        guard overrideChapter else { return (nil, nil) }
        if useExistingChapter && !existingChapters.isEmpty {
            let ch = existingChapters[min(selectedChapterIndex, existingChapters.count - 1)]
            return (ch.number, ch.name)
        } else {
            return (nextChapterNumber, customChapterName.isEmpty ? nil : customChapterName)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if showPreview {
                    previewView
                } else {
                    pasteView
                }
            }
            .navigationTitle("Bulk Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if showPreview {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save \(extractedQuotes.count)") {
                            saveQuotes()
                        }
                        .fontWeight(.semibold)
                        .disabled(extractedQuotes.isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Paste View

    private var pasteView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste Quotes")
                        .font(.headline)
                    Text("Paste any text — a list of quotes, a chapter excerpt, your own notes. AI will extract each quote.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top)

                TextEditor(text: $pastedText)
                    .frame(minHeight: 180)
                    .padding(12)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .overlay(
                        Group {
                            if pastedText.isEmpty {
                                Text("Paste your quotes here...")
                                    .foregroundStyle(.secondary.opacity(0.5))
                                    .padding(.leading, 16)
                                    .padding(.top, 20)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )
                    .padding(.horizontal)

                // Chapter Assignment
                chapterAssignmentSection

                if let error = extractionError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Button(action: extractQuotes) {
                    HStack {
                        if isExtracting {
                            ProgressView().scaleEffect(0.8)
                            Text("Extracting quotes...")
                        } else {
                            Image(systemName: "wand.and.sparkles")
                            Text("Extract Quotes with AI")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExtracting ? Color.gray : Color.indigo)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExtracting)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    private var chapterAssignmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $overrideChapter) {
                HStack(spacing: 6) {
                    Image(systemName: "books.vertical")
                        .foregroundColor(.indigo)
                    Text("Assign to a chapter")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .tint(.indigo)

            if overrideChapter {
                VStack(alignment: .leading, spacing: 10) {
                    // Existing vs custom picker
                    if !existingChapters.isEmpty {
                        Picker("", selection: $useExistingChapter) {
                            Text("Existing chapter").tag(true)
                            Text("New chapter").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    if useExistingChapter && !existingChapters.isEmpty {
                        // Pick from existing chapters
                        Picker("Chapter", selection: $selectedChapterIndex) {
                            ForEach(Array(existingChapters.enumerated()), id: \.offset) { idx, ch in
                                Text("Ch.\(ch.number) · \(ch.name)").tag(idx)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    } else {
                        // New chapter — number is auto-assigned, just enter name
                        HStack(spacing: 8) {
                            Text("Ch.\(nextChapterNumber)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.indigo)
                                .cornerRadius(6)

                            TextField("Chapter name (optional)", text: $customChapterName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // Preview of the resolved assignment
                    if let num = resolvedChapter.number {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("All quotes → Ch.\(num)\(resolvedChapter.name.map { " · \($0)" } ?? "")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Preview View

    private var previewView: some View {
        List {
            Section {
                Text("AI extracted \(extractedQuotes.count) quote\(extractedQuotes.count == 1 ? "" : "s") from your text. Review and tap Save.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Show chapter assignment summary
                if overrideChapter, let num = resolvedChapter.number {
                    HStack(spacing: 6) {
                        Image(systemName: "books.vertical")
                            .foregroundColor(.indigo)
                            .font(.caption)
                        Text("All quotes will be saved to Ch.\(num)\(resolvedChapter.name.map { " · \($0)" } ?? "")")
                            .font(.caption)
                            .foregroundColor(.indigo)
                    }
                } else if !overrideChapter {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Chapters assigned by AI from extracted text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Button("← Edit Text") {
                    showPreview = false
                }
                .font(.caption)
                .foregroundColor(.indigo)
            }

            Section("Extracted Quotes") {
                ForEach(Array(extractedQuotes.enumerated()), id: \.offset) { _, quote in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(quote.text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)

                        // Show effective chapter
                        let effectiveNum = overrideChapter ? resolvedChapter.number : quote.chapterNumber
                        let effectiveName = overrideChapter ? resolvedChapter.name : quote.chapterName
                        if let chNum = effectiveNum {
                            let label = effectiveName.map { "Ch.\(chNum) · \($0)" } ?? "Ch.\(chNum)"
                            HStack(spacing: 4) {
                                if overrideChapter {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.indigo)
                                }
                                Text(label)
                                    .font(.caption2)
                                    .foregroundColor(.indigo.opacity(0.8))
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Actions

    private func extractQuotes() {
        isExtracting = true
        extractionError = nil
        let text = pastedText
        let existing = (book.quotes ?? []).map { $0.text }
        let title = book.title
        let author = book.author

        _Concurrency.Task {
            do {
                let service = BookQuoteService()
                let quotes = try await service.extractQuotes(from: text, bookTitle: title, author: author, existingQuotes: existing)
                await MainActor.run {
                    extractedQuotes = quotes
                    isExtracting = false
                    showPreview = true
                }
            } catch {
                await MainActor.run {
                    extractionError = error.localizedDescription
                    isExtracting = false
                }
            }
        }
    }

    private func saveQuotes() {
        let chNum = overrideChapter ? resolvedChapter.number : nil
        let chName = overrideChapter ? resolvedChapter.name : nil

        for quote in extractedQuotes {
            let q = BookQuote(
                text: quote.text,
                source: .ai,
                chapterNumber: overrideChapter ? chNum : quote.chapterNumber,
                chapterName: overrideChapter ? chName : quote.chapterName,
                book: book
            )
            modelContext.insert(q)
        }
        try? modelContext.save()
        dismiss()
    }
}
