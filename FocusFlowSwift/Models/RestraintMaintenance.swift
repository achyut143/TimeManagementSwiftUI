import Foundation
import SwiftData

// Any release window whose time passed more than `gracePeriod` ago and still
// has no logged instance (or an explicit but never-resolved "pending" one)
// gets auto-marked as Fail. Without this, an unlogged window just sits
// "Pending" forever and silently inflates pass rates/streaks by never
// counting against them. Run on every app launch/foreground.
enum RestraintMaintenance {
    static let gracePeriod: TimeInterval = 24 * 3600
    // How many days back to sweep — old enough windows were already resolved
    // (or resolved by an earlier sweep), no need to walk the whole history.
    private static let lookbackDays = 14

    static func resolveStalePending(restraints: [Restraint], modelContext: ModelContext) {
        let now = Date()
        let cal = Calendar.current
        var didChange = false

        for restraint in restraints {
            if restraint.isAbstinence {
                didChange = resolveAbstinence(restraint, now: now, cal: cal, modelContext: modelContext) || didChange
            } else {
                didChange = resolveWindowed(restraint, now: now, cal: cal, modelContext: modelContext) || didChange
            }
        }

        if didChange {
            try? modelContext.save()
        }
    }

    private static func resolveWindowed(_ restraint: Restraint, now: Date, cal: Calendar, modelContext: ModelContext) -> Bool {
        var didChange = false
        for offset in -lookbackDays...0 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            guard restraint.isScheduledOn(date: day) else { continue }
            for window in restraint.timeWindows {
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = window.hour
                comps.minute = window.minute
                guard let windowDate = cal.date(from: comps) else { continue }
                guard now.timeIntervalSince(windowDate) > gracePeriod else { continue }

                let existing = restraint.instances.first { inst in
                    cal.isDate(inst.date, inSameDayAs: day) &&
                    inst.windowHour == window.hour && inst.windowMinute == window.minute
                }
                if let existing, existing.isPending {
                    existing.status = "fail"
                    existing.notes = existing.notes.isEmpty ? "Auto-marked: not logged in time" : existing.notes
                    didChange = true
                } else if existing == nil {
                    let inst = RestraintInstance(restraint: restraint, date: day, windowHour: window.hour, windowMinute: window.minute)
                    inst.status = "fail"
                    inst.notes = "Auto-marked: not logged in time"
                    modelContext.insert(inst)
                    didChange = true
                }
            }
        }
        return didChange
    }

    private static func resolveAbstinence(_ restraint: Restraint, now: Date, cal: Calendar, modelContext: ModelContext) -> Bool {
        var didChange = false
        for offset in -lookbackDays...0 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            guard restraint.isScheduledOn(date: day) else { continue }
            // A day only resolves once it's fully over.
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: day), now.timeIntervalSince(dayEnd) > gracePeriod else { continue }

            let existing = restraint.instances.first { cal.isDate($0.date, inSameDayAs: day) }
            if let existing, existing.isPending {
                existing.status = "fail"
                existing.notes = existing.notes.isEmpty ? "Auto-marked: not logged in time" : existing.notes
                didChange = true
            } else if existing == nil {
                let inst = RestraintInstance(restraint: restraint, date: day, windowHour: RestraintInstanceRow.abstinenceHour, windowMinute: RestraintInstanceRow.abstinenceMinute)
                inst.status = "fail"
                inst.notes = "Auto-marked: not logged in time"
                modelContext.insert(inst)
                didChange = true
            }
        }
        return didChange
    }
}
