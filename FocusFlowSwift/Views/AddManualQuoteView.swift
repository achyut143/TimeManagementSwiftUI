import SwiftUI
import SwiftData

struct AddManualQuoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let book: Book

    @State private var quoteText = ""
    @State private var isDuplicate = false

    var trimmed: String { quoteText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSave: Bool { trimmed.count >= 10 && !isDuplicate }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if quoteText.isEmpty {
                            Text("Type your quote here...")
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $quoteText)
                            .frame(minHeight: 120)
                    }

                    HStack {
                        Text("\(trimmed.count) characters")
                            .font(.caption2)
                            .foregroundColor(trimmed.count < 10 ? .red : .secondary)
                        Spacer()
                        if isDuplicate {
                            Label("Already exists in this book", systemImage: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("Quote Text")
                } footer: {
                    Text("Minimum 10 characters required")
                }
            }
            .navigationTitle("Add Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: quoteText) { _, _ in
                checkDuplicate()
            }
        }
    }

    private func checkDuplicate() {
        let existing = (book.quotes ?? []).map {
            $0.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        isDuplicate = existing.contains(trimmed.lowercased())
    }

    private func save() {
        let quote = BookQuote(text: trimmed, source: .manual, book: book)
        modelContext.insert(quote)
        try? modelContext.save()
        dismiss()
    }
}
