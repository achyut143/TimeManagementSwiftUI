# Activity Timer Setup Instructions

## Files to Add to Xcode Project

You need to manually add these new files to your Xcode project:

### Widget Extension Files (FocusFlowWidgets target)
1. `FocusFlowWidgets/ActivityTimerAttributes.swift`
2. `FocusFlowWidgets/ActivityTimerLiveActivityView.swift`

### Main App Files (FocusFlowSwift target)
3. `FocusFlowSwift/Models/ActivityTimerManager.swift`
4. `FocusFlowSwift/Views/ActiveTimerButton.swift`

## Steps to Add Files in Xcode

1. Open your project in Xcode
2. Right-click on the `FocusFlowWidgets` folder in the Project Navigator
3. Select "Add Files to FocusFlowSwift..."
4. Navigate to and select:
   - `ActivityTimerAttributes.swift`
   - `ActivityTimerLiveActivityView.swift`
5. Make sure "FocusFlowWidgets" target is checked
6. Click "Add"

7. Right-click on the `Models` folder under `FocusFlowSwift`
8. Select "Add Files to FocusFlowSwift..."
9. Navigate to and select:
   - `ActivityTimerManager.swift`
10. Make sure "FocusFlowSwift" target is checked
11. Click "Add"

12. Right-click on the `Views` folder under `FocusFlowSwift`
13. Select "Add Files to FocusFlowSwift..."
14. Navigate to and select:
   - `ActiveTimerButton.swift`
15. Make sure "FocusFlowSwift" target is checked
16. Click "Add"

## Modified Files (Already Updated)

These files have been automatically updated:
- ✅ `FocusFlowWidgets/FocusFlowWidgets.swift` - Added ActivityTimerWidget
- ✅ `FocusFlowSwift/Views/QuickActivityButton.swift` - Added timer confirmation logic
- ✅ `FocusFlowSwift/ContentView.swift` - Added ActiveTimerButton

## Build and Run

1. Clean build folder (Cmd + Shift + K)
2. Build the project (Cmd + B)
3. Run on a physical device (Live Activities don't work in simulator)

## Testing the Feature

1. Create a scheduled activity with a timed reward attachment:
   - Go to Activities tab
   - Create or edit an activity
   - Attach a reward
   - Set burn type to "Time"
   - Set burn amount (e.g., 10 minutes)

2. Let the activity window pass to accumulate credits

3. Click the quick activity button (floating button)

4. Select "Use Credits" or "Use Overdraft"

5. You'll see a dialog: "Would you like to start a [X] minute timer in the Dynamic Island?"

6. Select "Yes, Start Timer"

7. The timer will appear in the Dynamic Island with highest priority

8. A floating orange button will appear in the app - click it to:
   - View timer progress and remaining time
   - Pause or resume the timer
   - Cancel the timer (with confirmation)

9. The timer will automatically end when it reaches zero

## Priority Behavior

- The activity timer uses a relevance score of 100.0 (maximum)
- When running, it will appear on top of other Live Activities (like daily notes timer)
- Other Live Activities will be deprioritized while this timer is active
- Once the timer ends, other Live Activities return to normal priority

## Troubleshooting

### Timer doesn't appear
- Make sure you're running on a physical device (not simulator)
- Check that Live Activities are enabled in Settings > Face ID & Passcode > Allow Access When Locked
- Verify the activity has a reward attachment with time configured

### Timer appears but doesn't update
- Check console logs for errors
- Verify ActivityTimerManager is properly initialized
- Make sure the timer update loop is running

### Multiple timers conflict
- Only one activity timer can run at a time
- Starting a new timer automatically ends the previous one
- This is by design to maintain priority

## Notes

- The timer is visual only - it doesn't affect activity window logic
- Timer automatically ends when countdown reaches zero
- You can manually end the timer by calling `ActivityTimerManager.shared.endTimer()`
