import Foundation
import SwiftData
import Combine

@Model
class CycleConfiguration {
    var id: UUID
    var name: String
    var createdDate: Date
    var cycles: [CyclePhase]
    
    init(name: String, cycles: [CyclePhase]) {
        self.id = UUID()
        self.name = name
        self.createdDate = Date()
        // Preserve the existing order from the input cycles
        // The cycles should already have the correct order set
        self.cycles = cycles.map { phase in
            let newPhase = CyclePhase(name: phase.name, totalMinutes: phase.totalMinutes, order: phase.order ?? 0)
            return newPhase
        }
    }
    
    var totalDuration: Int {
        cycles.reduce(0) { $0 + $1.totalMinutes }
    }
    
    func totalIntervals(intervalMinutes: Int) -> Int {
        cycles.reduce(0) { $0 + $1.totalIntervals(intervalMinutes: intervalMinutes) }
    }
    
    var orderedCycles: [CyclePhase] {
        return cycles.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }
}

@Model
class CyclePhase: ObservableObject {
    var id: UUID
    var name: String
    var totalMinutes: Int
    var currentIntervals: Int
    var order: Int?
    var configuration: CycleConfiguration?
    
    init(name: String, totalMinutes: Int, order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.totalMinutes = totalMinutes
        self.currentIntervals = 0
        self.order = order
    }
    
    func totalIntervals(intervalMinutes: Int) -> Int {
        return totalMinutes / intervalMinutes
    }
    
    func reset() {
        currentIntervals = 0
    }
}