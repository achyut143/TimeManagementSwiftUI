import Foundation
import SwiftData
import SwiftUI

@Model
class EventDay {
    var date: Date
    var isFullDay: Bool
    var isMorning: Bool
    var isAfternoon: Bool
    var isEvening: Bool
    var events: [String]
    
    init(date: Date, isFullDay: Bool = false, isMorning: Bool = false, isAfternoon: Bool = false, isEvening: Bool = false, events: [String] = []) {
        self.date = date
        self.isFullDay = isFullDay
        self.isMorning = isMorning
        self.isAfternoon = isAfternoon
        self.isEvening = isEvening
        self.events = events
    }
    
    var hasAnyEvent: Bool {
        return isFullDay || isMorning || isAfternoon || isEvening || !events.isEmpty
    }
    
    var eventTypes: [EventType] {
        var types: [EventType] = []
        if isFullDay { types.append(.fullDay) }
        if isMorning { types.append(.morning) }
        if isAfternoon { types.append(.afternoon) }
        if isEvening { types.append(.evening) }
        return types
    }
}

enum EventType: String, CaseIterable {
    case fullDay = "Full Day"
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
    
    var color: Color {
        switch self {
        case .fullDay: return .red
        case .morning: return .orange
        case .afternoon: return .blue
        case .evening: return .purple
        }
    }
}