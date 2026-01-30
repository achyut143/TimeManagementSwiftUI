# Quick Task Input Implementation

## Overview
Replaced AI-based task creation with a simple, fast text-based quick task input system that uses a structured format for creating tasks.

## Changes Made

### 1. Created QuickTaskParser (`Models/QuickTaskParser.swift`)
A parser that handles two formats:

**Timed Tasks:**
```
15:30 - 16:30 - shovel snow - 2 - r2
```
- `15:30` = start time
- `16:30` = end time
- `shovel snow` = task title
- `2` = weight (optional, defaults to 1)
- `r2` = repeat every 2 days (optional)

**Untimed Tasks:**
```
shovel snow - 2 - r2
```
- `shovel snow` = task title
- `2` = weight (optional, defaults to 1)
- `r2` = repeat every 2 days (optional)

### 2. Created QuickTaskInputView (`Views/QuickTaskInputView.swift`)
A reusable SwiftUI component that:
- Provides a text editor for quick task input
- Shows help text with examples when user taps the `?` button
- Displays placeholder text showing the format
- Has a "Create Task" button that parses and creates the task
- Uses the QuickTaskParser to validate and parse input

### 3. Updated TasksCalendarView
**Removed:**
- AI Assistant section (`aiTaskCreationHeader`)
- Speech recognition functions (`toggleRecording`, `startRecording`, `stopRecording`)
- AI task generation (`generateAITask`, `createTaskWithFallback`)
- Helper functions (`convertTo24Hour`, `parseDate`)
- State variables: `showAITaskCreation`, `aiInput`, `isRecording`, `isProcessing`, `audioEngine`, `recognitionTask`
- Import: `Speech`

**Added:**
- `quickTaskInputView` using `QuickTaskInputView` component
- `createQuickTask(from:)` function to create tasks from parsed input
- State variables: `showQuickTaskInput`, `quickTaskInput`
- Toggle button changed from "AI" to "Quick"

### 4. Updated UntimedTasksView
**Removed:**
- Same AI-related code as TasksCalendarView
- All speech recognition and AI generation functions

**Added:**
- Same quick task input functionality as TasksCalendarView
- `createQuickTask(from:)` function

## Benefits

1. **Faster**: No API calls, instant task creation
2. **Simpler**: Clear, predictable format
3. **Offline**: Works without internet connection
4. **Consistent**: Same format for both timed and untimed tasks
5. **Reusable**: Common parser and view component used in both views
6. **Flexible**: Weight and repeat are optional

## Usage Examples

### Timed Tasks
- `9:00 - 10:00 - morning routine` → Creates task from 9am to 10am, weight 1
- `15:30 - 16:30 - gym - 3` → Creates task from 3:30pm to 4:30pm, weight 3
- `14:00 - 15:00 - meeting - 2 - r7` → Creates task, weight 2, repeats every 7 days

### Untimed Tasks
- `buy groceries` → Creates untimed task, weight 1
- `call mom - 2` → Creates untimed task, weight 2
- `water plants - 1 - r3` → Creates untimed task, weight 1, repeats every 3 days

## Task Creation for Selected Date
All tasks are created for the currently selected date in the date picker. This applies to both timed and untimed tasks.

## Code Cleanup
- Removed unused imports (`Speech`)
- Removed ~150 lines of AI-related code from each view
- Consolidated task creation logic into reusable components
