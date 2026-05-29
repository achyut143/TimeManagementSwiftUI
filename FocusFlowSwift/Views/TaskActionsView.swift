import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook
import PhotosUI

struct TaskAttachmentsManagementView: View {
    @Bindable var task: Task
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var fileManager = FileAttachmentManager.shared
    
    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var showingPreview = false
    @State private var previewURL: URL?
    @State private var dragOver = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var currentPreviewIndex = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Upload Section
                    uploadSection
                    
                    // Attachments Grid
                    if let attachments = task.attachments, !attachments.isEmpty {
                        attachmentsGrid(attachments)
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("File Attachments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Browse Files", systemImage: "folder")
                        }
                        
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
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
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { _, newItems in
                handlePhotoSelection(items: newItems)
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
    }
    
    private var uploadSection: some View {
        VStack(spacing: 12) {
            Text("Upload Files")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            RoundedRectangle(cornerRadius: 12)
                .fill(dragOver ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                .frame(height: 100)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: dragOver ? "doc.badge.plus.fill" : "doc.badge.plus")
                            .font(.title2)
                            .foregroundColor(dragOver ? .blue : .gray)
                        
                        Text(dragOver ? "Drop files here" : "Drag & drop files or tap to browse")
                            .font(.subheadline)
                            .foregroundColor(dragOver ? .blue : .gray)
                        
                        Text("Supports: PNG, JPEG, PDF")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
                .onTapGesture {
                    showingFilePicker = true
                }
            
            // Quick action buttons
            HStack(spacing: 12) {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Browse Files", systemImage: "folder")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.blue)
                        .cornerRadius(8)
                }
                
                Button {
                    showingPhotoPicker = true
                } label: {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.green)
                        .cornerRadius(8)
                }
                
                Spacer()
            }
        }
    }
    
    private func attachmentsGrid(_ attachments: [TaskAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attached Files (\(attachments.count))")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120, maximum: 150))
            ], spacing: 16) {
                    ForEach(attachments.indices, id: \.self) { index in
                        let attachment = attachments[index]
                        AttachmentCard(
                            attachment: attachment,
                            onPreview: { previewAttachment(attachment, at: index) },
                            onDelete: { deleteAttachment(attachment) }
                        )
                    }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No Files Attached")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Add files or photos to keep important documents with this task")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Add Files", systemImage: "folder")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding()
                        .background(.blue)
                        .cornerRadius(10)
                }
                
                Button {
                    showingPhotoPicker = true
                } label: {
                    Label("Add Photos", systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding()
                        .background(.green)
                        .cornerRadius(10)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
    
    private func handlePhotoSelection(items: [PhotosPickerItem]) {
        for item in items {
            _Concurrency.Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // Create a temporary file from the photo data
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("jpg")
                    
                    do {
                        try data.write(to: tempURL)
                        
                        // Add the attachment on the main thread
                        await MainActor.run {
                            addAttachment(from: tempURL)
                        }
                        
                        // Clean up temporary file
                        try? FileManager.default.removeItem(at: tempURL)
                    } catch {
                        print("Error processing photo: \(error)")
                    }
                }
            }
        }
        
        // Clear the selection
        selectedPhotoItems = []
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

struct AttachmentCard: View {
    let attachment: TaskAttachment
    let onPreview: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var fileManager = FileAttachmentManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail or icon
                Group {
                    if attachment.isImage, let thumbnailData = attachment.thumbnailData,
                       let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipped()
                            .cornerRadius(8)
                    } else if attachment.isPDF, let thumbnailData = attachment.thumbnailData,
                              let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
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
                            .padding(20)
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
            
            // File info
            VStack(spacing: 4) {
                Text(attachment.fileName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text(attachment.formattedFileSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if attachment.canPreview {
                    Text("Tap to preview")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
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