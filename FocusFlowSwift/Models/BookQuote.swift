import Foundation
import SwiftData

enum QuoteSource: String, Codable {
    case ai
    case manual
}

@Model
class BookQuote {
    var id: UUID
    var text: String
    var source: QuoteSource
    var createdAt: Date
    var book: Book?

    init(text: String, source: QuoteSource, book: Book? = nil) {
        self.id = UUID()
        self.text = text
        self.source = source
        self.createdAt = Date()
        self.book = book
    }
}
