import SwiftUI

/// Editable repeat settings for the task forms.
struct RepeatDraft: Equatable {
    var enabled = false
    var kind: RepeatKind = .days
    var interval = 1
    var weekdays: Set<Int> = []
    var monthDays: Set<Int> = []
    var hasEnd = false
    var endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    init() {}

    init(task: Task?) {
        guard let task, let rule = task.repeatRule else { return }
        enabled = true
        kind = rule.kind
        interval = rule.interval
        weekdays = rule.weekdays
        monthDays = rule.monthDays
        if let end = rule.endDate { hasEnd = true; endDate = end }
        fillDefaults(for: task.date ?? Date())
    }

    /// nil = doesn't repeat.
    var rule: RepeatRule? {
        guard enabled else { return nil }
        return RepeatRule(kind: kind, interval: interval,
                          weekdays: kind == .weekly ? weekdays : [],
                          monthDays: kind == .monthly ? monthDays : [],
                          endDate: hasEnd ? endDate : nil)
    }

    /// The legacy "repeat days" number the forms already pass around.
    var repeatAgain: Int { enabled ? max(1, interval) : 0 }

    /// Weekly/monthly with nothing picked: start from the task's own day.
    mutating func fillDefaults(for date: Date) {
        let cal = Calendar.current
        if weekdays.isEmpty { weekdays = [cal.component(.weekday, from: date)] }
        if monthDays.isEmpty { monthDays = [cal.component(.day, from: date)] }
    }

    var summary: String { rule?.summary ?? "Doesn't repeat" }
}

/// One-line row that shows the repeat and opens the editor.
struct RepeatSummaryButton: View {
    @Binding var draft: RepeatDraft
    let taskDate: Date
    var compact = false
    @State private var showing = false

    var body: some View {
        Button {
            draft.fillDefaults(for: taskDate)
            showing = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .foregroundStyle(draft.enabled ? Color.accentColor : .secondary)
                if !compact { Text("Repeat").foregroundStyle(.primary) }
                Spacer(minLength: 4)
                Text(draft.summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) {
            RepeatEditorView(draft: $draft, taskDate: taskDate)
        }
    }
}

/// Every N days, weekly on chosen weekdays, or monthly on chosen dates,
/// with an optional end date.
struct RepeatEditorView: View {
    @Binding var draft: RepeatDraft
    let taskDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Repeat", isOn: $draft.enabled.animation())
                }

                if draft.enabled {
                    Section {
                        Picker("Repeats", selection: $draft.kind) {
                            ForEach(RepeatKind.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        Stepper(value: $draft.interval, in: 1...365) {
                            Text(intervalText)
                        }
                    }

                    switch draft.kind {
                    case .days:
                        EmptyView()
                    case .weekly:
                        Section {
                            weekdayPicker
                        } header: {
                            Text("On these days")
                        } footer: {
                            Text("Pick one or more days.")
                        }
                    case .monthly:
                        Section {
                            monthDayPicker
                        } header: {
                            Text("On these dates")
                        } footer: {
                            Text("Pick one or more dates. A date the month doesn't have (like the 31st) falls on its last day.")
                        }
                    }

                    Section {
                        Toggle("End date", isOn: $draft.hasEnd.animation())
                        if draft.hasEnd {
                            DatePicker("Last day", selection: $draft.endDate,
                                       in: Calendar.current.startOfDay(for: taskDate)...,
                                       displayedComponents: .date)
                        }
                    } footer: {
                        Text(draft.hasEnd
                             ? "No new copies are made after this day."
                             : "Repeats until you turn it off.")
                    }

                    Section {
                        Label(draft.summary, systemImage: "repeat")
                        if let next = draft.rule?.next(after: taskDate) {
                            LabeledContent("Next after this one",
                                           value: next.formatted(.dateTime.weekday(.abbreviated).month().day()))
                        } else {
                            Text("No more repeats after this one (end date).")
                                .foregroundStyle(.orange)
                        }
                    } footer: {
                        Text("Each day you open (today or later) gets its repeat tasks added automatically. Checking a task off also adds the next one.")
                    }
                }
            }
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var isValid: Bool {
        guard draft.enabled else { return true }
        switch draft.kind {
        case .days: return true
        case .weekly: return !draft.weekdays.isEmpty
        case .monthly: return !draft.monthDays.isEmpty
        }
    }

    private var intervalText: String {
        let n = draft.interval
        switch draft.kind {
        case .days: return n == 1 ? "Every day" : "Every \(n) days"
        case .weekly: return n == 1 ? "Every week" : "Every \(n) weeks"
        case .monthly: return n == 1 ? "Every month" : "Every \(n) months"
        }
    }

    private var weekdayPicker: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return HStack(spacing: 6) {
            ForEach(RepeatRule.weekOrder, id: \.self) { day in
                let on = draft.weekdays.contains(day)
                Button {
                    toggle(day, in: &draft.weekdays)
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Circle().fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .foregroundStyle(on ? Color.white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var monthDayPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(1...31, id: \.self) { day in
                let on = draft.monthDays.contains(day)
                Button {
                    toggle(day, in: &draft.monthDays)
                } label: {
                    Text("\(day)")
                        .font(.subheadline.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.accentColor : Color.secondary.opacity(0.12)))
                        .foregroundStyle(on ? Color.white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ value: Int, in set: inout Set<Int>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

/// Delete prompt for a task. Repeating tasks also get "this and future" and
/// "whole series"; other tasks get the plain Delete.
struct TaskDeleteAlert: ViewModifier {
    @Binding var isPresented: Bool
    let task: Task?
    /// Called after deleting, with the scope used.
    let onDeleted: (RepeatSeries.DeleteScope) -> Void
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button("Cancel", role: .cancel) {}
            if let task, task.isInSeries {
                let c = RepeatSeries.counts(for: task, context: modelContext)
                Button("Delete this one only", role: .destructive) { run(.thisOne) }
                if c.future > 1 {
                    Button("Delete this and \(c.future - 1) later", role: .destructive) { run(.thisAndFuture) }
                } else {
                    Button("Delete and stop repeating", role: .destructive) { run(.thisAndFuture) }
                }
                Button("Delete whole series (\(c.all))", role: .destructive) { run(.all) }
            } else {
                Button("Delete", role: .destructive) { run(.thisOne) }
            }
        } message: {
            if let task, task.isInSeries {
                Text("\"\(task.title)\" repeats. \"This and later\" also stops new copies. \"Whole series\" removes its past days too, so its habit history goes.")
            } else {
                Text("Are you sure you want to delete this task?")
            }
        }
    }

    private var title: String { (task?.isInSeries ?? false) ? "Delete repeating task" : "Delete Task" }

    private func run(_ scope: RepeatSeries.DeleteScope) {
        guard let task else { return }
        if task.isInSeries {
            RepeatSeries.delete(task, scope: scope, context: modelContext)
        } else {
            modelContext.delete(task)
            try? modelContext.save()
        }
        onDeleted(scope)
    }
}

extension View {
    func taskDeleteAlert(isPresented: Binding<Bool>, task: Task?, onDeleted: @escaping (RepeatSeries.DeleteScope) -> Void) -> some View {
        modifier(TaskDeleteAlert(isPresented: isPresented, task: task, onDeleted: onDeleted))
    }
}
