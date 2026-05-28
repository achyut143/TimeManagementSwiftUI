import Foundation
import SwiftUI
import SwiftData

// MARK: - Time Block Type

enum DayBlockType: String, CaseIterable, Identifiable {
    case morning      = "morning"
    case midMorning   = "midMorning"
    case afternoon    = "afternoon"
    case midAfternoon = "midAfternoon"
    case evening      = "evening"
    case night        = "night"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning:      return "Morning"
        case .midMorning:   return "Mid Morning"
        case .afternoon:    return "Afternoon"
        case .midAfternoon: return "Mid Afternoon"
        case .evening:      return "Evening"
        case .night:        return "Night"
        }
    }

    var timeRange: String {
        switch self {
        case .morning:      return "5:00 – 9:00 AM"
        case .midMorning:   return "9:00 AM – 12:00 PM"
        case .afternoon:    return "1:00 – 3:00 PM"
        case .midAfternoon: return "3:00 – 5:30 PM"
        case .evening:      return "6:00 – 9:00 PM"
        case .night:        return "9:00 – 11:00 PM"
        }
    }

    var icon: String {
        switch self {
        case .morning:      return "sunrise.fill"
        case .midMorning:   return "sun.max.fill"
        case .afternoon:    return "sun.min.fill"
        case .midAfternoon: return "cloud.sun.fill"
        case .evening:      return "sunset.fill"
        case .night:        return "moon.stars.fill"
        }
    }

    var blockColor: Color {
        switch self {
        case .morning:      return .orange
        case .midMorning:   return Color(red: 0.9, green: 0.75, blue: 0.0)
        case .afternoon:    return .blue
        case .midAfternoon: return .teal
        case .evening:      return .purple
        case .night:        return .indigo
        }
    }

    var sortOrder: Int {
        switch self {
        case .morning:      return 0
        case .midMorning:   return 1
        case .afternoon:    return 2
        case .midAfternoon: return 3
        case .evening:      return 4
        case .night:        return 5
        }
    }
}

// MARK: - Block Controller

enum BlockController: String {
    case me    = "me"
    case tie   = "tie"
    case enemy = "enemy"
    case unset = "unset"
}

// MARK: - Enemy Types

enum EnemyType: String, CaseIterable, Identifiable {
    case sloth    = "sloth"
    case gluttony = "gluttony"
    case pride    = "pride"
    case envy     = "envy"
    case wrath    = "wrath"
    case greed    = "greed"
    case lust     = "lust"

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var emoji: String {
        switch self {
        case .sloth:    return "🦥"
        case .gluttony: return "🍕"
        case .pride:    return "👑"
        case .envy:     return "💚"
        case .wrath:    return "🔥"
        case .greed:    return "💰"
        case .lust:     return "💫"
        }
    }

    var tagline: String {
        switch self {
        case .sloth:    return "Laziness"
        case .gluttony: return "Overindulgence"
        case .pride:    return "Arrogance"
        case .envy:     return "Jealousy"
        case .wrath:    return "Anger"
        case .greed:    return "Materialism"
        case .lust:     return "Distraction"
        }
    }

    var enemyColor: Color {
        switch self {
        case .sloth:    return .gray
        case .gluttony: return .orange
        case .pride:    return .purple
        case .envy:     return .green
        case .wrath:    return .red
        case .greed:    return Color(red: 0.85, green: 0.7, blue: 0.0)
        case .lust:     return .pink
        }
    }
}

// MARK: - SwiftData Model

@Model
final class DayBlock {
    var date: Date
    var blockTypeRaw: String
    var controllerRaw: String
    var enemyTypeRaw: String?
    var createdAt: Date

    var blockType: DayBlockType {
        DayBlockType(rawValue: blockTypeRaw) ?? .morning
    }

    var controller: BlockController {
        BlockController(rawValue: controllerRaw) ?? .unset
    }

    var enemyType: EnemyType? {
        guard let raw = enemyTypeRaw else { return nil }
        return EnemyType(rawValue: raw)
    }

    init(date: Date, blockType: DayBlockType) {
        self.date = Calendar.current.startOfDay(for: date)
        self.blockTypeRaw = blockType.rawValue
        self.controllerRaw = BlockController.unset.rawValue
        self.enemyTypeRaw = nil
        self.createdAt = Date()
    }
}

// MARK: - Battle Metrics

struct BattleMetrics: Equatable {
    var wins: Int = 0
    var ties: Int = 0
    var losses: Int = 0
    var unset: Int = 0

    var decided: Int { wins + ties + losses }

    var winRate: Double  { decided > 0 ? Double(wins)   / Double(decided) : 0 }
    var tieRate: Double  { decided > 0 ? Double(ties)   / Double(decided) : 0 }
    var lossRate: Double { decided > 0 ? Double(losses) / Double(decided) : 0 }

    static func compute(from blocks: [DayBlock]) -> BattleMetrics {
        var m = BattleMetrics()
        for b in blocks {
            switch b.controller {
            case .me:    m.wins   += 1
            case .tie:   m.ties   += 1
            case .enemy: m.losses += 1
            case .unset: m.unset  += 1
            }
        }
        return m
    }
}

// MARK: - Date Helpers

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    var isToday: Bool { Calendar.current.isDateInToday(self) }

    var weekdayName: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: self)
    }

    var monthDayYearDisplay: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: self)
    }
}
