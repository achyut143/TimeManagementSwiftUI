# Scheduled Activity Edit Fix - Updated

## Problem
When editing scheduled activities and changing window times, the active window increment system would stop working properly. The issue occurred because:

1. The `checkForExpiredWindows()` function tracks skipped windows by comparing the number of passed windows with `windowsSkippedInPeriod`
2. When you edit an activity's schedule, the old window tracking data becomes invalid
3. The system would either:
   - Stop incrementing windows because it thought all windows were already accounted for
   - Mass-mark windows as skipped incorrectly
4. **Additional Issue**: The initial fix used a 5-minute protection period that completely blocked window credit accumulation after editing

## Root Cause
The window tracking system (`windowsSkippedInPeriod`) wasn't being reset when the activity schedule was modified, causing a mismatch between the actual schedule and the tracking data. The overly broad protection period prevented normal window processing.

## Solution - Version 2
Refined the fix to be more surgical and allow normal window processing to resume quickly:

### 1. Improved Edit Tracking
- Added `lastEditedAt: Date?` property to `ScheduledActivity` model
- Added `markAsEdited()` method to reset window tracking when schedule changes
- Changed to `needsPostEditReset()` method with only 10-second protection period
- Removed the broad `wasRecentlyEdited()` blocking approach

### 2. Smart Edit Detection in Save
In `EditScheduledActivityView.saveChanges()`:
- Detects when `scheduledTimes` or `windowDuration` changes
- Calls `activity.markAsEdited()` to reset window tracking
- Preserves user actions like `windowsUsedInPeriod` and `accumulatedWindowCredits`

### 3. Refined Window Checking
In `ScheduledActivityView.checkForExpiredWindows()`:
- No longer completely skips recently edited activities
- Uses conservative approach for recently edited activities (1 window per cycle)
- Allows normal processing for regular activities (up to 3 windows per cycle)
- Ensures window credits continue to accumulate after editing

## Key Changes - Version 2

### ScheduledActivity.swift
```swift
// Refined method
func needsPostEditReset() -> Bool {
    guard let editTime = lastEditedAt else { return false }
    let tenSecondsAgo = Date().addingTimeInterval(-10) // 10 seconds
    return editTime > tenSecondsAgo
}
```

### ScheduledActivityView.swift
```swift
// In checkForExpiredWindows() - No longer skips activities completely
// For recently edited activities, only mark 1 window at a time to prevent bulk marking
// For normal activities, allow up to 3 windows per cycle
let maxWindowsToSkip = activity.needsPostEditReset() ? 1 : min(newlySkipped, 3)
let windowsToSkip = min(newlySkipped, maxWindowsToSkip)
```

## Benefits - Version 2
1. **Preserves User Data**: Doesn't reset accumulated window credits or used windows
2. **Smart Reset**: Only resets tracking when schedule actually changes
3. **Minimal Disruption**: Only 10-second conservative period instead of 5 minutes
4. **Continues Processing**: Window credits accumulate normally after brief protection period
5. **Prevents Mass-Skipping**: Still protects against incorrect bulk window marking
6. **Maintains Accuracy**: Ensures window increment system works correctly after edits
7. **Backward Compatible**: Existing activities continue to work normally

## Testing - Version 2
After implementing this improved fix:
1. Create a weekly scheduled activity with multiple days selected
2. Let it run and accumulate some window credits
3. Edit the activity and change window duration
4. Verify that window increments resume working within 10 seconds
5. Confirm that accumulated credits are preserved
6. Test that new windows properly accumulate credits when they expire

The improved fix ensures that the window increment system resumes normal operation almost immediately after editing, while still providing protection against bulk window marking.