# Activity Timer Feature

## Overview
When using activity credits or overdraft windows, if the activity has a timed reward attachment, the app will prompt you to start a countdown timer in the Dynamic Island.

## How It Works

### 1. Timer Calculation
- The timer duration is calculated based on the reward burn amount (in minutes) multiplied by the number of credits/windows used
- Example: If reward burn amount is 10 minutes and you use 3 credits, the timer will be 30 minutes

### 2. Timer Confirmation Dialog
When you click "Use Credits" or "Use Overdraft Windows":
- If the activity has a reward attachment with time configured, a dialog appears
- The dialog shows: "Would you like to start a [X] minute timer in the Dynamic Island?"
- Options:
  - "Yes, Start Timer" - Starts the timer and uses the credits/overdraft
  - "No, Just Use" - Uses the credits/overdraft without starting a timer
  - "Cancel" - Cancels the entire operation

### 3. Dynamic Island Timer
The timer displays in the Dynamic Island with:
- **HIGH PRIORITY**: This timer has a relevance score of 100.0, making it appear on top of other Live Activities (like daily notes timer)
- **Compact View**: Timer icon and countdown
- **Expanded View**: 
  - Activity name
  - Large countdown timer
  - Progress percentage
  - Total duration
  - End time
  - Running/Paused status
- **Minimal View**: Timer icon

### 4. Priority System
- The activity timer uses a relevance score of 100.0 (maximum priority)
- When multiple Live Activities are running, iOS will prioritize showing this timer in the Dynamic Island
- Other timers (like daily notes) will be deprioritized while the activity timer is running
- Once the activity timer ends, other Live Activities will return to normal priority

### 4. Timer Features
- Live countdown in Dynamic Island
- Automatic end when time expires
- Visual progress indicator
- Persistent across app states
- Maximum priority (relevance score 100.0) - appears above all other Live Activities
- Manual controls: Pause, Resume, and Cancel
- Floating button appears when timer is active
- Notification when timer completes

### 5. Timer Controls
When a timer is active, a floating orange button appears in the app:
- Click the button to open timer controls
- View remaining time and progress
- Pause/Resume the timer
- Cancel the timer with confirmation
- See timer status (Running/Paused)

## Implementation Files

### New Files Created
1. `FocusFlowWidgets/ActivityTimerAttributes.swift` - Live Activity attributes
2. `FocusFlowWidgets/ActivityTimerLiveActivityView.swift` - Lock screen/banner UI
3. `FocusFlowSwift/Models/ActivityTimerManager.swift` - Timer management singleton
4. `FocusFlowSwift/Views/ActiveTimerButton.swift` - Floating button and timer controls

### Modified Files
1. `FocusFlowWidgets/FocusFlowWidgets.swift` - Added ActivityTimerWidget
2. `FocusFlowSwift/Views/QuickActivityButton.swift` - Added timer confirmation logic
3. `FocusFlowSwift/ContentView.swift` - Added ActiveTimerButton to main view

## Usage Example

1. Create an activity with a timed reward attachment (e.g., 10 minutes per window)
2. Let windows accumulate as credits
3. Click the quick activity button
4. Select "Use Credits" and choose how many credits to use
5. Dialog appears: "Would you like to start a 30 minute timer?" (if using 3 credits)
6. Select "Yes, Start Timer"
7. Timer appears in Dynamic Island and counts down
8. Credits are used and reward is burned
9. An orange floating button appears - click it to:
   - View timer progress
   - Pause/Resume the timer
   - Cancel the timer
10. Timer automatically ends when countdown reaches zero
11. Notification is sent when timer completes

## Technical Notes

- Requires iOS 16.1+ for Live Activities
- Timer manager is a singleton (`ActivityTimerManager.shared`)
- Only one timer can run at a time (starting a new timer ends the previous one)
- Timer automatically ends when countdown reaches zero
- The timer is purely visual - it doesn't affect the actual activity window logic
- Uses relevance score of 100.0 to ensure highest priority in Dynamic Island
- When multiple Live Activities are running, this timer will be shown on top

## Future Enhancements
- ~~Pause/resume timer controls~~ ✅ Implemented
- ~~Timer notifications when complete~~ ✅ Implemented
- Multiple simultaneous timers
- Custom timer sounds/haptics
- Timer history and statistics
