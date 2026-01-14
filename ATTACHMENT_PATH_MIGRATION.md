# Task Attachment Path Migration

## Problem
Task attachments were storing absolute file paths that included the app container ID:
```
/var/mobile/Containers/Data/Application/846DEF5B-16B5-4F54-9C33-5B5FBC4F02AE/Documents/TaskAttachments/file.pdf
```

Every time the app is rebuilt or reinstalled, the container ID changes, making all existing attachment paths invalid.

## Solution
Changed `TaskAttachment` to store only relative paths (filenames) and reconstruct the full path at runtime.

### Changes Made

1. **TaskAttachment.swift**
   - Changed `fileURL` from stored property to computed property
   - Added `relativeFilePath` to store only the filename
   - `fileURL` now dynamically constructs the full path using current Documents directory

2. **FileAttachmentManager.swift**
   - Simplified `validateAndFixAttachment()` since paths are now always correct
   - File recovery now only relies on `originalFileData` backup

3. **TaskAttachmentMigration.swift** (NEW)
   - Automatically migrates existing attachments from absolute to relative paths
   - Detects old paths by checking for "/" in `relativeFilePath`
   - Extracts filename from old absolute paths

4. **FocusFlowSwiftApp.swift**
   - Added `MigrationWrapper` view to run migration on app launch
   - Migration runs once when app first appears
   - Uses proper SwiftData modelContext

## How It Works

### Before Migration
```swift
relativeFilePath = "/var/mobile/.../Documents/TaskAttachments/file.pdf"
fileURL = URL(string: relativeFilePath) // Breaks after rebuild
```

### After Migration
```swift
relativeFilePath = "2C2107A2-10C7-490C-A5BD-BFA602C9FE84_file.pdf"
fileURL = documentsDirectory + "TaskAttachments/" + relativeFilePath // Always works
```

## Migration Process

1. App launches
2. `MigrationWrapper` runs on first appearance
3. Fetches all `TaskAttachment` objects
4. For each attachment:
   - If `relativeFilePath` contains "/", extract filename
   - Update `relativeFilePath` to just the filename
5. Save changes to SwiftData
6. Log results

## Testing

After this update:
1. Existing attachments will be automatically migrated on first launch
2. New attachments will use relative paths from the start
3. Files will survive app reinstalls as long as data persists
4. Check console logs for migration status:
   - "Successfully migrated X attachments"
   - "All X attachments already migrated"
   - "No attachments found to migrate"

## Notes

- Migration is idempotent (safe to run multiple times)
- Small files (<5MB) have backup data stored in `originalFileData`
- If file is missing but backup exists, it will be recreated
- Files are stored in `Documents/TaskAttachments/` directory
