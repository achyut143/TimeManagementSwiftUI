import SwiftData
import Foundation
import UniformTypeIdentifiers

@Model
class TaskAttachment {
    var id: UUID = UUID()
    var fileName: String
    var fileURL: URL
    var fileType: String
    var fileSize: Int64
    var dateAdded: Date
    var thumbnailData: Data? // For image previews
    var originalFileData: Data? // Store original file data for small files as backup
    
    @Relationship
    var task: Task?
    
    init(fileName: String, fileURL: URL, fileType: String, fileSize: Int64, thumbnailData: Data? = nil, originalFileData: Data? = nil) {
        self.id = UUID()
        self.fileName = fileName
        self.fileURL = fileURL
        self.fileType = fileType
        self.fileSize = fileSize
        self.dateAdded = Date()
        self.thumbnailData = thumbnailData
        self.originalFileData = originalFileData
    }
    
    // Check if file is an image
    var isImage: Bool {
        let imageTypes = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp"]
        return imageTypes.contains(fileType.lowercased())
    }
    
    // Check if file is a PDF
    var isPDF: Bool {
        return fileType.lowercased() == "pdf"
    }
    
    // Check if file can be previewed
    var canPreview: Bool {
        return isImage || isPDF
    }
    
    // Get file size in human readable format
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    // Get UTType for the file
    var utType: UTType? {
        return UTType(filenameExtension: fileType)
    }
}