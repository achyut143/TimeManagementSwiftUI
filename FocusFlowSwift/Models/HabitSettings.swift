import SwiftData
import Foundation

@Model
class HabitSettings {
    var fromDate: Date
    var lastUpdated: Date
    var metricDays: Int? // Number of days to show metrics for (7, 15, 30, 45, 60) - Optional for migration
    
    init(fromDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(), 
         metricDays: Int = 30) {
        self.fromDate = fromDate
        self.lastUpdated = Date()
        self.metricDays = metricDays
    }
    
    // Computed property to always return a valid value
    var effectiveMetricDays: Int {
        return metricDays ?? 30
    }
    
    static func getOrCreate(context: ModelContext) -> HabitSettings {
        let descriptor = FetchDescriptor<HabitSettings>()
        
        if let existing = try? context.fetch(descriptor).first {
            // Migrate old records that don't have metricDays set
            if existing.metricDays == nil {
                existing.metricDays = 30
                try? context.save()
            }
            return existing
        } else {
            let newSettings = HabitSettings()
            context.insert(newSettings)
            try? context.save()
            return newSettings
        }
    }
    
    func updateFromDate(_ from: Date, context: ModelContext) {
        self.fromDate = from
        self.lastUpdated = Date()
        try? context.save()
    }
    
    func updateMetricDays(_ days: Int, context: ModelContext) {
        self.metricDays = days
        self.lastUpdated = Date()
        try? context.save()
    }
}