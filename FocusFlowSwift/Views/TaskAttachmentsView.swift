import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook

struct TaskAttachmentsView: View {
    @Bindable var task: Task
    @Environment(\.modelContext) private var modelContext
    @StateObject private var fileManager = FileAttachmentManager.shared
    
    @State private var showingFilePicker = false
    @State private var showingPreview = false
    @State private var previewURL: URL?
    @State private var dragOver = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attachments")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showingFilePicker = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if let attachments = task.attachments, !attachments.isEmpty {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 120, maximum: 150))
                ], spacing: 12) {
                    ForEach(attachments, id: \.id) { attachment in
                        AttachmentThumbnailView(
                            attachment: attachment,
                            onPreview: { previewAttachment(attachment) },
                            onDelete: { deleteAttachment(attachment) }
                        )
                    }
                }
            } else {
                // Drop zone when no attachments
                RoundedRectangle(cornerRadius: 8)
                    .fill(dragOver ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(height: 80)
                    .overlay(
                        VStack {
                            Image(systemName: "doc.badge.plus")
                                .font(.title2)
                                .foregroundColor(.gray)
                            Text("Drop files here or click + to add")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    )
                    .onTapGesture {
                        showingFilePicker = true
                    }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dragOver) { providers in
            handleDrop(providers: providers)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.image, .pdf, .text, .data],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result: result)
        }
        .quickLookPreview($previewURL)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            addAttachment(from: url)
                        }
                    }
                }
            }
        }
        return true
    }
    
    private func handleFileSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                addAttachment(from: url)
            }
        case .failure(let error):
            print("File selection error: \(error)")
        }
    }
    
    private func addAttachment(from url: URL) {
        do {
            let attachment = try fileManager.saveFile(from: url, for: task.id)
            attachment.task = task
            
            // Initialize attachments array if nil
            if task.attachments == nil {
                // We can't directly assign to attachments since it's computed
                // Instead, we'll add the attachment and let SwiftData handle the relationship
            }
            
            modelContext.insert(attachment)
            try modelContext.save()
        } catch {
            print("Error adding attachment: \(error)")
        }
    }
    
    private func deleteAttachment(_ attachment: TaskAttachment) {
        fileManager.deleteAttachment(attachment)
        modelContext.delete(attachment)
        try? modelContext.save()
    }
    
    private func previewAttachment(_ attachment: TaskAttachment) {
        if attachment.canPreview {
            previewURL = attachment.fileURL
            showingPreview = true
        }
    }
}

struct AttachmentThumbnailView: View {
    let attachment: TaskAttachment
    let onPreview: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var fileManager = FileAttachmentManager.shared
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail or icon
                Group {
                    if attachment.isImage, let thumbnailData = attachment.thumbnailData,
                       let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(8)
                    } else if attachment.isPDF, let thumbnailData = attachment.thumbnailData,
                              let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(8)
                            .overlay(
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.red)
                                    .background(Color.white.opacity(0.8))
                                    .cornerRadius(4)
                                    .padding(4),
                                alignment: .bottomTrailing
                            )
                    } else {
                        Image(uiImage: fileManager.getFileIcon(for: attachment.fileType))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .padding(10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .onTapGesture {
                    onPreview()
                }
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .offset(x: 5, y: -5)
            }
            
            // File name and size
            VStack(spacing: 2) {
                Text(attachment.fileName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text(attachment.formattedFileSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 120)
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}