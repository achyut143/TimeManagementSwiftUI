import SwiftData
import Foundation

@Model
class HabitSettings {
    var fromDate: Date
    var toDate: Date
    var lastUpdated: Date
    
    init(fromDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(), 
         toDate: Date = Date()) {
        self.fromDate = fromDate
        self.toDate = toDate
        self.lastUpdated = Date()
    }
    
    static func getOrCreate(context: ModelContext) -> HabitSettings {
        let descriptor = FetchDescriptor<HabitSettings>()
        
        if let existing = try? context.fetch(descriptor).first {
            return existing
        } else {
            let newSettings = HabitSettings()
            context.insert(newSettings)
            try? context.save()
            return newSettings
        }
    }
    
    func updateDates(from: Date, to: Date, context: ModelContext) {
        self.fromDate = from
        self.toDate = to
        self.lastUpdated = Date()
        try? context.save()
    }
}