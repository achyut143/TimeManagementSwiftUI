import SwiftUI
import SwiftData

struct BooksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]

    @State private var showAddBook = false

    @AppStorage("display.quotesVisible") private var quotesVisible: Bool = true
    @AppStorage("display.tasksVisible") private var tasksVisible: Bool = true
    @AppStorage("display.quotesInterval") private var quotesInterval: Int = 10
    @AppStorage("display.tasksInterval") private var tasksInterval: Int = 10

    var activeCount: Int { books.filter { $0.isActive }.count }

    var body: some View {
        NavigationView {
            Group {
                if books.isEmpty {
                    ContentUnavailableView(
                        "No Books Yet",
                        systemImage: "books.vertical",
                        description: Text("Add a book to start generating and storing quotes")
                    )
                } else {
                    List {
                        Section("Display Settings") {
                            Toggle(isOn: $quotesVisible) {
                                Label("Show Book Quotes", systemImage: "books.vertical.fill")
                                    .foregroundColor(.indigo)
                            }
                            .tint(.indigo)

                            if quotesVisible {
                                Stepper(value: $quotesInterval, in: 5...60, step: 5) {
                                    HStack(spacing: 4) {
                                        Text("Quotes cycle every")
                                            .foregroundColor(.secondary)
                                        Text("\(quotesInterval)s")
                                            .fontWeight(.semibold)
                                            .foregroundColor(.indigo)
                                    }
                                    .font(.subheadline)
                                }
                            }

                            Toggle(isOn: $tasksVisible) {
                                Label("Show Pending Tasks", systemImage: "clock.badge.exclamationmark")
                                    .foregroundColor(.orange)
                            }
                            .tint(.orange)

                            if tasksVisible {
                                Stepper(value: $tasksInterval, in: 5...60, step: 5) {
                                    HStack(spacing: 4) {
                                        Text("Tasks cycle every")
                                            .foregroundColor(.secondary)
                                        Text("\(tasksInterval)s")
                                            .fontWeight(.semibold)
                                            .foregroundColor(.orange)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }

                        if activeCount > 0 {
                            Section {
                                Text("Active books rotate their quotes at the interval set above.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } header: {
                                Text("\(activeCount) book\(activeCount == 1 ? "" : "s") active")
                            }
                        }

                        Section("Your Books") {
                            ForEach(books) { book in
                                NavigationLink(destination: BookDetailView(book: book)) {
                                    BookListRow(book: book, onToggleActive: {
                                        toggleActive(book)
                                    })
                                }
                            }
                            .onDelete(perform: deleteBooks)
                        }
                    }
                }
            }
            .navigationTitle("Books Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddBook = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddBook) {
                AddBookView()
            }
        }
    }

    private func toggleActive(_ book: Book) {
        book.isActive.toggle()
        try? modelContext.save()
    }

    private func deleteBooks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(books[index])
        }
        try? modelContext.save()
    }
}

struct BookListRow: View {
    let book: Book
    let onToggleActive: () -> Void

    var quoteCount: Int { book.quotes?.count ?? 0 }
    var aiCount: Int { book.quotes?.filter { $0.source == .ai }.count ?? 0 }
    var manualCount: Int { book.quotes?.filter { $0.source == .manual }.count ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(quoteCount) quotes")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if aiCount > 0 {
                        Text("\(aiCount) AI")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }

                    if manualCount > 0 {
                        Text("\(manualCount) Manual")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            Button(action: onToggleActive) {
                Image(systemName: book.isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(book.isActive ? .indigo : .gray)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
