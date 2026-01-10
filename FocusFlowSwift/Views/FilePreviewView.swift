import SwiftUI
import PDFKit
import QuickLook

struct FilePreviewView: View {
    let attachment: TaskAttachment
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if attachment.isImage {
                    ImagePreviewView(url: attachment.fileURL)
                } else if attachment.isPDF {
                    PDFPreviewView(url: attachment.fileURL)
                } else {
                    UnsupportedFileView(attachment: attachment)
                }
            }
            .navigationTitle(attachment.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: attachment.fileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

struct ImagePreviewView: View {
    let url: URL
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(0.5, min(3.0, value))
                                },
                            DragGesture()
                                .onChanged { value in
                                    offset = value.translation
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            scale = scale == 1.0 ? 2.0 : 1.0
                            offset = .zero
                        }
                    }
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let loadedImage = UIImage(contentsOfFile: url.path) {
                DispatchQueue.main.async {
                    self.image = loadedImage
                }
            }
        }
    }
}

struct PDFPreviewView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        // No updates needed
    }
}

struct UnsupportedFileView: View {
    let attachment: TaskAttachment
    @StateObject private var fileManager = FileAttachmentManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Image(uiImage: fileManager.getFileIcon(for: attachment.fileType))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
            
            VStack(spacing: 8) {
                Text(attachment.fileName)
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("File Type: \(attachment.fileType.uppercased())")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Size: \(attachment.formattedFileSize)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button("Open in Files App") {
                // Open in Files app or other compatible apps
                let activityController = UIActivityViewController(activityItems: [attachment.fileURL], applicationActivities: nil)
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    window.rootViewController?.present(activityController, animated: true)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.05))
    }
}