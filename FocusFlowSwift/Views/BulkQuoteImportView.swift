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

    private var pasteView: some View {
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
                .frame(maxHeight: .infinity)
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

    private var previewView: some View {
        List {
            Section {
                Text("AI extracted \(extractedQuotes.count) quote\(extractedQuotes.count == 1 ? "" : "s") from your text. Review and tap Save to add them to \"\(book.title)\".")
                    .font(.caption)
                    .foregroundColor(.secondary)

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

                        if let chNum = quote.chapterNumber {
                            let label = quote.chapterName.map { "Ch.\(chNum) · \($0)" } ?? "Ch.\(chNum)"
                            Text(label)
                                .font(.caption2)
                                .foregroundColor(.indigo.opacity(0.8))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

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
        for quote in extractedQuotes {
            let q = BookQuote(
                text: quote.text,
                source: .ai,
                chapterNumber: quote.chapterNumber,
                chapterName: quote.chapterName,
                book: book
            )
            modelContext.insert(q)
        }
        try? modelContext.save()
        dismiss()
    }
}
