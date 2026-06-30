import SwiftUI
import SwiftData

struct RestraintListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Restraint.createdAt, order: .reverse) private var restraints: [Restraint]

    @State private var showCreate = false
    @State private var restraintToEdit: Restraint?
    @State private var restraintToDelete: Restraint?
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            if restraints.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No restraints yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap + to create your first restraint")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                ForEach(restraints) { r in
                    NavigationLink(destination: RestraintInstancesView(restraint: r)) {
                        RestraintRowView(restraint: r)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            restraintToDelete = r
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            restraintToEdit = r
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button(action: { restraintToEdit = r }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive, action: {
                            restraintToDelete = r
                            showDeleteConfirm = true
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Restraints")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    NavigationLink(destination: RestraintChartsView()) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.indigo)
                    }
                    Button(action: { showCreate = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateRestraintView()
        }
        .sheet(item: $restraintToEdit) { r in
            CreateRestraintView(restraint: r)
        }
        .confirmationDialog("Delete Restraint?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let r = restraintToDelete { modelContext.delete(r) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the restraint and all its logged instances.")
        }
    }
}

private struct RestraintRowView: View {
    let restraint: Restraint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(restraint.name)
                    .font(.headline)
                Spacer()
                limitBadge
            }
            Text(restraint.weekdayNames)
                .font(.caption)
                .foregroundColor(.secondary)
            let windows = restraint.timeWindows
            if !windows.isEmpty {
                Text(windows.map { $0.timeString }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var limitBadge: some View {
        if restraint.effectiveLimitType == .duration {
            Text("\(restraint.awardedMinutes) min awarded")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.12))
                .foregroundColor(.blue)
                .clipShape(Capsule())
        } else {
            let qty = restraint.quantityLimit == restraint.quantityLimit.rounded()
                ? "\(Int(restraint.quantityLimit))"
                : String(format: "%.1f", restraint.quantityLimit)
            Text("\(qty) \(restraint.quantityUnit) awarded")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.12))
                .foregroundColor(.orange)
                .clipShape(Capsule())
        }
    }
}
