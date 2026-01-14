# Data Recovery Instructions

## What Happened
The previous schema change to `TaskAttachment` caused SwiftData to create a new database, which made your existing data inaccessible.

## Current Fix
The schema has been reverted to keep `fileURL` as a stored property. This means:
- **If you haven't rebuilt yet**: Your data is still safe
- **If you already rebuilt**: The data might be in an old database file

## Recovery Options

### Option 1: Simulator Data (if using simulator)
If you're using the iOS Simulator, old data might still exist:

1. Find the old app container:
```bash
# List all simulator containers
xcrun simctl get_app_container booted com.ams.FocusFlowSwift.FocusFlowSwift2 data
```

2. Look for SwiftData files:
```bash
# The database is usually at:
~/Library/Developer/CoreSimulator/Devices/[DEVICE_ID]/data/Containers/Data/Application/[APP_ID]/Library/Application Support/default.store
```

### Option 2: Device Backup (if using real device)
If you're using a real device and have iCloud or iTunes backup:
1. Restore from backup before the schema change
2. Your data should be intact

### Option 3: Start Fresh
If recovery isn't possible:
1. Delete the app completely
2. Reinstall with the fixed version
3. Your new data will be preserved correctly going forward

## Prevention
The current implementation:
- Keeps the original schema intact
- Only updates file paths at runtime
- Won't cause data loss on future rebuilds
- Automatically fixes attachment paths after container changes

## Testing the Fix
After reinstalling:
1. Check console logs for: "TaskAttachmentMigration: Successfully updated X attachment paths"
2. Verify your tasks and data are visible
3. Test attachment previews to ensure paths are working

## If Data Is Still Missing
The data loss likely occurred when the schema changed. To prevent this in the future:
- Always test schema changes on a separate branch
- Use SwiftData versioning for migrations
- Keep backups before major changes
