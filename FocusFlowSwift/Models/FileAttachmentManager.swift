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
    
    // Check and fix file path if needed (for development builds)
    func validateAndFixAttachment(_ attachment: TaskAttachment) -> Bool {
        // Get the valid file URL (handles container changes)
        let validURL = attachment.getValidFileURL()
        
        // Check if file exists
        if FileManager.default.fileExists(atPath: validURL.path) {
            // Update stored path if it changed
            if validURL.path != attachment.fileURL.path {
                attachment.fileURL = validURL
            }
            return true
        }
        
        // If file doesn't exist but we have original file data, recreate it
        if let originalData = attachment.originalFileData {
            do {
                // Ensure directory exists
                let directory = validURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                
                // Write file
                try originalData.write(to: validURL)
                attachment.fileURL = validURL
                return true
            } catch {
                print("Failed to recreate file from backup data: \(error)")
                return false
            }
        }
        
        return false
    }
    
    // Save file to attachments directory
    func saveFile(from sourceURL: URL, for taskId: UUID) throws -> TaskAttachment {
        let fileName = sourceURL.lastPathComponent
        let fileExtension = sourceURL.pathExtension.lowercased()
        
        // Create unique filename to avoid conflicts
        let uniqueFileName = "\(taskId.uuidString)_\(UUID().uuidString)_\(fileName)"
        let destinationURL = attachmentsDirectory.appendingPathComponent(uniqueFileName)
        
        // Handle iCloud files - start accessing security-scoped resource
        let isSecurityScoped = sourceURL.startAccessingSecurityScopedResource()
        
        defer {
            if isSecurityScoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Copy file to attachments directory
        do {
            // Remove destination if it exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            
        } catch {
            throw error
        }
        
        // Get file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        
        // Store original file data for small files (< 5MB) as backup
        var originalFileData: Data?
        if fileSize < 5_000_000 { // 5MB limit
            do {
                originalFileData = try Data(contentsOf: destinationURL)
            } catch {
                // Not critical if we can't store backup data
            }
        }
        
        // Generate thumbnail for images
        var thumbnailData: Data?
        if isImageFile(extension: fileExtension) {
            thumbnailData = generateImageThumbnail(from: destinationURL)
        } else if fileExtension == "pdf" {
            thumbnailData = generatePDFThumbnail(from: destinationURL)
        }
        
        let attachment = TaskAttachment(
            fileName: fileName,
            fileURL: destinationURL,
            fileType: fileExtension,
            fileSize: fileSize,
            thumbnailData: thumbnailData,
            originalFileData: originalFileData
        )
        
        return attachment
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
        // Verify file is readable
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            // Try loading as Data first
            guard let pdfData = try? Data(contentsOf: url),
                  let pdfDocumentFromData = PDFDocument(data: pdfData) else {
                return nil
            }
            
            return generateThumbnailFromPDFDocument(pdfDocumentFromData)
        }
        
        return generateThumbnailFromPDFDocument(pdfDocument)
    }
    
    private func generateThumbnailFromPDFDocument(_ pdfDocument: PDFDocument) -> Data? {
        guard pdfDocument.pageCount > 0 else {
            return nil
        }
        
        guard let firstPage = pdfDocument.page(at: 0) else {
            return nil
        }
        
        let thumbnailSize = CGSize(width: 120, height: 120)
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