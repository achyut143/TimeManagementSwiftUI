import SwiftUI
import SwiftData

struct EditQuoteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var quote: BookQuote

    @State private var text: String = ""
    @State private var chapterNumber: String = ""
    @State private var chapterName: String = ""
    @State private var saveError: String?

    var existingTexts: [String] {
        (quote.book?.quotes ?? [])
            .filter { $0.id != quote.id }
            .map { $0.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Quote Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 100)
                }

                Section("Chapter (Optional)") {
                    TextField("Chapter number", text: $chapterNumber)
                        .keyboardType(.numberPad)
                    TextField("Chapter name", text: $chapterName)
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
            }
            .onAppear {
                text = quote.text
                chapterNumber = quote.chapterNumber.map { "\($0)" } ?? ""
                chapterName = quote.chapterName ?? ""
            }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return }

        if existingTexts.contains(trimmed.lowercased()) {
            saveError = "This quote already exists in the book."
            return
        }

        quote.text = trimmed
        quote.chapterNumber = Int(chapterNumber.trimmingCharacters(in: .whitespaces))
        quote.chapterName = chapterName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : chapterName.trimmingCharacters(in: .whitespaces)
        try? modelContext.save()
        dismiss()
    }
}
