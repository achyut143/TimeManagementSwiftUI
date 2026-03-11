import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var book: Book

    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var showAddManualQuote = false

    var sortedQuotes: [BookQuote] {
        (book.quotes ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var aiCount: Int { book.quotes?.filter { $0.source == .ai }.count ?? 0 }
    var manualCount: Int { book.quotes?.filter { $0.source == .manual }.count ?? 0 }

    var body: some View {
        List {
            // Book header
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title)
                                .font(.title2)
                                .fontWeight(.bold)
                            Text(book.author)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if book.isActive {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.indigo)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.indigo.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }

                    HStack(spacing: 8) {
                        Label("\(book.quotes?.count ?? 0) total", systemImage: "quote.bubble")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if aiCount > 0 {
                            Text("\(aiCount) AI")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }

                        if manualCount > 0 {
                            Text("\(manualCount) Manual")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Actions
            Section("Add Quotes") {
                Button(action: generateQuotes) {
                    HStack {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Generating quotes...")
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "sparkles")
                            Text(sortedQuotes.isEmpty ? "Generate 25 Quotes" : "Generate 25 More")
                        }
                    }
                    .foregroundColor(isGenerating ? .secondary : .indigo)
                }
                .disabled(isGenerating)

                Button(action: { showAddManualQuote = true }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Add My Own Quote")
                    }
                    .foregroundColor(.green)
                }
                .disabled(isGenerating)

                if let error = generationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Saved quotes list
            if !sortedQuotes.isEmpty {
                Section("Saved Quotes (\(sortedQuotes.count))") {
                    ForEach(sortedQuotes) { quote in
                        QuoteRow(quote: quote)
                    }
                    .onDelete(perform: deleteQuotes)
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddManualQuote) {
            AddManualQuoteView(book: book)
        }
    }

    private func generateQuotes() {
        isGenerating = true
        generationError = nil
        let existingTexts = (book.quotes ?? []).map { $0.text }
        let bookTitle = book.title
        let author = book.author

        _Concurrency.Task {
            do {
                let service = BookQuoteService()
                let newTexts = try await service.generateQuotes(
                    bookTitle: bookTitle,
                    author: author,
                    existingQuotes: existingTexts
                )

                await MainActor.run {
                    for text in newTexts {
                        let quote = BookQuote(text: text, source: .ai, book: book)
                        modelContext.insert(quote)
                    }
                    try? modelContext.save()
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    generationError = "Failed to generate quotes. Check your API key and try again."
                    isGenerating = false
                }
            }
        }
    }

    private func deleteQuotes(at offsets: IndexSet) {
        let sorted = sortedQuotes
        for index in offsets {
            modelContext.delete(sorted[index])
        }
        try? modelContext.save()
    }
}

struct QuoteRow: View {
    let quote: BookQuote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(quote.text)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(quote.source == .ai ? "AI" : "Manual")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(quote.source == .ai ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                    .foregroundColor(quote.source == .ai ? .blue : .green)
                    .cornerRadius(4)

                Text(quote.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
