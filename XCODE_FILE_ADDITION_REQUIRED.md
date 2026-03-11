# ⚠️ XCODE FILE ADDITION REQUIRED

## Build Error

The build is failing because the new timer files exist in the file system but haven't been added to the Xcode project file (`project.pbxproj`).

## Error Messages
```
error: cannot find type 'ActivityTimerAttributes' in scope
error: referencing subscript 'subscript(dynamicMember:)' requires wrapper
```

## Why This Happens

When you create files outside of Xcode (like we did), they exist on disk but Xcode doesn't know to compile them. You must manually add them to the project.

## Files That Need to Be Added

### Widget Extension Target (FocusFlowWidgets)
1. ✅ `FocusFlowWidgets/ActivityTimerAttributes.swift` - EXISTS
2. ✅ `FocusFlowWidgets/ActivityTimerLiveActivityView.swift` - EXISTS

### Main App Target (FocusFlowSwift)
3. ✅ `FocusFlowSwift/Models/ActivityTimerManager.swift` - EXISTS
4. ✅ `FocusFlowSwift/Views/ActiveTimerButton.swift` - EXISTS

## How to Add Files in Xcode

### Method 1: Drag and Drop (Easiest)
1. Open `FocusFlowSwift.xcodeproj` in Xcode
2. In Finder, navigate to `FocusFlowWidgets` folder
3. Drag `ActivityTimerAttributes.swift` and `ActivityTimerLiveActivityView.swift` into the `FocusFlowWidgets` group in Xcode
4. In the dialog that appears:
   - ✅ Check "Copy items if needed" (even though they're already there)
   - ✅ Check "FocusFlowWidgets" target
   - Click "Finish"
5. Navigate to `FocusFlowSwift/Models` folder in Finder
6. Drag `ActivityTimerManager.swift` into the `Models` group in Xcode
7. In the dialog:
   - ✅ Check "FocusFlowSwift" target
   - Click "Finish"
8. Navigate to `FocusFlowSwift/Views` folder in Finder
9. Drag `ActiveTimerButton.swift` into the `Views` group in Xcode
10. In the dialog:
    - ✅ Check "FocusFlowSwift" target
    - Click "Finish"

### Method 2: Add Files Menu
1. Open `FocusFlowSwift.xcodeproj` in Xcode
2. Right-click on `FocusFlowWidgets` folder in Project Navigator
3. Select "Add Files to FocusFlowSwift..."
4. Navigate to and select both:
   - `ActivityTimerAttributes.swift`
   - `ActivityTimerLiveActivityView.swift`
5. Make sure "FocusFlowWidgets" target is checked
6. Click "Add"
7. Repeat for `FocusFlowSwift` target with:
   - `Models/ActivityTimerManager.swift`
   - `Views/ActiveTimerButton.swift`

## After Adding Files

1. Clean Build Folder: Cmd + Shift + K
2. Build: Cmd + B
3. Should build successfully!

## Verification

After adding files, you should see them in Xcode's Project Navigator with the correct target membership:

```
FocusFlowWidgets/
  ├── ActivityTimerAttributes.swift (Target: FocusFlowWidgets)
  └── ActivityTimerLiveActivityView.swift (Target: FocusFlowWidgets)

FocusFlowSwift/
  ├── Models/
  │   └── ActivityTimerManager.swift (Target: FocusFlowSwift)
  └── Views/
      └── ActiveTimerButton.swift (Target: FocusFlowSwift)
```

## Alternative: Command Line (Advanced)

If you're comfortable with command line, you could use a tool like `xcodeproj` gem to add files programmatically, but manual addition in Xcode is recommended.

## Once Files Are Added

The build should succeed and you'll be able to:
- Use activity credits/overdraft
- See timer confirmation dialog
- Start timer in Dynamic Island
- Control timer with floating button
- Pause/Resume/Cancel timer

## Need Help?

If you're still having issues after adding the files:
1. Check target membership (select file → File Inspector → Target Membership)
2. Verify files are in correct groups
3. Clean build folder and rebuild
4. Restart Xcode if needed
