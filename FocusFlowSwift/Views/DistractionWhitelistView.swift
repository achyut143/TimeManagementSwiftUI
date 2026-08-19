import SwiftUI

// Manages which task names have their distraction time tracked. An empty list
// means "track everything" (the original behavior); a non-empty list restricts
// tracking to only those task names.
struct DistractionWhitelistView: View {
    @Binding var whitelistRaw: String
    @Environment(\.dismiss) private var dismiss
    @State private var newEntry: String = ""

    private var entries: [String] {
        whitelistRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Task name (e.g. work)", text: $newEntry)
                            .autocorrectionDisabled()
                        Button("Add") { addEntry() }
                            .disabled(newEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("Only tasks in this list have their distraction time tracked — everything else is ignored. Leave the list empty to track every task, as before. Parenthetical detail like \"work (office)\" is ignored when matching — it's treated as \"work\".")
                }

                if !entries.isEmpty {
                    Section("Whitelisted Tasks") {
                        ForEach(entries, id: \.self) { entry in
                            Text(entry)
                        }
                        .onDelete(perform: removeEntries)
                    }
                }
            }
            .navigationTitle("Distraction Whitelist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addEntry() {
        let trimmed = newEntry.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = entries
        guard !current.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newEntry = ""
            return
        }
        current.append(trimmed)
        whitelistRaw = current.joined(separator: ", ")
        newEntry = ""
    }

    private func removeEntries(at offsets: IndexSet) {
        var current = entries
        current.remove(atOffsets: offsets)
        whitelistRaw = current.joined(separator: ", ")
    }
}
