import SwiftUI
import SwiftData

/// Shown when you open an app linked to an impulse type outside planned time:
/// a short wait, then turn back or use it anyway as unplanned time.
struct ImpulseGateView: View {
    let app: ImpulseLinkedApp
    let typeID: UUID
    let onClose: () -> Void

    @Query(sort: \ImpulseType.sortOrder) private var types: [ImpulseType]
    @AppStorage(ImpulseGate.waitSecondsKey) private var waitSeconds = 10

    @State private var remaining = 0
    @State private var started = false
    @State private var finished: Finished?

    private enum Finished { case resisted, switchTo }

    private static let choices = [5, 10, 15, 30]

    private var type: ImpulseType? { types.first { $0.id == typeID } }
    private var color: Color { type?.color ?? .pink }
    private var waiting: Bool { remaining > 0 }

    var body: some View {
        VStack(spacing: 24) {
            header
            if let finished {
                doneView(finished)
            } else {
                statusCard
                breathRing
                choicesView
            }
            Spacer(minLength: 0)
            statsLine
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled(finished == nil)
        .onAppear(perform: start)
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 34))
                .foregroundStyle(color)
            Text(app.name)
                .font(.largeTitle.bold())
            if let type {
                Text("\(type.name) impulse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 24)
    }

    private var statusCard: some View {
        VStack(spacing: 4) {
            Text("Not planned right now")
                .font(.headline)
            Text(statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.12)))
    }

    private var statusDetail: String {
        if let next = ImpulseGate.nextPlanned(typeID: typeID) {
            return "Your next planned time starts at \(next.formatted(date: .omitted, time: .shortened))."
        }
        let hours = type?.planBeforeHours ?? 0
        if hours > 0 {
            return "Plan it at least \(PlannerRules.formatHours(hours * 60))h ahead to make it planned."
        }
        return "Using it now counts as unplanned time."
    }

    private var breathRing: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: waitSeconds > 0 ? CGFloat(remaining) / CGFloat(waitSeconds) : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            VStack(spacing: 2) {
                if waiting {
                    Text("\(remaining)")
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                    Text("Take a breath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(color)
                    Text("Your choice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 140, height: 140)
    }

    private var choicesView: some View {
        VStack(spacing: 12) {
            Button {
                ImpulseGate.record(.resisted, app: app, typeID: typeID)
                withAnimation { finished = .resisted }
            } label: {
                Text("Not now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            VStack(spacing: 6) {
                Text("Use it anyway (unplanned)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Self.choices, id: \.self) { minutes in
                        Button("\(minutes)m") { useAnyway(minutes) }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .disabled(waiting)
        .opacity(waiting ? 0.4 : 1)
    }

    @ViewBuilder
    private func doneView(_ finished: Finished) -> some View {
        VStack(spacing: 12) {
            switch finished {
            case .resisted:
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text("Good call").font(.title2.bold())
                Text("That's counted as an impulse you turned back.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .switchTo:
                Image(systemName: "arrow.uturn.right.circle.fill").font(.system(size: 44)).foregroundStyle(color)
                Text("Now switch to \(app.name)").font(.title2.bold())
                Text("It's logged as unplanned time, and \(app.name) won't be checked again until your time is up.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Close") { onClose() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var statsLine: some View {
        let today = ImpulseGate.events(typeID: typeID, since: Date().startOfDay)
        let resisted = today.filter { $0.outcome == .resisted }.count
        let unplanned = today.filter { $0.outcome == .unplanned }.reduce(0) { $0 + $1.minutes }
        return Text("Today: \(today.count) checks · \(resisted) turned back · \(unplanned)m unplanned")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: Actions

    private func start() {
        guard !started else { return }
        started = true
        remaining = max(0, waitSeconds)
        guard remaining > 0 else { return }
        _Concurrency.Task { @MainActor in
            while remaining > 0 {
                try? await _Concurrency.Task.sleep(for: .seconds(1))
                remaining -= 1
            }
        }
    }

    private func useAnyway(_ minutes: Int) {
        ImpulseGate.useUnplanned(app: app, typeID: typeID, minutes: minutes)
        if app.urlScheme.isEmpty {
            withAnimation { finished = .switchTo }
        } else {
            onClose()
        }
    }
}

/// Step-by-step setup for the Shortcuts automation.
struct ImpulseGateSetupGuide: View {
    let apps: [ImpulseLinkedApp]

    var body: some View {
        List {
            Section {
                Text("iPhone doesn't let FocusFlow block apps directly, so a Shortcuts automation asks FocusFlow first each time you open the app. Set it up once per app.")
                    .font(.subheadline)
            }
            Section("Steps") {
                step(1, "Open the **Shortcuts** app and tap **Automation**.")
                step(2, "Tap **+** (or **New Automation**) and choose **App**.")
                step(3, "Tap **Choose**, pick the app (e.g. \(apps.first?.name ?? "Instagram")), and keep **Is Opened** checked.")
                step(4, "Choose **Run Immediately** and turn off **Notify When Run**.")
                step(5, "Tap **Next** → **New Blank Automation** → **Add Action**, search **FocusFlow**, and pick **Impulse check**.")
                step(6, "Tap **App** in the action and choose the same app. Tap **Done**.")
            }
            Section("What happens") {
                Label("Planned impulse time for this type right now: the app opens as normal.", systemImage: "checkmark.circle")
                Label("Otherwise FocusFlow shows a short wait. Turn back, or use it for 5–30 minutes as unplanned time.", systemImage: "hand.raised")
                Label("While that time runs, the app isn't checked again. You get a reminder when it's up.", systemImage: "bell")
            }
            .font(.subheadline)
            if !apps.isEmpty {
                Section("Apps to set up") {
                    ForEach(apps) { app in
                        Text(app.name)
                    }
                }
            }
        }
        .navigationTitle("Set up app checks")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
