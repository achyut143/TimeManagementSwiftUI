import SwiftUI
import AVFoundation

struct AlertView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = AlertSettings.shared




    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                counterView
                if settings.isPlaying {
                    alertInfoView
                }
                controlsView
            }
            .padding()
            .navigationTitle("Voice Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if settings.isPlaying {
                    try? AVAudioSession.sharedInstance().setCategory(.playback, options: [])
                    try? AVAudioSession.sharedInstance().setActive(true)
                    
                    if settings.nextAlertDate <= Date() {
                        settings.nextAlertDate = Date().addingTimeInterval(TimeInterval(settings.intervalMinutes * 60))
                    }
                    settings.scheduleIntervalTimer()
                }
            }
            .onChange(of: settings.isPlaying) { _, newValue in
                if newValue {
                    settings.nextAlertDate = Date().addingTimeInterval(TimeInterval(settings.intervalMinutes * 60))
                    settings.scheduleIntervalTimer()
                } else {
                    settings.stopTimer()
                }
            }
            .onChange(of: settings.intervalMinutes) { _, _ in
                if settings.isPlaying {
                    settings.nextAlertDate = Date().addingTimeInterval(TimeInterval(settings.intervalMinutes * 60))
                    settings.scheduleIntervalTimer()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .intervalAlert)) { _ in
            handleAlertFire()
        }
    }

    private var counterView: some View {
        VStack(spacing: 12) {
            Text("\(settings.counter)\(settings.targetIntervals.map { "/\($0)" } ?? "")")
                .font(.system(size: 48, weight: .bold, design: .rounded))

            Text("Intervals Completed")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let target = settings.targetIntervals {
                ProgressView(
                    value: Double(settings.counter),
                    total: Double(target)
                )
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            }
        }
    }

    private var alertInfoView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.blue)
                Text("Every \(settings.intervalMinutes) minutes")
                Spacer()
            }

            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.green)
                Text("Started: \(settings.startTime)")
                Spacer()
            }
            
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
                Text("Next: \(settings.nextAlertTime)")
                Spacer()
            }
        }
        .font(.caption)
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controlsView: some View {
        VStack(spacing: 16) {
            Toggle(isOn: Binding(
                get: { settings.isPlaying },
                set: { newValue in
                    settings.isPlaying = newValue
                    settings.isPaused = false
                    settings.startTime = ""
                    if newValue {
                        settings.intervalsComplete = false
                        // schedule timer in onChange
                        NotificationManager
                            .shared
                            .scheduleRepeatingIntervalNotifications(
                                intervalMinutes: settings.intervalMinutes
                            )
                    } else {
                        settings.stopTimer()
                        NotificationManager.shared.stopRepeatingNotifications()
                    }
                }
            )) {
                Text(settings.isPlaying ? "Stop Alerts" : "Start Alerts")
            }

            HStack {
                Text("Interval:")
                Spacer()
                TextField(
                    "Minutes",
                    value: $settings.intervalMinutes,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                Text("min")
            }

            HStack {
                Text("Target:")
                Spacer()
                TextField(
                    "Optional",
                    value: Binding(
                        get: { settings.targetIntervals ?? 0 },
                        set: {
                            settings.targetIntervals = $0 > 0 ? $0 : nil
                        }
                    ),
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                Text("intervals")
            }

            HStack {
                Button("Reset") {
                    settings.counter = 0
                    settings.intervalsComplete = false
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    settings.isPlaying = false
                    settings.stopTimer()
                    settings.intervalMinutes = 5
                    settings.targetIntervals = nil
                    NotificationManager.shared.stopRepeatingNotifications()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func handleAlertFire() {
        // Speech is now handled in AlertSettings
    }
}
