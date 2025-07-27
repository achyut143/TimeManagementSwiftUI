import SwiftData
import Foundation

@Model
class AlertSettings {
    var isPlaying: Bool = false
    var isSimple: Bool = false
    var isPaused: Bool = false
    var intervalMinutes: Int = 5
    var counter: Int = 0
    var targetIntervals: Int? = nil
    var intervalsComplete: Bool = false
    var startTime: String = ""
    var nextAlertTime: String = ""
    var positionX: Double = 20
    var positionY: Double = 20
    var isMinimized: Bool = false
    
    init() {}
}