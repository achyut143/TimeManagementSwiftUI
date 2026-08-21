import SwiftUI
import SwiftData

struct RestraintListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Restraint.createdAt, order: .reverse) private var restraints: [Restraint]

    @State private var showCreate = false
    @State private var createKind: RestraintKind = .restraint
    @State private var restraintToEdit: Restraint?
    @State private var restraintToDelete: Restraint?
    @State private var showDeleteConfirm = false
    @State private var showTrends = false

    private var restraintItems: [Restraint] { restraints.filter { $0.kind == .restraint } }
    private var practiceItems: [Restraint] { restraints.filter { $0.kind == .practice } }

    var body: some View {
        List {
            if restraints.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No rules yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap + to create a Restraint (something to limit) or a Practice (something to do regularly)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                kindSection(.restraint, items: restraintItems)
                kindSection(.practice, items: practiceItems)
            }
        }
        .navigationTitle("Rules")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    NavigationLink(destination: AllRestraintInstancesView()) {
                        Image(systemName: "checklist")
                            .foregroundColor(.indigo)
                    }
                    NavigationLink(destination: RestraintChartsView()) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.indigo)
                    }
                    Button(action: { showTrends = true }) {
                        Image(systemName: "chart.xyaxis.line")
                            .foregroundColor(.indigo)
                    }
                    Menu {
                        Button(action: { createKind = .restraint; showCreate = true }) {
                            Label("New Restraint", systemImage: "hand.raised.fill")
                        }
                        Button(action: { createKind = .practice; showCreate = true }) {
                            Label("New Practice", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showTrends) {
            RestraintTrendsView()
        }
        .sheet(isPresented: $showCreate) {
            CreateRestraintView(initialKind: createKind)
        }
        .sheet(item: $restraintToEdit) { r in
            CreateRestraintView(restraint: r)
        }
        .confirmationDialog("Delete this rule?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let r = restraintToDelete { modelContext.delete(r) }
                try? modelContext.save()
                RestraintNotificationScheduler.rescheduleAll(from: restraints.filter { $0.id != restraintToDelete?.id })
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes it and all its logged instances.")
        }
    }

    @ViewBuilder
    private func kindSection(_ kind: RestraintKind, items: [Restraint]) -> some View {
        if !items.isEmpty {
            Section(kind.pluralName) {
                ForEach(items) { r in
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
    }
}

private struct RestraintRowView: View {
    @Environment(\.modelContext) private var modelContext
    let restraint: Restraint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: restraint.iconName)
                    .foregroundColor(restraint.displayColor)
                Text(restraint.name)
                    .font(.headline)
                Spacer()
                Button {
                    restraint.showInFocusWidget.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: restraint.showInFocusWidget ? "eye.fill" : "eye.slash")
                        .foregroundColor(restraint.showInFocusWidget ? .indigo : .secondary)
                }
                .buttonStyle(.plain)
                limitBadge
            }
            HStack(spacing: 8) {
                Text(restraint.weekdayNames)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if restraint.isAbstinence {
                    Text("Zero-Tolerance")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                }
                let streak = restraint.currentPassStreak()
                if streak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                        Text("\(streak)")
                    }
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                }
            }
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
        let verb = restraint.kind == .restraint ? "awarded" : "goal"
        if restraint.effectiveLimitType == .duration {
            Text("\(restraint.awardedMinutes) min \(verb)")
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
            Text("\(qty) \(restraint.quantityUnit) \(verb)")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.12))
                .foregroundColor(.orange)
                .clipShape(Capsule())
        }
    }
}
