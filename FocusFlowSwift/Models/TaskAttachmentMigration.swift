import Foundation
import SwiftData

/// Handles migration of TaskAttachment paths after app container changes
class TaskAttachmentMigration {
    
    /// Update all TaskAttachment paths to use current container directory
    /// This should be called once on app launch after the model container is created
    static func migrateAttachmentsIfNeeded(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<TaskAttachment>()
        
        guard let attachments = try? modelContext.fetch(descriptor) else {
            print("TaskAttachmentMigration: Failed to fetch attachments")
            return
        }
        
        var updatedCount = 0
        var validCount = 0
        
        for attachment in attachments {
            // Check if file exists at stored path
            if FileManager.default.fileExists(atPath: attachment.fileURL.path) {
                validCount += 1
                continue
            }
            
            // File doesn't exist at stored path - update to current container
            let oldPath = attachment.fileURL.path
            attachment.updateToCurrentPath()
            let newPath = attachment.fileURL.path
            
            if oldPath != newPath {
                updatedCount += 1
                print("TaskAttachmentMigration: Updated '\(attachment.fileName)' path")
                
                // If file still doesn't exist but we have backup data, restore it
                if !FileManager.default.fileExists(atPath: newPath), let backupData = attachment.originalFileData {
                    do {
                        // Ensure directory exists
                        let directory = attachment.fileURL.deletingLastPathComponent()
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        
                        // Write backup data
                        try backupData.write(to: attachment.fileURL)
                        print("TaskAttachmentMigration: Restored '\(attachment.fileName)' from backup")
                    } catch {
                        print("TaskAttachmentMigration: Failed to restore '\(attachment.fileName)': \(error)")
                    }
                }
            }
        }
        
        if updatedCount > 0 {
            do {
                try modelContext.save()
                print("TaskAttachmentMigration: Successfully updated \(updatedCount) attachment paths")
            } catch {
                print("TaskAttachmentMigration: Failed to save updated attachments: \(error)")
            }
        }
        
        if validCount > 0 {
            print("TaskAttachmentMigration: \(validCount) attachments already have valid paths")
        }
        
        if updatedCount == 0 && validCount == 0 {
            print("TaskAttachmentMigration: No attachments found")
        }
    }
}
