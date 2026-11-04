import Foundation
import SwiftData
import AppIntents
import UIKit
import UserNotifications

// App checks for impulse types (a ScreenZen-style gate without Screen Time).
//
// iOS doesn't let apps on a free developer account block other apps, so this
// works through a Shortcuts automation the user sets up once per app:
// "When Instagram is opened → FocusFlow: Impulse check (App: Instagram)".
// The check runs in the background. If you have planned impulse time for that
// app's type right now (or an unplanned pass is still running), it ends quietly
// and Instagram opens as normal. Otherwise FocusFlow comes forward with a wait
// screen where you can turn back or use the app anyway as unplanned time.

/// An app linked to an impulse type. `urlScheme` (e.g. "instagram://") lets
/// FocusFlow send you back into the app after you choose to use it.
struct ImpulseLinkedApp: Codable, Hashable, Identifiable {
    var name: String
    var urlScheme: String = ""
    var id: String { name.lowercased() }

    /// Common apps and the links that open them.
    static let presets: [ImpulseLinkedApp] = [
        .init(name: "Instagram", urlScheme: "instagram://"),
        .init(name: "YouTube", urlScheme: "youtube://"),
        .init(name: "TikTok", urlScheme: "tiktok://"),
        .init(name: "X", urlScheme: "twitter://"),
        .init(name: "Facebook", urlScheme: "fb://"),
        .init(name: "Reddit", urlScheme: "reddit://"),
        .init(name: "Snapchat", urlScheme: "snapchat://"),
        .init(name: "Threads", urlScheme: "barcelona://"),
        .init(name: "WhatsApp", urlScheme: "whatsapp://"),
        .init(name: "Netflix", urlScheme: "nflx://"),
        .init(name: "LinkedIn", urlScheme: "linkedin://"),
        .init(name: "Discord", urlScheme: "discord://"),
        .init(name: "Twitch", urlScheme: "twitch://"),
        .init(name: "Pinterest", urlScheme: "pinterest://")
    ]
}

extension ImpulseType {
    /// Apps that count as this impulse. Stored as JSON in `linkedAppsData`.
    var linkedApps: [ImpulseLinkedApp] {
        get {
            guard let data = linkedAppsData else { return [] }
            return (try? JSONDecoder().decode([ImpulseLinkedApp].self, from: data)) ?? []
        }
        set {
            linkedAppsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }
}

/// One run of the app check: what happened when you tried to open a linked app.
@Model
final class ImpulseGateEvent {
    var id: UUID = UUID()
    var date: Date = Date()
    var typeID: UUID = UUID()
    var appName: String = ""
    /// "planned" (let through), "resisted" (turned back) or "unplanned" (used anyway).
    var outcomeRaw: String = ImpulseGateEvent.Outcome.resisted.rawValue
    /// Minutes chosen when used anyway.
    var minutes: Int = 0

    enum Outcome: String { case planned, resisted, unplanned }

    var outcome: Outcome { Outcome(rawValue: outcomeRaw) ?? .resisted }

    init(typeID: UUID, appName: String, outcome: Outcome, minutes: Int = 0) {
        self.id = UUID()
        self.date = Date()
        self.typeID = typeID
        self.appName = appName
        self.outcomeRaw = outcome.rawValue
        self.minutes = minutes
    }
}

@MainActor
enum ImpulseGate {
    static let waitSecondsKey = "impulseGate.waitSeconds"
    static let requestedNotification = Notification.Name("ImpulseGateRequested")
    private static let pendingAppKey = "impulseGate.pendingApp"
    private static let pendingAtKey = "impulseGate.pendingAt"
    private static func passKey(_ typeID: UUID) -> String { "impulseGate.passUntil.\(typeID.uuidString)" }

    /// Set while the gate screen is on screen, so it isn't shown twice.
    static var isShowing = false

    static var context: ModelContext { FocusFlowSwiftApp.sharedContainer.mainContext }

    // MARK: Finding the type

    static func allLinkedApps(context: ModelContext? = nil) -> [(app: ImpulseLinkedApp, type: ImpulseType)] {
        let ctx = context ?? self.context
        let types = (try? ctx.fetch(FetchDescriptor<ImpulseType>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        return types.filter { !$0.isArchived }.flatMap { type in type.linkedApps.map { ($0, type) } }
    }

    static func match(appName: String) -> (app: ImpulseLinkedApp, type: ImpulseType)? {
        let key = appName.trimmingCharacters(in: .whitespaces).lowercased()
        return allLinkedApps().first { $0.app.name.lowercased() == key }
    }

    // MARK: Decision

    enum Decision {
        /// Not linked to any impulse type, so not checked.
        case notLinked
        /// Planned impulse time of this type is running until `until`.
        case planned(until: Date)
        /// An "use it anyway" pass is still running.
        case pass(until: Date)
        /// Needs the wait screen.
        case check
    }

    static func decide(appName: String, now: Date = Date()) -> Decision {
        guard let (_, type) = match(appName: appName) else { return .notLinked }
        if let until = passUntil(type.id), until > now { return .pass(until: until) }
        if let window = plannedWindow(typeID: type.id, at: now) { return .planned(until: window.end) }
        return .check
    }

    /// The planned impulse of this type happening at `now`, if any.
    static func plannedWindow(typeID: UUID, at now: Date = Date()) -> (task: Task, end: Date)? {
        tasks(typeID: typeID, on: now).compactMap { task -> (Task, Date)? in
            guard !ImpulseRules.isSkipped(task), ImpulseRules.isPlannedLabel(task),
                  let start = ImpulseRules.startDate(of: task),
                  let end = ImpulseRules.endDate(of: task),
                  start <= now, now < end else { return nil }
            return (task, end)
        }
        .max { $0.1 < $1.1 }
    }

    /// The next planned impulse of this type later today, if any.
    static func nextPlanned(typeID: UUID, after now: Date = Date()) -> Date? {
        tasks(typeID: typeID, on: now)
            .filter { !ImpulseRules.isSkipped($0) && ImpulseRules.isPlannedLabel($0) }
            .compactMap { ImpulseRules.startDate(of: $0) }
            .filter { $0 > now }
            .min()
    }

    private static func tasks(typeID: UUID, on day: Date) -> [Task] {
        let id: UUID? = typeID
        let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.impulseTypeID == id })
        let all = (try? context.fetch(descriptor)) ?? []
        let cal = Calendar.current
        // Yesterday too, for impulse time that runs past midnight.
        let yesterday = cal.date(byAdding: .day, value: -1, to: day) ?? day
        return all.filter { t in
            guard let d = t.date else { return false }
            return cal.isDate(d, inSameDayAs: day) || cal.isDate(d, inSameDayAs: yesterday)
        }
    }

    // MARK: Passes

    static func passUntil(_ typeID: UUID) -> Date? {
        UserDefaults.standard.object(forKey: passKey(typeID)) as? Date
    }

    static func setPass(_ typeID: UUID, until: Date) {
        UserDefaults.standard.set(until, forKey: passKey(typeID))
    }

    // MARK: Pending request (intent → gate screen)

    static func setPending(_ appName: String) {
        UserDefaults.standard.set(appName, forKey: pendingAppKey)
        UserDefaults.standard.set(Date(), forKey: pendingAtKey)
    }

    /// The app waiting for the gate screen, if the request is recent (2 minutes).
    private static func pendingApp() -> String? {
        let d = UserDefaults.standard
        guard let name = d.string(forKey: pendingAppKey),
              let at = d.object(forKey: pendingAtKey) as? Date,
              Date().timeIntervalSince(at) < 120 else { clearPending(); return nil }
        return name
    }

    private static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingAppKey)
        UserDefaults.standard.removeObject(forKey: pendingAtKey)
    }

    /// Shows the gate screen for a pending request, if there is one. Tries a few
    /// times, since on a cold start the window may not be ready yet.
    static func presentIfPending(attempt: Int = 0) {
        guard !isShowing, let name = pendingApp() else { return }
        guard let (app, type) = match(appName: name) else { clearPending(); return }
        let shown = FoodPresenter.present { close in
            ImpulseGateView(app: app, typeID: type.id) {
                isShowing = false
                close()
            }
        }
        if shown {
            isShowing = true
            clearPending()
        } else if attempt < 5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { presentIfPending(attempt: attempt + 1) }
        }
    }

    // MARK: Outcomes

    static func record(_ outcome: ImpulseGateEvent.Outcome, app: ImpulseLinkedApp, typeID: UUID, minutes: Int = 0) {
        context.insert(ImpulseGateEvent(typeID: typeID, appName: app.name, outcome: outcome, minutes: minutes))
        try? context.save()
    }

    /// Use the app anyway: logs unplanned impulse time starting now, lets the
    /// app through for `minutes`, reminds you when time is up, and opens it.
    static func useUnplanned(app: ImpulseLinkedApp, typeID: UUID, minutes: Int) {
        let now = Date()
        let end = now.addingTimeInterval(Double(minutes) * 60)
        let task = Task(title: app.name, startTime: DayPlanDetailView.hm(now),
                        endTime: DayPlanDetailView.hm(end), weight: 0, date: now.startOfDay)
        task.impulseTypeID = typeID
        task.impulseCheckedAt = now
        task.impulsePlannedMinutes = 0
        context.insert(task)
        record(.unplanned, app: app, typeID: typeID, minutes: minutes)
        setPass(typeID, until: end)
        NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
        scheduleTimeUp(app: app, at: end)
        open(app)
    }

    static func open(_ app: ImpulseLinkedApp) {
        guard !app.urlScheme.isEmpty, let url = URL(string: app.urlScheme) else { return }
        UIApplication.shared.open(url)
    }

    private static func scheduleTimeUp(app: ImpulseLinkedApp, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Time's up for \(app.name)"
        content.body = "Your unplanned time is over. Opening it again starts a new check."
        content.sound = .default
        let seconds = max(1, date.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: "impulse-gate-\(app.id)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Stats

    static func events(typeID: UUID? = nil, since: Date) -> [ImpulseGateEvent] {
        let all = (try? context.fetch(FetchDescriptor<ImpulseGateEvent>(predicate: #Predicate { $0.date >= since }))) ?? []
        guard let typeID else { return all }
        return all.filter { $0.typeID == typeID }
    }
}

// MARK: - Shortcuts action

/// Lists the apps linked to impulse types, for the action's App field.
struct ImpulseLinkedAppOptions: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        ImpulseGate.allLinkedApps().map(\.app.name)
    }
}

/// "Impulse check" — run it from a Shortcuts automation when an app is opened.
struct ImpulseCheckIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Impulse check"
    static let description = IntentDescription(
        "Checks if you planned time for this app. If not, FocusFlow opens with a short wait so you can decide.")
    static let openAppWhenRun = false

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "App", optionsProvider: ImpulseLinkedAppOptions())
    var app: String

    static var parameterSummary: some ParameterSummary {
        Summary("Impulse check for \(\.$app)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        switch ImpulseGate.decide(appName: app) {
        case .notLinked, .pass:
            return .result()
        case .planned(let until):
            // Planned time: let it through and remember until the window ends.
            if let (linked, type) = ImpulseGate.match(appName: app) {
                if ImpulseGate.passUntil(type.id).map({ $0 < until }) ?? true {
                    ImpulseGate.record(.planned, app: linked, typeID: type.id)
                }
                ImpulseGate.setPass(type.id, until: until)
            }
            return .result()
        case .check:
            ImpulseGate.setPending(app)
            if #available(iOS 26.0, *) {
                try await continueInForeground(alwaysConfirm: false)
            } else {
                try await requestToContinueInForeground()
            }
            NotificationCenter.default.post(name: ImpulseGate.requestedNotification, object: nil)
            return .result()
        }
    }
}
