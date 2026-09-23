import Foundation
import SwiftData

/// A reusable preset for the Schedule Generator's Interval and Task fields.
/// `intervals` and `tasks` are comma-separated strings, e.g. "1,2,3,4,5,6" and
/// "work,eat,rest,..." — mirroring the format the generator's text fields expect.
@Model
class GeneratorTemplate {
    var name: String
    var intervals: String
    var tasks: String
    var createdAt: Date
    var updatedAt: Date

    init(name: String, intervals: String, tasks: String) {
        self.name = name
        self.intervals = intervals
        self.tasks = tasks
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func update(name: String? = nil, intervals: String? = nil, tasks: String? = nil) {
        if let name { self.name = name }
        if let intervals { self.intervals = intervals }
        if let tasks { self.tasks = tasks }
        self.updatedAt = Date()
    }

    var intervalList: [String] {
        intervals.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var taskList: [String] {
        tasks.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
