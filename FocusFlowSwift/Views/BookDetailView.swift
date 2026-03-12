import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var book: Book

    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var showAddManualQuote = false
    @State private var showBulkImport = false
    @State private var generateCount: Int = 25
    @State private var editingQuote: BookQuote?

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
                Stepper(value: $generateCount, in: 5...100, step: 5) {
                    HStack {
                        Text("Generate")
                            .foregroundColor(.secondary)
                        Text("\(generateCount)")
                            .fontWeight(.semibold)
                            .foregroundColor(.indigo)
                        Text("quotes")
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(isGenerating)

                Button(action: generateQuotes) {
                    HStack {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Generating \(generateCount) quotes...")
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "sparkles")
                            Text(sortedQuotes.isEmpty ? "Generate \(generateCount) Quotes" : "Generate \(generateCount) More")
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

                Button(action: { showBulkImport = true }) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste & Extract Quotes")
                    }
                    .foregroundColor(.orange)
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
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingQuote = quote
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.indigo)
                            }
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
        .sheet(isPresented: $showBulkImport) {
            BulkQuoteImportView(book: book)
        }
        .sheet(item: $editingQuote) { quote in
            EditQuoteView(quote: quote)
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
                let generatedQuotes = try await service.generateQuotes(
                    bookTitle: bookTitle,
                    author: author,
                    existingQuotes: existingTexts,
                    count: generateCount
                )

                await MainActor.run {
                    for generated in generatedQuotes {
                        let quote = BookQuote(
                            text: generated.text,
                            source: .ai,
                            chapterNumber: generated.chapterNumber,
                            chapterName: generated.chapterName,
                            book: book
                        )
                        modelContext.insert(quote)
                    }
                    try? modelContext.save()
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
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

                if let chNum = quote.chapterNumber {
                    let chLabel = quote.chapterName.map { "Ch.\(chNum) · \($0)" } ?? "Ch.\(chNum)"
                    Text(chLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(quote.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
