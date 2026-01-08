# Activity Window Credits System

## Overview
The Activity Window Credits System allows users to earn window credits when they skip scheduled activity windows. Each unused window grants 1 window credit that can be used later. The system automatically resets daily to encourage consistent behavior.

## Key Features

### 1. Automatic Credit Tracking
- **Unused Windows**: When a scheduled activity window expires without being used, the system automatically adds 1 window credit to the activity's balance
- **Daily Reset**: All window credits and counters reset to 0 at the start of each new day
- **Usage Tracking**: The system tracks how many windows were used vs skipped each day

### 2. Credit Accumulation
- Each skipped window = 1 window credit
- Credits accumulate throughout the day
- Multiple activities can have their own credit balances
- Total credits is the sum of all activities' credits

### 3. Credit Usage
- **Individual Usage**: Use credits directly from each activity (1, 2, or 5 credit buttons)
- **Activity-Specific**: Credits can only be used for the same activity that earned them
- **No Cross-Activity Usage**: You cannot use credits from one activity for another activity

## Implementation Details

### Model Changes (`ScheduledActivity.swift`)
```swift
// New properties added to ScheduledActivity
var accumulatedWindowCredits: Int = 0       // Number of unused windows that can be used later
var lastResetDate: Date?                    // Track when credits were last reset
var windowsUsedToday: Int = 0               // Track windows used today
var windowsSkippedToday: Int = 0            // Track windows skipped today
```

### ActivityUsageHistory Model
```swift
// Enhanced to track both regular window usage and credit usage
var usageType: ActivityUsageType = .regularWindow  // Track usage type
var creditsUsed: Int?                              // Number of credits used (for credit usage)

enum ActivityUsageType {
    case regularWindow  // Normal scheduled window usage
    case creditUsage    // Using earned window credits
}
```

### Key Methods
- `checkAndResetDailyCounters()`: Resets counters if it's a new day
- `markWindowAsUsed()`: Called when user uses an activity window
- `markWindowAsSkipped()`: Called when window expires unused, adds 1 credit
- `useWindowCredits(_:context:)`: Deducts window credits when used and records in history
- `formattedWindowCredits()`: Returns formatted credit string (e.g., "1 window", "5 windows")

### UI Integration

#### Main Activity View
- **Credit Display**: Shows accumulated window credits for each activity
- **Quick Use Buttons**: 
  - "Use 1 Window Credit" button appears when activity has ≥1 credit
  - Available both in active windows and when waiting for next window
- **Credits Access**: Orange gift icon in toolbar opens dedicated credits view

#### Dedicated Credits View (`ActivityRewardsView.swift`)
- **Total Overview**: Shows combined window credits from all activities (for information only)
- **Individual Cards**: Each activity with credits gets its own card showing:
  - Activity name and credit balance
  - Daily usage statistics (windows used/skipped)
  - Quick use buttons (1, 2, 5 credits) - only for that specific activity

#### Activity History View (`ActivityHistoryView.swift`)
- **Enhanced History**: Shows both regular window usage and credit usage entries
- **Visual Distinction**: 
  - Regular window usage: Clock icon (blue)
  - Credit usage: Gift icon (orange)
- **Credit Details**: Shows number of credits used and usage notes
- **Filtering**: Can filter by day, week, month, or all time

### Automatic Processing
The system automatically:
1. **Checks for expired windows** every second via timer
2. **Marks windows as skipped** when they expire unused
3. **Resets daily counters** at midnight
4. **Records all usage** in activity history (both regular and credit usage)
5. **Saves changes** to the database

## Usage Flow

### Earning Credits
1. User has scheduled activities with time windows
2. When a window opens, user can either:
   - Use the window (marks as used, no credit)
   - Let it expire (automatically marks as skipped, +1 window credit)
3. Credits accumulate throughout the day

### Using Credits
1. **Individual Use Only**: Each activity can only use its own earned credits
2. **Quick Use**: Tap "Use 1 Window Credit" button on any activity card
3. **Credits View**: 
   - Tap gift icon in toolbar to see all credits
   - Use buttons (1, 2, 5) for each individual activity
   - Cannot transfer credits between activities
4. **Automatic Recording**: System records credit usage in activity history with timestamp and details
5. System deducts from that activity's credit balance only

### Daily Reset
- At midnight, all counters reset:
  - `accumulatedWindowCredits` → 0
  - `windowsUsedToday` → 0
  - `windowsSkippedToday` → 0
  - `lastResetDate` → current date

## Benefits
- **Encourages Discipline**: Users are rewarded for sticking to their schedule
- **Activity-Specific Rewards**: Credits earned by skipping one activity can only be used for that same activity
- **Flexible Usage**: Earned credits can be used when needed for the specific activity
- **Daily Fresh Start**: Reset system prevents indefinite accumulation
- **Visual Feedback**: Clear display of earned credits and usage statistics per activity
- **Complete History Tracking**: All credit usage is recorded with timestamps and details
- **Automatic Management**: No manual tracking required
- **Simple Counting**: Easy to understand - 1 skipped window = 1 credit for that activity
- **No Cross-Contamination**: Prevents using credits from disciplined activities to justify overuse of others
- **Audit Trail**: Full history of when and how credits were earned and used

## Technical Notes
- Credit tracking is integrated into existing `ScheduledActivity` model
- Uses SwiftData for persistence
- Timer-based checking ensures real-time updates
- Graceful handling of day transitions and app restarts
- Credits are counted as integers (whole windows) rather than time-based units