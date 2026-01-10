import Foundation
import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import UIKit

class FileAttachmentManager: ObservableObject {
    static let shared = FileAttachmentManager()
    
    private init() {}
    
    // Get the documents directory for storing attachments
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    // Create attachments folder if it doesn't exist
    private var attachmentsDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("TaskAttachments")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    // Save file to attachments directory
    func saveFile(from sourceURL: URL, for taskId: UUID) throws -> TaskAttachment {
        let fileName = sourceURL.lastPathComponent
        let fileExtension = sourceURL.pathExtension.lowercased()
        
        // Create unique filename to avoid conflicts
        let uniqueFileName = "\(taskId.uuidString)_\(UUID().uuidString)_\(fileName)"
        let destinationURL = attachmentsDirectory.appendingPathComponent(uniqueFileName)
        
        // Copy file to attachments directory
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        
        // Get file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        
        // Generate thumbnail for images
        var thumbnailData: Data?
        if isImageFile(extension: fileExtension) {
            thumbnailData = generateImageThumbnail(from: destinationURL)
        } else if fileExtension == "pdf" {
            thumbnailData = generatePDFThumbnail(from: destinationURL)
        }
        
        return TaskAttachment(
            fileName: fileName,
            fileURL: destinationURL,
            fileType: fileExtension,
            fileSize: fileSize,
            thumbnailData: thumbnailData
        )
    }
    
    // Delete attachment file
    func deleteAttachment(_ attachment: TaskAttachment) {
        try? FileManager.default.removeItem(at: attachment.fileURL)
    }
    
    // Check if file extension is an image
    private func isImageFile(extension fileExtension: String) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp"]
        return imageExtensions.contains(fileExtension.lowercased())
    }
    
    // Generate thumbnail for image files
    private func generateImageThumbnail(from url: URL) -> Data? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        
        let thumbnailSize = CGSize(width: 100, height: 100)
        let thumbnail = image.resized(to: thumbnailSize)
        
        return thumbnail?.pngData()
    }
    
    // Generate thumbnail for PDF files
    private func generatePDFThumbnail(from url: URL) -> Data? {
        guard let pdfDocument = PDFDocument(url: url),
              let firstPage = pdfDocument.page(at: 0) else { return nil }
        
        let thumbnailSize = CGSize(width: 100, height: 100)
        let thumbnail = firstPage.thumbnail(of: thumbnailSize, for: .cropBox)
        
        return thumbnail.pngData()
    }
    
    // Get file icon for non-previewable files
    func getFileIcon(for fileType: String) -> UIImage {
        // Return a generic document icon for iOS
        return UIImage(systemName: "doc.fill") ?? UIImage()
    }
}

// Extension to resize UIImage
extension UIImage {
    func resized(to newSize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        self.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}