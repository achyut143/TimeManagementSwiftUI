# FocusFlow — Time Management & Habit Tracker

A comprehensive iOS productivity app built with SwiftUI and SwiftData. FocusFlow combines task scheduling, habit tracking, a discipline scoring system, activity-based rewards, and Live Activity / Dynamic Island support into one cohesive workflow.

---

## Table of Contents

- [Requirements](#requirements)
- [Build Instructions](#build-instructions)
- [App Architecture](#app-architecture)
- [Features & Usage Guide](#features--usage-guide)
  - [Tasks Calendar](#1-tasks-calendar)
  - [Habits Overview](#2-habits-overview)
  - [Points Dashboard](#3-points-dashboard)
  - [Rewards & Activities](#4-rewards--activities)
  - [Alert Manager](#5-alert-manager)
  - [Books & Quotes](#6-books--quotes)
  - [Widgets & Live Activities](#7-widgets--live-activities)
- [Screenshots](#screenshots)
- [AI Integration (OpenAI)](#ai-integration-openai)
- [Troubleshooting](#troubleshooting)

---

## Requirements

| Requirement | Version |
|-------------|---------|
| Xcode | 15.0 or later |
| iOS Deployment Target | iOS 17.0+ |
| Swift | 5.9+ |
| Device | iPhone (Live Activities require a physical device) |
| macOS (host) | macOS 14 Sonoma or later |

---

## Build Instructions

### 1. Clone the Repository

```bash
git clone <repo-url>
cd FocusFlow
```

### 2. Open the Xcode Project

```bash
open TimeManagementSwiftUI/FocusFlowSwift.xcodeproj
```

### 3. Configure Signing

1. In the Xcode Project Navigator, select the **FocusFlowSwift** project root.
2. Select the **FocusFlowSwift** target → **Signing & Capabilities**.
3. Set your **Team** to your Apple Developer account.
4. Change the **Bundle Identifier** to a unique reverse-domain string (e.g., `com.yourname.focusflow`).
5. Repeat for the **FocusFlowWidgets** extension target — it must share the same App Group.

### 4. App Groups (Required for Widgets)

Both the main app target and the widget extension must belong to the same App Group:

1. **FocusFlowSwift** target → Signing & Capabilities → **+ Capability** → App Groups.
2. Add or create a group (e.g., `group.com.yourname.focusflow`).
3. Repeat the same App Group on the **FocusFlowWidgets** target.
4. Update any `UserDefaults(suiteName:)` calls in the code to match your group identifier if you changed it.

### 5. Background Modes (already configured in Info.plist)

The following background modes are enabled:

- `fetch` — background data refresh
- `processing` — BGTaskScheduler
- `audio` — audio session
- `location` — location updates
- `bluetooth-central` — Bluetooth

These are pre-configured in `FocusFlowSwift/Info.plist`. No manual changes needed unless you modify capabilities.

### 6. Optional: OpenAI API Key

FocusFlow includes an AI feature for generating book quotes. To enable it:

1. Open `FocusFlowSwift/Info.plist`.
2. Set the value for the key `OpenAI_API_Key` to your OpenAI API key.

If left empty, AI quote generation is silently disabled; all other features work normally.

### 7. Select Target & Run

1. Choose a simulator or a connected iPhone as the run destination.
2. Press **⌘R** (or Product → Run).
3. On first launch you will be prompted for:
   - **Notifications** permission — required for Alert Manager.
   - **Speech Recognition** — required for voice task input.
   - **Microphone** — required for voice input.

> **Live Activities & Dynamic Island** only function on a physical device running iOS 16.1+. They are gracefully hidden in Simulator.

### 8. Running Tests

```
⌘U  — Product → Test
```

---

## App Architecture

```
FocusFlowSwift/
├── FocusFlowSwiftApp.swift      # App entry: SwiftData container, permissions, background tasks
├── ContentView.swift            # Root TabView (5 tabs)
├── Models/                      # SwiftData @Model classes + plain structs
│   ├── Task.swift               # Core task entity
│   ├── Habit.swift / HabitSettings.swift
│   ├── Reward.swift / TaskRewardLink.swift
│   ├── ScheduledActivity.swift
│   ├── AlertInstance.swift
│   ├── Book.swift / BookQuote.swift
│   ├── DailyNote.swift
│   ├── TaskMetrics.swift / DisciplineMuscle.swift
│   └── ...
├── Views/                       # SwiftUI views organised by feature
│   ├── TasksCalendarView.swift
│   ├── HabitOverviewView.swift
│   ├── PointsDashboardView.swift
│   ├── RewardsActivitiesTabView.swift
│   ├── AlertManagerView.swift
│   └── ...
├── Managers/                    # Singleton service objects
│   ├── AlertManager.swift
│   ├── NotificationManager.swift
│   ├── ActivityTimerManager.swift
│   ├── BackgroundCounterManager.swift
│   └── LiveActivityManager.swift
└── Assets.xcassets/
```

**Persistence**: SwiftData with automatic migration. All models are stored in a shared container so the widget extension can read them.

---

## Features & Usage Guide

### 1. Tasks Calendar

**Location**: First tab (calendar icon)

The Tasks Calendar is the primary scheduling surface. It shows a date picker at the top and splits tasks into **timed** (appear in the timeline) and **untimed** (listed below).

#### Creating a Task — Quick Input

Tap the text field at the top and use the shorthand parser:

```
START - END - TITLE - WEIGHT - REPEAT
```

| Token | Example | Meaning |
|-------|---------|---------|
| Start time | `15:30` | 24-hour start |
| End time | `16:30` | 24-hour end |
| Title | `Deep work` | Task name |
| Weight | `2` | Points multiplier (default 1) |
| Repeat | `r2` | Repeat on weekdays (1=Mon … 7=Sun) |

**Example**: `09:00 - 10:00 - Morning review - 1 - r135` creates a 1-hour task on Mon, Wed, Fri.

If parsing fails, the full task-creation form opens automatically.

#### Creating a Task — Full Form

Tap **+** (floating button) → fill in title, start/end time, weight, subtasks, attachments, and any linked reward.

#### Completing a Task

- Tap the circle next to a task to toggle completion.
- Partial completion (by time) is tracked automatically against the scheduled window.
- Completed tasks contribute their weight as points to the Points Dashboard.

#### Subtasks

Inside a task's detail view, tap **Add Subtask**. Subtasks can be checked off independently; they roll up to the parent task's completion state.

#### Attachments

In task detail → **Add Attachment** — supports images from the photo library, files from the Files app, and PDFs.

#### Event Days

An *Event Day* marks a calendar date as a special occasion (Full Day, Morning, Afternoon, or Evening). Tasks on event days are visually highlighted and tracked separately in analytics.

Configure via the **Event Day** button on the calendar toolbar.

---

### 2. Habits Overview

**Location**: Second tab (chart icon)

Habits are recurring tasks that appear automatically based on their repeat schedule. This tab shows a 30-day retrospective and your **Discipline Muscle Score (DMS)** per habit.

#### Discipline Muscle Score

The DMS is a 0–1 score that reflects consistency:

| Score | Level | Meaning |
|-------|-------|---------|
| 0.90 – 1.00 | Strong 💪 | Near-perfect consistency |
| 0.75 – 0.89 | Growing 📈 | Mostly consistent |
| 0.60 – 0.74 | Inconsistent ⚡ | Needs attention |
| 0.40 – 0.59 | Weak 🔻 | Frequently missed |
| < 0.40 | Undertrained 💤 | Rarely done |

**How it is calculated**:
- Base = `(completions − decay penalties) / actual occurrences`
- Streak bonus = `longest streak / actual occurrences`
- 2+ consecutive misses apply a −0.5 rep penalty each.

#### Filtering Habits

Use the toolbar filters to show:
- All habits / Completed only / Incomplete only
- Filter by Discipline Level (Strong, Growing, etc.)
- Filter by tag

#### Archiving a Habit

Swipe left on a habit → **Archive**. Archived habits are viewable under **Archived Habits** (toolbar menu) and excluded from active metrics.

#### Exporting Habit Notes as PDF

Toolbar → **Export PDF** — generates a PDF of all daily notes associated with your habits for the selected period.

#### Changing Metrics Period

Toolbar → **Settings** — choose 30, 45, or 60 days for the analysis window.

---

### 3. Points Dashboard

**Location**: Third tab (star/points icon)

Points are earned by completing tasks. Each task has a configurable **weight** (points multiplier). The dashboard shows a calendar grid where each day's cell is filled proportionally to the day's completion percentage.

#### Reading the Grid

- **Full colour cell** — all tasks completed for that day.
- **Partial fill** — percentage of weighted tasks completed.
- **Event Day halo** — a coloured ring around cells that had an Event Day.
- Tap any day to see a breakdown of tasks and points earned.

#### Points Calculation

```
Daily points = Σ (task weight × completion fraction)
```

Where `completion fraction = minutes spent / minutes allocated` (capped at 1.0).

---

### 4. Rewards & Activities

**Location**: Fourth tab (gift/activity icon)

This tab has two sub-tabs: **Activities** and **Rewards**.

---

#### 4a. Scheduled Activities

Scheduled Activities are time-windowed blocks you can "check in" to (e.g., a 20-minute walk). They have a credit system — you earn credits by completing windows within the scheduled recurrence.

##### Creating an Activity

Tap **+** → fill in:
- **Name** — activity label.
- **Window size** — how long each session is (e.g., 20 min).
- **Recurrence** — Daily / Weekly / Monthly / Quarterly.
- **Credits per cycle** — how many windows you can use per cycle.

##### Using an Activity

On the Activities list, tap an activity → **Start Window**. A countdown timer starts (also visible in the Live Activity / Dynamic Island). When the window ends, the credit is consumed.

##### Activity History

Tap an activity → **History** to view all past windows with timestamps and durations.

---

#### 4b. Rewards

Rewards let you exchange accumulated points for real-world incentives.

##### Reward Types

| Type | How it works |
|------|--------------|
| **Time** | Convert points → minutes of leisure/screen time |
| **Money** | Convert points → spending money |
| **Goal** | Accumulate points until a threshold; then unlock a treat |
| **Guilt** | Log unplanned spending; interest accrues if not "paid off" with points |

##### Creating a Reward

Tap **+** → choose type, name, point cost, and (for Guilt rewards) interest rate and period.

##### Using a Reward

When you have enough points, the reward moves to **Ready to Use** status. Tap → **Redeem** to use it. Redeemed rewards move to **Utilized** and appear in the history.

##### Filtering Rewards

Use the status filter chips at the top: **Need Points / Ready / Utilized** or search by name.

##### Overdraft

For Money-type rewards you can enable **Overdraft**. If you spend beyond your earned points, the deficit accrues interest at your configured rate (e.g., 10% per 5 days) until you earn enough points to cover it.

##### Linking Tasks to Rewards

In task detail → **Link Reward** — when the task is completed, points are automatically credited to the linked reward.

---

### 5. Alert Manager

**Location**: Fifth tab (bell icon)

The Alert Manager schedules recurring local notifications at custom intervals — useful for reminders to drink water, take breaks, check posture, etc.

#### Creating an Alert

Tap **+** → set:
- **Name** — what the notification says.
- **Interval** — how often it fires (minimum 60 seconds per iOS limits).
- **Start / End time** — optionally restrict to waking hours.

#### Pausing & Resuming

- Swipe left on an alert → **Pause** to temporarily silence it without deleting.
- Tap **Resume** to re-activate.
- Toolbar has **Pause All** / **Resume All** global controls.

#### Multi-Timer View

Tap the **Multitask Timer** button to see all active alerts on one screen with individual countdowns.

---

### 6. Books & Quotes

**Location**: Accessible from the main menu / toolbar

Keep a library of books and store memorable quotes. Quotes can be added manually or generated via the OpenAI integration.

#### Adding a Book

Books list → **+** → enter title and author → Save.

#### Adding Quotes

Inside a book:
- **Manual**: tap **Add Quote** → type the quote and page number.
- **AI-assisted**: tap **Generate Quotes** — the app sends the book title/author to OpenAI and imports suggested quotes (requires API key in Info.plist).
- **Bulk Import**: tap **Bulk Import** → paste multiple quotes separated by line breaks.

#### Viewing Quotes

Quotes are displayed as cards. Swipe through them or view them in a list. Tap a quote to edit or delete.

---

### 7. Widgets & Live Activities

FocusFlow ships a widget extension (**FocusFlowWidgets**) with three Live Activity types visible on the Lock Screen and in the Dynamic Island (requires a physical device, iOS 16.1+).

| Widget | Shows |
|--------|-------|
| **Focus Activity** | Current task, cycle countdown, task counter |
| **Background Counter** | Time spent in current session / total background time |
| **Activity Timer** | Active scheduled-activity name, countdown, pause state |

#### Starting a Live Activity

- Begin a focus session from the Tasks Calendar → **Start Focus**.
- Start a scheduled activity window → the timer Live Activity launches automatically.
- Background Counter starts when you switch away from the app (toggleable in Settings).

#### Dynamic Island

- **Compact view** — shows the countdown or task count.
- **Minimal view** — shows the task count or a dot indicator.
- **Expanded view** — tap the island to see full timer, task name, cycle info, and pause/resume controls.

---

## Screenshots

> Add screenshots by dragging images into this section or by updating the paths below.
> Recommended: capture at 393 × 852 pt (iPhone 15 Pro) and save to `docs/screenshots/`.

| Screen | Screenshot |
|--------|------------|
| Tasks Calendar | `docs/screenshots/tasks_calendar.png` |
| Quick Task Input | `docs/screenshots/quick_task_input.png` |
| Habits Overview | `docs/screenshots/habits_overview.png` |
| Discipline Muscle Score | `docs/screenshots/discipline_muscle.png` |
| Points Dashboard | `docs/screenshots/points_dashboard.png` |
| Rewards List | `docs/screenshots/rewards.png` |
| Scheduled Activities | `docs/screenshots/activities.png` |
| Alert Manager | `docs/screenshots/alerts.png` |
| Books & Quotes | `docs/screenshots/books.png` |
| Live Activity / Dynamic Island | `docs/screenshots/live_activity.png` |

**To add screenshots**:

```bash
mkdir -p docs/screenshots
# Copy or move your simulator/device screenshots here
cp ~/Desktop/tasks_calendar.png docs/screenshots/
```

Then reference them in Markdown:

```markdown
![Tasks Calendar](docs/screenshots/tasks_calendar.png)
```

---

## AI Integration (OpenAI)

FocusFlow optionally uses the OpenAI API for book-quote generation.

1. Obtain an API key from [platform.openai.com](https://platform.openai.com).
2. Add the key to `FocusFlowSwift/Info.plist` under the key `OpenAI_API_Key`.
3. Build and run — the **Generate Quotes** button in any Book detail view will become active.

The app never sends personal task or habit data to OpenAI. Only book title and author are included in the prompt.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Live Activities not showing | Run on a physical device (iOS 16.1+); check that ActivityKit entitlement is enabled in Signing & Capabilities |
| Widgets show stale data | Verify App Group identifier matches between app and widget targets |
| Notifications not firing | Check Settings → Notifications → FocusFlow is set to Allow; intervals must be ≥ 60 s |
| SwiftData migration error on launch | Delete the app and reinstall (development only); data models changed between versions |
| OpenAI quotes not generating | Confirm API key in Info.plist and that your OpenAI account has quota remaining |
| Background time counter not working | Grant the app permission to run in background; ensure Background App Refresh is enabled in iOS Settings |

---

## License

This project is private. All rights reserved.
