import SwiftUI
import SwiftData

// MARK: - If-then

struct IfThenPlansView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IfThenPlan.sortOrder) private var plans: [IfThenPlan]

    var body: some View {
        List {
            Section {
                ForEach(plans) { plan in
                    IfThenRow(plan: plan)
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
            } footer: {
                Text("Predict where you're likely to slip and decide your response now.")
            }

            Section {
                Button {
                    modelContext.insert(IfThenPlan(sortOrder: (plans.last?.sortOrder ?? -1) + 1))
                } label: {
                    Label("Add if-then plan", systemImage: "plus")
                }
            } footer: {
                // Room for the floating timer buttons
                Color.clear.frame(height: 60)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("If-then plans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
        }
        .onAppear { IfThenPlan.seedIfNeeded(context: modelContext) }
        .onDisappear { try? modelContext.save() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(plans[index])
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = plans
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, plan) in reordered.enumerated() {
            plan.sortOrder = index
        }
    }
}

private struct IfThenRow: View {
    @Bindable var plan: IfThenPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text("If")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                    .frame(width: 36, alignment: .leading)
                TextField("this happens…", text: $plan.trigger, axis: .vertical)
            }
            HStack(alignment: .top, spacing: 8) {
                Text("Then")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                    .frame(width: 36, alignment: .leading)
                TextField("I will…", text: $plan.response, axis: .vertical)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }
}
