# Overdraft Tracking & Chart Visualization Feature

## Overview
Added the ability to use more activity windows than allocated (overdraft) and visualize window usage with interactive daily charts over customizable date ranges.

## Key Features

### 1. Overdraft Window Usage
- Users can now use more windows than their allocated amount
- Overdraft usage is tracked separately from regular window usage
- Overdraft windows still trigger reward burning and task time addition
- Overdraft counter resets at the same time as other counters (based on recurrence type)

### 2. Daily Chart Visualization
- Interactive line chart showing data over time with smart aggregation
- **Adaptive X-axis based on recurrence type:**
  - **Daily activities**: Shows individual days (e.g., "Feb 1", "Feb 15")
  - **Weekly activities**: Shows weeks (e.g., "Week of Feb 1", "Week of Feb 8")
  - **Monthly activities**: Shows months (e.g., "Jan 2026", "Feb 2026")
  - **Quarterly activities**: Shows months (aggregated monthly view)
- Y-axis: Number of windows
- Three colored areas with lines:
  - Allocated windows (blue gradient with circles)
  - Used windows (green gradient with squares)
  - Overdraft windows (red gradient with triangles)
- **Smart date range presets based on activity type:**
  - Daily: Last 7 Days, Last 30 Days, This Month
  - Weekly: Last 4 Weeks, Last 12 Weeks, This Quarter
  - Monthly: Last 3 Months, Last 6 Months, This Year
  - Custom date range picker for all types
- Summary statistics for selected range
- Usage percentage calculation
- Overdraft percentage display

### 3. Integration Points

#### QuickActivityButton View
- Added overdraft option in the CreditUseView sheet
- Expandable overdraft section with +/- controls
- Shows what rewards/tasks will be affected
- Separate "Use Overdraft Windows" button

#### ActivityRewardsView
- Added "View Chart" button for each activity
- Added "Use Overdraft" button for each activity
- New OverdraftUseView sheet for overdraft selection
- Chart opens in a modal sheet

#### ScheduledActivityView
- Added "View Usage Chart" button on each activity card
- Displays overdraft usage if any windows used
- Chart accessible from main activity list

## Model Changes

### ScheduledActivity Model
Added properties:
- `overdraftWindowsUsed: Int` - Tracks overdraft window usage

Added methods:
- `useOverdraftWindows(_ windows: Int, context: ModelContext) -> Bool`
  - Increments overdraft counter
  - Burns attached rewards (multiplied by windows)
  - Adds time to attached tasks (multiplied by windows)
  - Records usage in history

### ActivityUsageType Enum
Added new case:
- `.overdraftUsage` - Tracks overdraft window usage in history

## New Files

### ActivityWindowChartView.swift
- SwiftUI view with Charts framework
- Uses SwiftData @Query to fetch ActivityUsageHistory
- **Adaptive aggregation based on activity recurrence type:**
  - Daily activities: Shows daily data points
  - Weekly activities: Aggregates data by week
  - Monthly/Quarterly activities: Aggregates data by month
- Displays line chart with area fills (gradient colors)
- Date range filtering with:
  - Custom date picker (start and end dates)
  - Context-aware quick presets (different for daily/weekly/monthly)
- Calculates metrics per time period:
  - Allocated windows based on recurrence pattern
  - Used windows from usage history
  - Overdraft windows from usage history
- Shows detailed statistics for selected range
- Calculates usage percentages
- Adapts X-axis labels and formatting based on aggregation mode

## Usage Flow

### Viewing Charts:
1. From ScheduledActivityView: Tap "View Usage Chart" on any activity card
2. From ActivityRewardsView: Tap "View Chart" on any activity card
3. Chart opens with appropriate default range:
   - Daily activities: Last 30 days
   - Weekly activities: Last 12 weeks
   - Monthly activities: Last 6 months
   - Quarterly activities: Last 12 months
4. Tap date range button to change period
5. Select preset or custom dates
6. Chart updates automatically with aggregated data

### Filtering Date Range:
1. Tap the date range button (shows current range)
2. Choose a preset based on activity type:
   - **Daily**: Last 7 Days, Last 30 Days, This Month
   - **Weekly**: Last 4 Weeks, Last 12 Weeks, This Quarter
   - **Monthly/Quarterly**: Last 3 Months, Last 6 Months, This Year
3. Or use date pickers for custom range
4. Chart and statistics update immediately with proper aggregation

## Technical Details

### Chart Data Calculation
The chart queries ActivityUsageHistory from SwiftData and calculates metrics based on aggregation mode:

**Daily Aggregation (for daily activities):**
- Shows individual days on X-axis
- Each data point represents one day
- Allocated windows checked per day based on recurrence pattern

**Weekly Aggregation (for weekly activities):**
- Shows weeks on X-axis (labeled as "Week of [date]")
- Each data point represents one week (7 days)
- Sums allocated, used, and overdraft windows for all days in the week

**Monthly Aggregation (for monthly/quarterly activities):**
- Shows months on X-axis (labeled as "Jan 2026", etc.)
- Each data point represents one month
- Sums allocated, used, and overdraft windows for all days in the month

**Allocated Windows:**
- Checks if date is valid for activity's recurrence pattern
- Returns number of scheduled times for valid days
- Returns 0 for days that don't match recurrence pattern

**Used Windows:**
- Filters usage history for the specific time period
- Counts regular window usage and credit usage
- Excludes overdraft usage from this count

**Overdraft Windows:**
- Filters usage history for overdraft usage type
- Sums up creditsUsed values for accurate count
- Handles multiple overdraft uses per period

### Chart Display Logic
- **Line Chart**: Shows trends over time with smooth curves
- **X-Axis**: Dates with smart label spacing (shows ~7 labels max)
- **Y-Axis**: Window count with automatic scaling
- **Legend**: Color-coded with shape indicators
- **Responsive**: Adapts to different date range lengths

### Reset Behavior
- Overdraft counter resets with other counters based on recurrence type:
  - Daily: Resets daily at midnight
  - Weekly: Resets monthly on the 1st
  - Monthly: Resets quarterly
  - Quarterly: Resets yearly on January 1st

## Benefits

1. **Flexibility**: Users can use activities even when out of allocated windows
2. **Tracking**: Full visibility into overdraft usage
3. **Visualization**: Easy-to-understand charts show usage patterns over time
4. **Historical Analysis**: View trends across days, weeks, or months
5. **Date Filtering**: Focus on specific time periods for analysis
6. **Accountability**: Overdraft is clearly marked and tracked separately
7. **Consistency**: Overdraft still triggers reward/task integrations
8. **Pattern Recognition**: Identify days with high/low usage

## Future Enhancements

Possible additions:
- Overdraft limits or warnings
- Overdraft "debt" that must be paid back
- Export chart data to CSV
- Compare multiple activities side-by-side
- Weekly/monthly aggregated views
- Overdraft notifications when threshold reached
- Predictive analytics for future usage
