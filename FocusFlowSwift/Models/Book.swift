import Foundation
import SwiftData

@Model
class Book {
    var id: UUID
    var title: String
    var author: String
    var isActive: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \BookQuote.book)
    var quotes: [BookQuote]? = []

    init(title: String, author: String) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.isActive = false
        self.createdAt = Date()
    }
}
