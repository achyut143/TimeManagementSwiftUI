import SwiftUI
import SwiftData

struct BooksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]

    @State private var showAddBook = false
    @State private var tooManyActiveAlert = false

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
                        if activeCount > 0 {
                            Section {
                                Text("Active books rotate their quotes every 10 seconds in your Daily Notes and task views.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } header: {
                                Text("\(activeCount) of 5 books active")
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
            .alert("Too Many Active Books", isPresented: $tooManyActiveAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can only activate 5 books at a time. Deactivate one first.")
            }
        }
    }

    private func toggleActive(_ book: Book) {
        if !book.isActive && activeCount >= 5 {
            tooManyActiveAlert = true
            return
        }
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
