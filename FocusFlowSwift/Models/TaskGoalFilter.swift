import SwiftUI
import SwiftData
import Foundation

/// Google Calendar–style "which calendars are visible" filter for tasks.
/// Stored in one AppStorage key so TasksCalendarView, UntimedTasksView and
/// both calendar-task timers always agree.
///
/// Two groups:
/// - Type: Habits (tasks with a repeat value) and General (no repeat).
/// - Goals: each Goal, plus "No Goal".
/// Within a group, ticked items are OR'd; across groups they're AND'd
/// (e.g. Habits + Fitness = habits in the Fitness goal). An empty group
/// doesn't filter anything.
///
/// Raw value: comma-separated tokens — `habitToken`, `generalToken`,
/// `noGoalToken`, and goal UUIDs. "" means show everything.
enum TaskGoalFilter {
    static let storageKey = "tasks.goalFilter"
    static let noGoalToken = "none"
    static let habitToken = "type:habit"
    static let generalToken = "type:general"

    static func selection(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    static func raw(from selection: Set<String>) -> String {
        selection.sorted().joined(separator: ",")
    }

    static func isShowingAll(_ raw: String) -> Bool {
        selection(from: raw).isEmpty
    }

    static func isTypeToken(_ token: String) -> Bool {
        token.hasPrefix("type:")
    }

    static func isHabit(_ task: Task) -> Bool {
        task.repeatAgain != nil
    }

    static func matches(_ task: Task, raw: String) -> Bool {
        let selected = selection(from: raw)
        guard !selected.isEmpty else { return true }

        let typeSel = selected.filter(isTypeToken)
        let goalSel = selected.subtracting(typeSel)

        if !typeSel.isEmpty {
            let token = isHabit(task) ? habitToken : generalToken
            guard typeSel.contains(token) else { return false }
        }

        if !goalSel.isEmpty {
            let token = task.goal?.id.uuidString ?? noGoalToken
            guard goalSel.contains(token) else { return false }
        }

        return true
    }
}

/// Filter menu with checkmarks, like the calendar list in Google Calendar.
/// Nothing checked = all tasks shown.
struct TaskGoalFilterMenu: View {
    @AppStorage(TaskGoalFilter.storageKey) private var filterRaw: String = ""
    @Query(sort: \Goal.name) private var goals: [Goal]

    private var selection: Set<String> { TaskGoalFilter.selection(from: filterRaw) }

    var body: some View {
        Menu {
            Button {
                filterRaw = ""
            } label: {
                if TaskGoalFilter.isShowingAll(filterRaw) {
                    Label("Show All", systemImage: "checkmark")
                } else {
                    Text("Show All")
                }
            }

            Section("Type") {
                toggleButton(title: "Habits", token: TaskGoalFilter.habitToken)
                toggleButton(title: "General", token: TaskGoalFilter.generalToken)
            }

            Section("Goals") {
                ForEach(goals) { goal in
                    toggleButton(title: goal.name, token: goal.id.uuidString)
                }
                toggleButton(title: "No Goal", token: TaskGoalFilter.noGoalToken)
            }
        } label: {
            Label(labelText, systemImage: TaskGoalFilter.isShowingAll(filterRaw)
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .lineLimit(1)
        }
        // Keeps the menu open while ticking several items.
        .menuActionDismissBehavior(.disabled)
    }

    private var labelText: String {
        // Ignore ids of goals that were deleted since they were ticked.
        let names = selection.compactMap(name(for:)).sorted()
        switch names.count {
        case 0: return "All"
        case 1, 2: return names.joined(separator: " · ")
        default: return "\(names.count) filters"
        }
    }

    private func name(for token: String) -> String? {
        switch token {
        case TaskGoalFilter.habitToken: return "Habits"
        case TaskGoalFilter.generalToken: return "General"
        case TaskGoalFilter.noGoalToken: return "No Goal"
        default: return goals.first { $0.id.uuidString == token }?.name
        }
    }

    private func toggleButton(title: String, token: String) -> some View {
        Button {
            var sel = selection
            if sel.contains(token) { sel.remove(token) } else { sel.insert(token) }
            filterRaw = TaskGoalFilter.raw(from: sel)
        } label: {
            if selection.contains(token) {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
