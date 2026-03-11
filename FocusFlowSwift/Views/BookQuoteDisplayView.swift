import SwiftUI
import SwiftData

struct BookQuoteDisplayView: View {
    @Query(filter: #Predicate<Book> { $0.isActive }) private var activeBooks: [Book]

    @State private var currentIndex: Int = 0
    @State private var showQuote: Bool = true
    @State private var quotePool: [(text: String, bookTitle: String, author: String)] = []
    @State private var cycleTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if quotePool.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Activate a book in the Books library to see quotes here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else {
                let quote = quotePool[currentIndex]
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "quote.opening")
                            .foregroundColor(.indigo)
                            .font(.caption)
                        Spacer()
                        Image(systemName: "quote.closing")
                            .foregroundColor(.indigo)
                            .font(.caption)
                    }

                    if showQuote {
                        Text(quote.text)
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                            )
                            .id("quote-\(currentIndex)")

                        Text("— \(quote.author), \(quote.bookTitle)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                            .transition(.opacity)
                            .id("attr-\(currentIndex)")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.indigo.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.indigo.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .onAppear {
            buildQuotePool()
            startCycling()
        }
        .onDisappear {
            stopCycling()
        }
        .onChange(of: activeBooks.count) { _, _ in
            buildQuotePool()
        }
    }

    private func buildQuotePool() {
        var pool: [(text: String, bookTitle: String, author: String)] = []
        for book in activeBooks {
            for quote in book.quotes ?? [] {
                pool.append((text: quote.text, bookTitle: book.title, author: book.author))
            }
        }
        quotePool = pool.shuffled()
        currentIndex = 0
    }

    private func startCycling() {
        guard cycleTimer == nil else { return }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            advanceQuote()
        }
    }

    private func stopCycling() {
        cycleTimer?.invalidate()
        cycleTimer = nil
    }

    private func advanceQuote() {
        guard quotePool.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            showQuote = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            currentIndex = (currentIndex + 1) % quotePool.count
            withAnimation(.easeInOut(duration: 0.4)) {
                showQuote = true
            }
        }
    }
}
