# Scheduled Activity Recurrence Patterns

## Overview
The scheduled activity system now supports four different recurrence patterns with different reward reset behaviors. This allows for both short-term daily habits and longer-term periodic activities.

## Recurrence Types

### 1. Daily Activities
- **Pattern**: Every day
- **Icon**: 📅 calendar
- **Reward Reset**: Credits reset to 0 every day at midnight
- **Use Case**: Daily habits like social media limits, exercise, reading
- **Example**: "Check Instagram" - 2:00 PM and 8:00 PM daily

### 2. Weekly Activities  
- **Pattern**: Selected days of the week
- **Icon**: 🕐 calendar.badge.clock
- **Reward Reset**: Credits persist for the entire month, reset on 1st of each month
- **Selection**: Choose specific weekdays (Sunday through Saturday)
- **Use Case**: Weekly routines, gym days, social activities
- **Example**: "Gym Session" - Monday, Wednesday, Friday at 6:00 AM

### 3. Monthly Activities
- **Pattern**: Selected days of the month
- **Icon**: ⭕ calendar.circle  
- **Reward Reset**: Credits persist for the entire quarter, reset quarterly (Jan, Apr, Jul, Oct)
- **Selection**: Choose specific days (1-31)
- **Use Case**: Monthly tasks, bill payments, reviews
- **Example**: "Budget Review" - 1st and 15th of each month at 10:00 AM

### 4. Quarterly Activities
- **Pattern**: Selected months and days
- **Icon**: ➕ calendar.badge.plus
- **Reward Reset**: Credits persist for the entire year, reset on January 1st
- **Selection**: Choose specific months AND specific days within those months
- **Use Case**: Quarterly reviews, seasonal activities, major planning
- **Example**: "Quarterly Planning" - January, April, July, October on the 1st at 9:00 AM

## Key Features

### Smart Scheduling
- **Next Window Calculation**: System calculates next valid window based on recurrence pattern
- **Valid Day Checking**: Only shows active windows on valid days for the activity
- **Cross-Period Planning**: Can see next occurrence even if it's weeks/months away

### Reward System Differences

#### Daily Activities
- ✅ **Credits reset daily** - Fresh start every day
- ✅ **Encourages daily discipline** - Can't accumulate credits indefinitely
- ✅ **Simple tracking** - Today's usage vs skipped

#### Weekly/Monthly/Quarterly Activities  
- ✅ **Credits persist longer** - Accumulate across extended periods
- ✅ **Extended flexibility** - Can save credits for much longer periods
- ✅ **Period-based tracking** - Shows usage across entire persistence period
- ✅ **Longer reset cycles**:
  - **Weekly**: Credits persist for entire month
  - **Monthly**: Credits persist for entire quarter  
  - **Quarterly**: Credits persist for entire year

### UI Enhancements

#### Activity Creation
- **Recurrence Picker**: Choose from Daily, Weekly, Monthly, Quarterly
- **Dynamic Selection UI**: 
  - Weekly: Weekday buttons (Sun-Sat)
  - Monthly: Day grid (1-31)
  - Quarterly: Month selection + Day grid
- **Reset Description**: Shows when credits will reset
- **Validation**: Ensures proper selections for each type

#### Activity Display
- **Recurrence Icon**: Visual indicator of pattern type
- **Smart Countdown**: Shows time until next valid window
- **Period Statistics**: "Windows used/skipped in period" instead of "today"
- **Credit Persistence**: Non-daily activities keep credits longer

## Examples

### Daily Social Media Limit
```
📱 Instagram (Daily)
Times: 2:00 PM, 8:00 PM
Credits: Reset daily at midnight
Usage: 2 used today, 1 skipped today
```

### Weekly Gym Sessions
```
💪 Gym Workout (Weekly) 
Days: Mon, Wed, Fri at 6:00 AM
Credits: Reset monthly on 1st
Usage: 8 used this month, 4 skipped this month
Credits: 12 windows (persist until next month)
```

### Monthly Budget Review
```
💰 Budget Review (Monthly)
Days: 1st, 15th at 10:00 AM  
Credits: Reset quarterly (Jan, Apr, Jul, Oct)
Usage: 4 used this quarter, 2 skipped this quarter
Credits: 6 windows (persist until next quarter)
```

### Quarterly Planning
```
📊 Quarterly Review (Quarterly)
Months: Jan, Apr, Jul, Oct on 1st at 9:00 AM
Credits: Reset yearly on January 1st
Usage: 3 used this year, 1 skipped this year
Credits: 4 windows (persist until next year)
```

## Benefits

### Flexibility
- **Multiple Time Scales**: Support habits from daily to quarterly
- **Appropriate Reset Cycles**: Credits reset at natural boundaries
- **Smart Scheduling**: Only active on relevant days

### Discipline Encouragement
- **Daily Activities**: Prevent credit hoarding with daily resets
- **Weekly Activities**: Allow month-long flexibility for weekly routines
- **Monthly Activities**: Allow quarter-long flexibility for monthly tasks
- **Quarterly Activities**: Allow year-long flexibility for major planning
- **Visual Feedback**: Clear indication of pattern and next occurrence

### Real-World Usage
- **Daily Habits**: Social media, exercise, reading
- **Weekly Routines**: Gym, social events, cleaning
- **Monthly Tasks**: Bills, reviews, maintenance  
- **Quarterly Goals**: Planning, assessments, major tasks

This system provides the flexibility to manage both short-term daily habits and longer-term periodic activities with appropriate reward mechanics for each time scale.