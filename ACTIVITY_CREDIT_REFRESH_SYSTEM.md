# Activity Credit Refresh System

## Overview

Activity credits are now managed centrally in **ContentView** instead of ScheduledActivityView. This ensures credits accumulate reliably regardless of which tab or screen you're viewing.

## Architecture Change

### Before (Old System)
```
ScheduledActivityView (Activities Tab)
  ↓
  Timer checks every 1 second
  ↓
  Detects expired windows
  ↓
  Adds credits
```

**Problem:** Credits only accumulated when viewing the Activities tab.

### After (New System)
```
ContentView (Root View - Always Active)
  ↓
  Timer checks every 60 seconds
  ↓
  Detects expired windows
  ↓
  Adds credits
  ↓
  Notifies all views to refresh
```

**Benefit:** Credits accumulate regardless of which tab you're on!

## How It Works

### 1. ContentView Monitors All Activities

```swift
@Query(filter: #Predicate<ScheduledActivity> { $0.isActive })
private var activeActivities: [ScheduledActivity]

let activityCheckTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
```

### 2. Checks for Expired Windows Every Minute

```swift
.onReceive(activityCheckTimer) { _ in
    checkForExpiredWindows()
}
```

### 3. Adds Credits When Windows Expire

```swift
private func checkForExpiredWindows() {
    for activity in activeActivities {
        // Check if windows have passed unused
        let passedWindows = activity.getPassedUnusedWindows()
        
        // Mark them as skipped (adds credits)
        for _ in 0..<windowsToSkip {
            activity.markWindowAsSkipped() // +1 credit per window
        }
        
        // Notify other views
        NotificationCenter.default.post(name: "ActivityUpdated")
    }
}
```

### 4. All Views Receive Updates

- ScheduledActivityView
- QuickActivitiesListView
- Any other view displaying activity credits

## Credit Flow

```
1. Window Time Passes (e.g., 2:00 PM - 2:10 PM)
   ↓
2. ContentView timer fires (every 60 seconds)
   ↓
3. ContentView detects expired window
   ↓
4. Calls activity.markWindowAsSkipped()
   ↓
5. Credit added: accumulatedWindowCredits += 1
   ↓
6. Database saved
   ↓
7. "ActivityUpdated" notification posted
   ↓
8. All views refresh and show new credit count
```

## Timing

### Check Frequency
- **Every 60 seconds** (1 minute)
- **On app launch** (onAppear)
- **Manual trigger** via "CheckExpiredWindows" notification

### Why 60 Seconds?
- Balance between responsiveness and performance
- Activity windows are typically 10+ minutes
- 1-minute delay is acceptable for credit accumulation
- Reduces battery usage compared to 1-second checks

### Immediate Checks
You can trigger an immediate check by posting:
```swift
NotificationCenter.default.post(name: NSNotification.Name("CheckExpiredWindows"))
```

## Benefits

### ✅ Always Active
Credits accumulate even when:
- Viewing Tasks tab
- Viewing Habits tab
- Viewing Points tab
- Using floating quick activity button
- App is in foreground on any screen

### ✅ Centralized Logic
- Single source of truth
- Easier to maintain
- Consistent behavior across app

### ✅ Better Performance
- 60-second checks vs 1-second checks
- Reduced CPU usage
- Better battery life

### ✅ Reliable
- No dependency on viewing specific screens
- Works as long as app is in foreground
- Automatic on app launch

## View Responsibilities

### ContentView
- ✅ Detects expired windows
- ✅ Adds credits
- ✅ Saves to database
- ✅ Notifies other views

### ScheduledActivityView
- ✅ Displays activities
- ✅ Shows credit counts
- ✅ Listens for updates
- ❌ No longer checks for expired windows

### QuickActivitiesListView
- ✅ Displays activities
- ✅ Shows credit counts
- ✅ Listens for updates
- ✅ Manual refresh button
- ❌ No longer checks for expired windows

## Edge Cases Handled

### 1. Recently Edited Activities
```swift
let maxWindowsToSkip = activity.needsPostEditReset() ? 1 : min(newlySkipped, 3)
```
- Only marks 1 window at a time for recently edited activities
- Prevents bulk credit accumulation after editing

### 2. Multiple Missed Windows
```swift
let maxWindowsToSkip = min(newlySkipped, 3)
```
- Maximum 3 windows marked per check cycle
- Prevents overwhelming credit accumulation

### 3. Period Resets
```swift
activity.checkAndResetCounters()
```
- Daily activities reset at midnight
- Weekly activities reset monthly
- Monthly activities reset quarterly
- Quarterly activities reset yearly

## Notifications

### Sent by ContentView
```swift
NotificationCenter.default.post(name: NSNotification.Name("ActivityUpdated"))
```

### Received by Views
```swift
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ActivityUpdated"))) { _ in
    // Refresh UI
}
```

## Testing

### Verify Credits Accumulate
1. Create an activity with a window time
2. Let the window pass without using it
3. Wait up to 60 seconds
4. Check any screen - credits should appear

### Verify Cross-Tab Functionality
1. Create an activity with a window
2. Navigate to Tasks tab (not Activities tab)
3. Let window expire
4. Wait 60 seconds
5. Open quick activities button
6. Credits should be visible

### Manual Trigger
```swift
// Force immediate check
NotificationCenter.default.post(
    name: NSNotification.Name("CheckExpiredWindows"),
    object: nil
)
```

## Performance Impact

### Before
- ScheduledActivityView: 1-second timer
- Checks: 60 per minute
- CPU: Higher usage when on Activities tab

### After
- ContentView: 60-second timer
- Checks: 1 per minute
- CPU: 60x less frequent checks
- Battery: Improved life

## Migration Notes

### What Changed
1. ✅ Moved `checkForExpiredWindows()` from ScheduledActivityView to ContentView
2. ✅ Changed timer from 1 second to 60 seconds
3. ✅ Added `@Query` for activeActivities in ContentView
4. ✅ Added notification posting after credit addition
5. ✅ Removed duplicate logic from ScheduledActivityView

### What Stayed the Same
1. ✅ Credit calculation logic unchanged
2. ✅ `markWindowAsSkipped()` function unchanged
3. ✅ UI display logic unchanged
4. ✅ Manual refresh button still works

## Future Enhancements

### Potential Improvements
- Background credit accumulation (when app is backgrounded)
- Push notifications when credits are added
- Credit accumulation history/log
- Adjustable check frequency in settings
- Real-time credit updates (websocket/live query)

## Code Locations

### ContentView.swift
- Lines: Timer definition, @Query, checkForExpiredWindows()
- Responsibility: Credit accumulation

### ScheduledActivityView.swift
- Removed: checkForExpiredWindows() function
- Kept: UI display, timer for currentTime updates

### QuickActivityButton.swift
- No changes needed
- Already listens to "ActivityUpdated" notification
