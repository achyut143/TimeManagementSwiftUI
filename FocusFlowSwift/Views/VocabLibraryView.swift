import SwiftUI
import SwiftData

/// Every saved word, with search and filters.
struct VocabLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabWord.createdAt, order: .reverse) private var words: [VocabWord]

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All", new = "New", learning = "Learning", weak = "Needs practice", mastered = "Mastered", favorites = "Favorites"
        var id: String { rawValue }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "Newest", alphabetical = "A–Z", weakest = "Weakest first"
        var id: String { rawValue }
    }

    @State private var search = ""
    @State private var levelFilter: VocabLevel?
    @State private var statusFilter: StatusFilter = .all
    @State private var sortOrder: SortOrder = .newest

    private var filtered: [VocabWord] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = words.filter { word in
            if let levelFilter, word.level != levelFilter { return false }
            switch statusFilter {
            case .all: break
            case .new: if word.timesTested > 0 { return false }
            case .learning: if word.masteryLabel != "Learning" { return false }
            case .weak: if word.masteryLabel != "Needs practice" { return false }
            case .mastered: if !word.isMastered { return false }
            case .favorites: if !word.isFavorite { return false }
            }
            if query.isEmpty { return true }
            return word.word.lowercased().contains(query) || word.definition.lowercased().contains(query)
        }
        switch sortOrder {
        case .newest: return list
        case .alphabetical: return list.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        case .weakest: return list.sorted { ($0.accuracy ?? 0.5) < ($1.accuracy ?? 0.5) }
        }
    }

    var body: some View {
        List {
            if words.isEmpty {
                ContentUnavailableView("No words yet", systemImage: "books.vertical",
                                       description: Text("Generate some words in Learn new words."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
            ForEach(filtered) { word in
                NavigationLink { VocabWordDetailView(word: word) } label: {
                    row(word)
                }
            }
            .onDelete { offsets in
                let list = filtered
                for index in offsets { modelContext.delete(list[index]) }
                try? modelContext.save()
            }
        }
        .navigationTitle("My words (\(words.count))")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search words or meanings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Level", selection: $levelFilter) {
                        Text("All levels").tag(VocabLevel?.none)
                        ForEach(VocabLevel.allCases) { Text("\($0.rawValue) · \($0.title)").tag(VocabLevel?.some($0)) }
                    }
                    Picker("Status", selection: $statusFilter) {
                        ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: levelFilter == nil && statusFilter == .all
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    private func row(_ word: VocabWord) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(word.word).font(.headline)
                    if word.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    VocabLevelBadge(level: word.level)
                }
                Text(word.definition)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(word.masteryLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(statusColor(word))
            }
            Spacer()
            VocabSpeakButton(text: word.word)
        }
        .padding(.vertical, 2)
    }

    private func statusColor(_ word: VocabWord) -> Color {
        switch word.masteryLabel {
        case "Mastered": return .green
        case "Learning": return .orange
        case "Needs practice": return .red
        default: return .secondary
        }
    }
}
