import SwiftUI
import QuickLook
import PDFKit

struct SwipeableFilePreviewView: View {
    let attachments: [TaskAttachment]
    @Binding var currentIndex: Int
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                if attachments.isEmpty {
                    Text("No attachments to preview")
                        .foregroundColor(.secondary)
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(attachments.indices, id: \.self) { index in
                            let attachment = attachments[index]
                            
                            if attachment.canPreview {
                                FilePreviewContentView(attachment: attachment)
                                    .tag(index)
                            } else {
                                NonPreviewableFileView(attachment: attachment)
                                    .tag(index)
                            }
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                }
            }
            .navigationTitle("Attachments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Validate files when view appears
        }
    }
}

struct FilePreviewContentView: View {
    let attachment: TaskAttachment
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        VStack {
            if attachment.isImage {
                Group {
                    if let image = image {
                        ZoomableImageView(image: image)
                    } else if isLoading {
                        ProgressView("Loading image...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = loadError {
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            Text("Failed to load image")
                                .font(.headline)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else if attachment.isPDF {
                PDFPreviewView(url: attachment.fileURL)
            }
            
            // File info
            VStack(spacing: 4) {
                Text(attachment.fileName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text(attachment.formattedFileSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .onAppear {
            if attachment.isImage {
                loadImage()
            }
        }
    }
    
    private func loadImage() {
        isLoading = true
        loadError = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            // First, validate and fix the attachment path if needed
            let fileManager = FileAttachmentManager.shared
            let isValid = fileManager.validateAndFixAttachment(attachment)
            
            var imageData: Data?
            
            if isValid {
                // Try to load from file
                do {
                    imageData = try Data(contentsOf: attachment.fileURL)
                } catch {
                    // File loading failed, will try backup data
                }
            }
            
            // If file loading failed, try original data
            if imageData == nil, let originalData = attachment.originalFileData {
                imageData = originalData
            }
            
            guard let data = imageData else {
                DispatchQueue.main.async {
                    self.loadError = "File not found and no backup data available"
                    self.isLoading = false
                }
                return
            }
            
            guard let loadedImage = UIImage(data: data) else {
                DispatchQueue.main.async {
                    self.loadError = "Invalid image data"
                    self.isLoading = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }
}

struct NonPreviewableFileView: View {
    let attachment: TaskAttachment
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.fill")
                .font(.system(size: 80))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text(attachment.fileName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text(attachment.formattedFileSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("File type: \(attachment.fileType.uppercased())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("This file type cannot be previewed")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
        }
        .padding()
    }
}

// ZoomableImageView and PDFPreviewView are defined in FilePreviewView.swift