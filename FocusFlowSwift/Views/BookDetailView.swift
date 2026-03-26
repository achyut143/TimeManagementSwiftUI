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
    @State private var isEditingBook = false
    @State private var isSegregating = false
    @State private var segregationError: String?

    var sortedQuotes: [BookQuote] {
        (book.quotes ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var aiCount: Int { book.quotes?.filter { $0.source == .ai }.count ?? 0 }
    var manualCount: Int { book.quotes?.filter { $0.source == .manual }.count ?? 0 }

    // Quotes grouped by chapter, merging any groups that share the same name (handles AI inconsistency)
    var chapterGroups: [(number: Int, name: String, quotes: [BookQuote])] {
        // First pass: group by chapter number
        var byNumber: [Int: (name: String, quotes: [BookQuote])] = [:]
        for quote in (book.quotes ?? []) {
            guard let n = quote.chapterNumber else { continue }
            if byNumber[n] == nil {
                byNumber[n] = (name: quote.chapterName ?? "Chapter \(n)", quotes: [])
            }
            byNumber[n]!.quotes.append(quote)
        }

        // Second pass: merge groups whose names match (case-insensitive), keeping the lowest number
        var nameToCanonicalNumber: [String: Int] = [:]
        var merged: [Int: (name: String, quotes: [BookQuote])] = [:]

        for (num, group) in byNumber.sorted(by: { $0.key < $1.key }) {
            let key = group.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let canonical = nameToCanonicalNumber[key] {
                merged[canonical]!.quotes.append(contentsOf: group.quotes)
            } else {
                nameToCanonicalNumber[key] = num
                merged[num] = group
            }
        }

        return merged
            .map { (number: $0.key, name: $0.value.name, quotes: $0.value.quotes.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.number < $1.number }
    }

    var unassignedQuotes: [BookQuote] {
        (book.quotes ?? []).filter { $0.chapterNumber == nil }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            // Book header
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            if isEditingBook {
                                TextField("Title", text: $book.title)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Author", text: $book.author)
                                    .font(.subheadline)
                                    .textFieldStyle(.roundedBorder)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(book.title)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text(book.author)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
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
                .disabled(isGenerating || isSegregating)

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
                .disabled(isGenerating || isSegregating)

                Button(action: { showAddManualQuote = true }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Add My Own Quote")
                    }
                    .foregroundColor(.green)
                }
                .disabled(isGenerating || isSegregating)

                Button(action: { showBulkImport = true }) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste & Extract Quotes")
                    }
                    .foregroundColor(.orange)
                }
                .disabled(isGenerating || isSegregating)

                if let error = generationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Segregate by Chapter
            if !(book.quotes ?? []).isEmpty {
                Section {
                    Button(action: segregateByChapter) {
                        HStack {
                            if isSegregating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Organising into chapters...")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "books.vertical.fill")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Segregate by Chapter")
                                        .fontWeight(.medium)
                                    Text("AI assigns all quotes to their chapters")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .foregroundColor(isSegregating ? .secondary : .purple)
                    }
                    .disabled(isSegregating || isGenerating)

                    if let error = segregationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            // Quotes grouped by chapter
            ForEach(chapterGroups, id: \.number) { group in
                Section(header: ChapterSectionHeader(
                    number: group.number,
                    name: group.name,
                    count: group.quotes.count
                )) {
                    ForEach(group.quotes) { quote in
                        QuoteRow(quote: quote)
                            .swipeActions(edge: .leading) {
                                Button { editingQuote = quote } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.indigo)
                            }
                    }
                    .onDelete { offsets in deleteQuotesFromList(offsets, in: group.quotes) }
                }
            }

            // Unassigned quotes (no chapter)
            if !unassignedQuotes.isEmpty {
                Section(header: ChapterSectionHeader(
                    number: nil,
                    name: "Unassigned",
                    count: unassignedQuotes.count
                )) {
                    ForEach(unassignedQuotes) { quote in
                        QuoteRow(quote: quote)
                            .swipeActions(edge: .leading) {
                                Button { editingQuote = quote } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.indigo)
                            }
                    }
                    .onDelete { offsets in deleteQuotesFromList(offsets, in: unassignedQuotes) }
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditingBook ? "Done" : "Edit") {
                    withAnimation { isEditingBook.toggle() }
                    if !isEditingBook {
                        try? modelContext.save()
                    }
                }
                .fontWeight(isEditingBook ? .semibold : .regular)
                .foregroundColor(isEditingBook ? .indigo : .accentColor)
            }
        }
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

    private func segregateByChapter() {
        isSegregating = true
        segregationError = nil
        let allQuotes = book.quotes ?? []
        // Pass nil for existing chapter info — AI assigns everything from scratch
        let quoteInputs = allQuotes.map { q in
            (id: q.id, text: q.text, existingChapterNumber: Int?(nil), existingChapterName: String?(nil))
        }
        let bookTitle = book.title
        let author = book.author

        _Concurrency.Task {
            do {
                let service = BookQuoteService()
                let assignments = try await service.segregateIntoChapters(
                    bookTitle: bookTitle,
                    author: author,
                    quotes: quoteInputs
                )

                await MainActor.run {
                    // Clear all existing chapter info first
                    for quote in allQuotes {
                        quote.chapterNumber = nil
                        quote.chapterName = nil
                    }
                    // Apply fresh assignments
                    let assignmentMap = Dictionary(uniqueKeysWithValues: assignments.map { ($0.quoteId, $0) })
                    for quote in allQuotes {
                        if let assignment = assignmentMap[quote.id] {
                            quote.chapterNumber = assignment.chapterNumber
                            quote.chapterName = assignment.chapterName
                        }
                    }
                    try? modelContext.save()
                    isSegregating = false
                }
            } catch {
                await MainActor.run {
                    segregationError = error.localizedDescription
                    isSegregating = false
                }
            }
        }
    }

    private func deleteQuotesFromList(_ offsets: IndexSet, in quotes: [BookQuote]) {
        for index in offsets {
            modelContext.delete(quotes[index])
        }
        try? modelContext.save()
    }
}

struct ChapterSectionHeader: View {
    let number: Int?
    let name: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let n = number {
                Text("CH.\(n)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text(name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Spacer()
            Text("\(count) quote\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .textCase(nil)
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
