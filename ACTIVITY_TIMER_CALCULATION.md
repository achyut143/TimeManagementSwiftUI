# Activity Timer Duration Calculation

## How Timer Duration is Calculated

When you use activity credits or overdraft windows, the timer duration is calculated by combining **both** reward time and task time attachments.

### Formula

```
Timer Duration = (Reward Time + Task Time) × Credits/Windows Used
```

## Calculation Logic

### Step 1: Check Reward Attachment
```swift
if activity.hasRewardAttachment {
    timerMinutes += activity.rewardBurnAmount × creditsUsed
}
```

### Step 2: Check Task Attachment
```swift
if activity.hasTaskAttachment {
    timerMinutes += activity.taskTimeAmount × creditsUsed
}
```

### Step 3: Show Timer if Any Time Available
```swift
if timerMinutes > 0 {
    // Show timer confirmation dialog
    // Start timer in Dynamic Island
} else {
    // No timer, just use credits/overdraft
}
```

## Examples

### Example 1: Reward Time Only
- Activity has reward attachment: **10 minutes**
- Activity has NO task attachment
- Using **3 credits**

**Calculation:**
```
Timer = (10 + 0) × 3 = 30 minutes
```

### Example 2: Task Time Only
- Activity has NO reward attachment
- Activity has task attachment: **15 minutes**
- Using **2 credits**

**Calculation:**
```
Timer = (0 + 15) × 2 = 30 minutes
```

### Example 3: Both Reward and Task Time
- Activity has reward attachment: **10 minutes**
- Activity has task attachment: **5 minutes**
- Using **4 credits**

**Calculation:**
```
Timer = (10 + 5) × 4 = 60 minutes (1 hour)
```

### Example 4: No Attachments
- Activity has NO reward attachment
- Activity has NO task attachment
- Using **3 credits**

**Calculation:**
```
Timer = (0 + 0) × 3 = 0 minutes
Result: No timer shown, credits used immediately
```

### Example 5: Overdraft with Both Attachments
- Activity has reward attachment: **8 minutes**
- Activity has task attachment: **12 minutes**
- Using **2 overdraft windows**

**Calculation:**
```
Timer = (8 + 12) × 2 = 40 minutes
```

## Scenarios Summary

| Reward Time | Task Time | Credits | Timer Duration | Timer Shown? |
|-------------|-----------|---------|----------------|--------------|
| 10 min | 0 min | 3 | 30 min | ✅ Yes |
| 0 min | 15 min | 2 | 30 min | ✅ Yes |
| 10 min | 5 min | 4 | 60 min | ✅ Yes |
| 0 min | 0 min | 3 | 0 min | ❌ No |
| 5 min | 10 min | 1 | 15 min | ✅ Yes |
| 20 min | 20 min | 2 | 80 min | ✅ Yes |

## What Happens When Timer Starts

1. **Timer Confirmation Dialog** appears:
   ```
   "Would you like to start a [X] minute timer in the Dynamic Island?"
   ```

2. **User Options:**
   - "Yes, Start Timer" → Starts timer + uses credits/overdraft
   - "No, Just Use" → Uses credits/overdraft without timer
   - "Cancel" → Cancels entire operation

3. **If Timer Started:**
   - Appears in Dynamic Island with highest priority
   - Counts down from calculated duration
   - Floating orange button appears for controls
   - Can pause/resume/cancel
   - Auto-ends when reaches zero
   - Sends notification on completion

## Benefits of Combined Time

### Use Case 1: Reward-Focused Activity
- Activity: "Study Session"
- Reward: 30 min Netflix time
- Task: 0 min
- **Timer tracks your earned Netflix time**

### Use Case 2: Task-Focused Activity
- Activity: "Morning Workout"
- Reward: 0 min
- Task: 45 min added to "Exercise" task
- **Timer tracks your workout commitment**

### Use Case 3: Combined Motivation
- Activity: "Deep Work Session"
- Reward: 15 min break time
- Task: 60 min added to "Project X"
- **Timer tracks both your break time AND project progress**
- Total: 75 minutes per credit

## Implementation Details

### Code Location
`FocusFlowSwift/Views/QuickActivityButton.swift`
- `handleCreditUse()` function
- `handleOverdraftUse()` function

### Key Properties
- `activity.hasRewardAttachment` - Boolean check
- `activity.rewardBurnAmount` - Minutes per credit (reward)
- `activity.hasTaskAttachment` - Boolean check
- `activity.taskTimeAmount` - Minutes per credit (task)

### Timer Manager
`FocusFlowSwift/Models/ActivityTimerManager.swift`
- `startTimer(activityName:durationMinutes:)` - Starts the countdown
- Receives the combined duration in minutes

## Edge Cases

### Zero Duration
If both attachments exist but amounts are 0:
```
Timer = (0 + 0) × credits = 0 minutes
Result: No timer shown
```

### Very Long Duration
If combined time is very long (e.g., 120 minutes):
- Timer still works normally
- Shows hours:minutes:seconds format
- Can be cancelled anytime via floating button

### Fractional Minutes
If task/reward amounts have decimals:
```
Reward: 7.5 minutes
Task: 12.5 minutes
Credits: 2
Timer = (7.5 + 12.5) × 2 = 40 minutes
```

## User Experience

The combined timer provides:
- **Clarity**: One timer for all time-based benefits
- **Motivation**: See total time you're earning/committing
- **Flexibility**: Works with any combination of attachments
- **Simplicity**: No need to track multiple timers
