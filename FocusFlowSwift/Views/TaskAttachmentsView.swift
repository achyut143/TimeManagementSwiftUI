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
    @State private var currentPreviewIndex = 0
    
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
                    ForEach(attachments.indices, id: \.self) { index in
                        let attachment = attachments[index]
                        AttachmentThumbnailView(
                            attachment: attachment,
                            onPreview: { previewAttachment(attachment, at: index) },
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
            allowedContentTypes: [.image, .pdf, .text, .plainText, .data, .item, .content],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result: result)
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showingPreview) {
            if let attachments = task.attachments, !attachments.isEmpty {
                SwipeableFilePreviewView(
                    attachments: attachments,
                    currentIndex: $currentPreviewIndex
                )
            }
        }
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
    
    private func previewAttachment(_ attachment: TaskAttachment, at index: Int) {
        if attachment.canPreview {
            currentPreviewIndex = index
            showingPreview = true
        }
    }
}

struct AttachmentThumbnailView: View {
    let attachment: TaskAttachment
    let onPreview: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var fileManager = FileAttachmentManager.shared
    @State private var isFileValid = true
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail or icon
                Group {
                    if !isFileValid {
                        // Show error state for missing files
                        VStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                            Text("File Missing")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        .frame(width: 80, height: 80)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    } else if attachment.isImage, let thumbnailData = attachment.thumbnailData,
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
                    if isFileValid {
                        onPreview()
                    }
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
                    .foregroundColor(isFileValid ? .primary : .orange)
                
                Text(isFileValid ? attachment.formattedFileSize : "Missing")
                    .font(.caption2)
                    .foregroundColor(isFileValid ? .secondary : .orange)
            }
        }
        .frame(width: 120)
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFileValid ? Color.gray.opacity(0.2) : Color.orange.opacity(0.5), lineWidth: 1)
        )
        .onAppear {
            validateFile()
        }
    }
    
    private func validateFile() {
        let fileExists = FileManager.default.fileExists(atPath: attachment.fileURL.path)
        let hasBackupData = attachment.originalFileData != nil
        
        if fileExists {
            isFileValid = true
        } else if hasBackupData {
            // Try to recover using the file manager
            isFileValid = fileManager.validateAndFixAttachment(attachment)
        } else {
            isFileValid = false
        }
    }
}