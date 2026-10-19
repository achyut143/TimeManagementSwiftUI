import SwiftUI
import SwiftData
import PhotosUI

/// Saves a finished or stopped workout to history.
enum WorkoutRecorder {
    static func record(kind: WorkoutKind, workoutID: UUID, name: String, startedAt: Date?, completed: Bool,
                       log: [RepLogEntry] = [], context: ModelContext) {
        guard let startedAt else { return }
        let session = WorkoutSession(workoutID: workoutID, kind: kind, name: name, startedAt: startedAt,
                                     endedAt: Date(), completed: completed, log: log)
        context.insert(session)
        try? context.save()
    }
}

/// Voice and beep mute buttons used on both run screens.
struct WorkoutSoundToggles: View {
    @AppStorage("workout.voiceOn") private var voiceOn = true
    @AppStorage("workout.beepsOn") private var beepsOn = true
    var showBeeps = true

    var body: some View {
        HStack(spacing: 16) {
            Button { voiceOn.toggle() } label: {
                Image(systemName: voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .accessibilityLabel(voiceOn ? "Mute voice" : "Unmute voice")
            if showBeeps {
                Button { beepsOn.toggle() } label: {
                    Image(systemName: beepsOn ? "bell.fill" : "bell.slash.fill")
                }
                .accessibilityLabel(beepsOn ? "Mute beeps" : "Unmute beeps")
            }
        }
        .font(.title3)
    }
}

/// End-of-workout panel: result, optional details, Done.
struct WorkoutFinishedView<Details: View>: View {
    let title: String
    let completed: Bool
    let durationSeconds: Int
    let onDone: () -> Void
    @ViewBuilder var details: Details

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: completed ? "checkmark.seal.fill" : "stop.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(completed ? .green : .orange)
                        Text(completed ? "Workout complete" : "Stopped early")
                            .font(.title2.bold())
                        Text("\(title) · \(WorkoutFormat.clock(durationSeconds))")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    details
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

// MARK: - Pictures

/// Thumbnail button on a cycle or exercise row: tap to pick a photo,
/// long-press to change or remove it.
struct WorkoutPictureButton: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var imageID: UUID?
    @State private var selection: PhotosPickerItem?
    @State private var thumbnail: UIImage?
    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo.badge.plus")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.12))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(imageID == nil ? "Add picture" : "Change picture")
        .contextMenu {
            if imageID != nil {
                Button("Change picture", systemImage: "photo") { showPicker = true }
                Button("Remove picture", systemImage: "trash", role: .destructive) { imageID = nil }
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $selection, matching: .images)
        .onAppear(perform: loadThumbnail)
        .onChange(of: imageID) { _, _ in loadThumbnail() }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            item.loadTransferable(type: Data.self) { result in
                guard case .success(let data?) = result, let small = WorkoutImage.downscaled(data) else { return }
                DispatchQueue.main.async {
                    let picture = WorkoutPicture(imageData: small)
                    modelContext.insert(picture)
                    imageID = picture.id
                    selection = nil
                }
            }
        }
    }

    private func loadThumbnail() {
        thumbnail = WorkoutPictureStore.image(imageID, context: modelContext)
    }
}

enum WorkoutImage {
    /// Shrinks a photo to at most 1200 px on its long side, as JPEG.
    static func downscaled(_ data: Data, maxSide: CGFloat = 1200) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longSide = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / max(longSide, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

/// The current exercise's picture on a run screen; nothing when there is none.
struct WorkoutRunImage: View {
    let image: UIImage?
    var maxHeight: CGFloat = 220

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// Small read-only thumbnail for detail lists.
struct WorkoutPictureThumb: View {
    @Environment(\.modelContext) private var modelContext
    let imageID: UUID?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .onAppear { image = WorkoutPictureStore.image(imageID, context: modelContext) }
    }
}
