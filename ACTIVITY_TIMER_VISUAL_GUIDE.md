# Activity Timer - Visual Guide

## UI Components

### 1. Timer Confirmation Dialog
```
┌─────────────────────────────────┐
│      Start Timer?               │
│                                 │
│  Would you like to start a      │
│  30 minute timer in the         │
│  Dynamic Island?                │
│                                 │
│  ┌──────────────────────────┐  │
│  │  Yes, Start Timer        │  │
│  └──────────────────────────┘  │
│  ┌──────────────────────────┐  │
│  │  No, Just Use            │  │
│  └──────────────────────────┘  │
│  ┌──────────────────────────┐  │
│  │  Cancel                  │  │
│  └──────────────────────────┘  │
└─────────────────────────────────┘
```

### 2. Dynamic Island - Compact View
```
┌──────────────────────┐
│  🕐  29:45           │  ← Timer icon + countdown
└──────────────────────┘
```

### 3. Dynamic Island - Expanded View
```
┌─────────────────────────────────────────┐
│  🕐 Activity Name                       │
│                                         │
│     29:45                    ● Running  │
│                                         │
│                              75%        │
│                                         │
│  Total: 30:00    Ends: 3:45 PM         │
└─────────────────────────────────────────┘
```

### 4. Floating Timer Button (In App)
```
                              ┌────┐
                              │ 🕐 │  ← Orange circle
                              │Act.│     "Active" text
                              └────┘
                                ↑
                    Positioned above
                    quick activity button
```

### 5. Timer Control Panel
```
┌─────────────────────────────────────┐
│  ← Activity Timer            Done   │
├─────────────────────────────────────┤
│                                     │
│        Activity Name                │
│                                     │
│           ╭─────────╮               │
│          │    29    │               │
│          │    45    │  ← Large      │
│          │          │    countdown  │
│          │   75%    │               │
│           ╰─────────╯               │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Total Duration:      30:00  │   │
│  │ End Time:           3:45 PM │   │
│  │ Status:      ● Running      │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  ⏸  Pause Timer             │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  ✕  Cancel Timer            │   │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

## Color Coding

### Timer States
- **Running**: 🟢 Green indicator, Orange timer
- **Paused**: 🟡 Yellow indicator, Yellow timer
- **Cancelled**: Timer removed

### Buttons
- **Start Timer**: Blue
- **Pause**: Yellow
- **Resume**: Green
- **Cancel**: Red
- **Floating Button**: Orange

## User Journey Visualization

```
Step 1: Use Credits
┌──────────────┐
│ Quick        │
│ Activity     │ → Click
│ Button       │
└──────────────┘

Step 2: Select Amount
┌──────────────┐
│ Credits: 3   │
│ [- 3 +]      │ → Confirm
│ Use Credits  │
└──────────────┘

Step 3: Timer Dialog
┌──────────────┐
│ Start 30min  │
│ timer?       │ → Yes
│ [Yes] [No]   │
└──────────────┘

Step 4: Timer Active
┌──────────────┐     ┌──────────┐
│ Dynamic      │     │ Floating │
│ Island       │ AND │ Button   │
│ 🕐 29:45     │     │ 🕐 Act.  │
└──────────────┘     └──────────┘

Step 5: Control Timer
┌──────────────┐
│ Click Float  │
│ Button       │ → Opens
└──────────────┘
        ↓
┌──────────────┐
│ Timer        │
│ Control      │
│ Panel        │
│ [Pause]      │
│ [Cancel]     │
└──────────────┘

Step 6: Timer Ends
┌──────────────┐
│ 00:00        │
│ ✓ Complete   │ → Auto-dismiss
│ Notification │
└──────────────┘
```

## Priority Visualization

### When Multiple Live Activities Are Running

```
Before Activity Timer:
┌─────────────────────┐
│ Daily Notes Timer   │ ← Shown in Dynamic Island
└─────────────────────┘

After Activity Timer Starts:
┌─────────────────────┐
│ Activity Timer      │ ← Shown in Dynamic Island (Priority 100)
└─────────────────────┘
┌─────────────────────┐
│ Daily Notes Timer   │ ← Deprioritized
└─────────────────────┘

After Activity Timer Ends:
┌─────────────────────┐
│ Daily Notes Timer   │ ← Returns to Dynamic Island
└─────────────────────┘
```

## Screen Positions

```
┌─────────────────────────────────┐
│  ← Tasks                   🕐 ⊕ │ ← Top toolbar
├─────────────────────────────────┤
│                                 │
│                                 │
│        Main Content             │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│                          ┌────┐ │
│                          │ 🕐 │ │ ← Timer button
│                          │Act.│ │   (when active)
│                          └────┘ │
│                          ┌────┐ │
│                          │ 🕐 │ │ ← Quick activity
│                          │Low │ │   button
│                          └────┘ │
├─────────────────────────────────┤
│  📅   🔁   ⭐   🎁   🔔        │ ← Tab bar
└─────────────────────────────────┘
```

## Interaction Flow

```
1. User Action
   ↓
2. Confirmation Dialog
   ↓
3. Timer Starts
   ├→ Dynamic Island (Priority 100)
   └→ Floating Button Appears
   ↓
4. User Can:
   ├→ View in Dynamic Island
   ├→ Click Floating Button
   │  ├→ View Progress
   │  ├→ Pause/Resume
   │  └→ Cancel
   └→ Let Timer Run
   ↓
5. Timer Completes
   ├→ Notification Sent
   ├→ Auto-dismiss
   └→ Floating Button Disappears
```

## Tips

- **Orange = Active Timer**: Look for orange color to identify timer-related UI
- **Tap Dynamic Island**: Expands to show full timer details
- **Floating Button**: Quick access to timer controls without leaving current screen
- **Confirmation Required**: Cancel action requires confirmation to prevent accidents
- **Auto-dismiss**: Control panel automatically closes when timer ends
