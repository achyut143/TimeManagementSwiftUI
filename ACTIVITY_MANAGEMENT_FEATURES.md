# Activity Management Features

## ✅ Edit & Delete Functionality

### Edit Activities
- **Access**: Tap the "⋯" menu on any activity card → "Edit"
- **Features**:
  - Change activity name
  - Add/remove scheduled times
  - Adjust window duration (1-60 minutes)
  - Enable/disable activity
  - Real-time preview of changes

### Delete Activities
- **Access**: Tap the "⋯" menu on any activity card → "Delete"
- **Safety**: Confirmation dialog prevents accidental deletion
- **Complete removal**: Deletes activity and all associated data

## ✅ Smart Quick Access System

### Toolbar Shortcut
- **Location**: Top-right of main Tasks screen
- **Icon**: Purple clock with plus (🕐➕)
- **Function**: Direct access to create new activity without navigating to Activities tab

### Quick Activity Buttons (Floating)
- **Location**: Bottom-right corner of screen
- **Smart Design**: Two context-aware buttons
  1. **Activities List** (Dynamic color): Quick access to all activities
     - **Blue clock**: Normal countdown mode (activities waiting)
     - **Green clock**: Active window available (ready to use)
     - **Hidden**: When no activities exist
  2. **New Activity** (Purple plus): Create new activity instantly

### Quick Activities List
- **Compact view**: Shows all activities with real-time status
- **Smart actions**: 
  - **"Use" button**: Only appears for activities with active windows
  - **Time display**: Shows either countdown to next window or remaining window time
  - **Color coding**: Green for active, secondary for waiting
- **One-tap access**: Direct to activity windows without navigation

## 🎯 Streamlined Workflow

### Creating Activities
1. **Method 1**: Activities tab → "+" button (traditional)
2. **Method 2**: Tasks tab → Purple clock icon (quick toolbar)
3. **Method 3**: Purple floating "+" button (instant access)

### Managing Activities
1. **View all**: Activities tab or blue/green floating button
2. **Edit**: Activity card → "⋯" → "Edit"
3. **Delete**: Activity card → "⋯" → "Delete" → Confirm
4. **Quick use**: Green floating button → Select activity → "Use"

### Using Activities
1. **From main view**: When window is active, tap "Use Window" on activity card
2. **From quick access**: Tap green floating button → Select activity → "Use"
3. **Full experience**: Activity window with countdown, notes, and completion tracking

## 🧠 Smart Design Decisions

### Why No Single Floating Timer?
- **Multiple activities**: Users can have several activities with different schedules
- **Context confusion**: A single timer wouldn't know which activity to display
- **Better solution**: Quick access button that shows all activities with their individual status
- **User choice**: Let users see all options and choose which activity to use

### Intelligent Button States
- **Dynamic visibility**: Buttons only appear when relevant
- **Color communication**: Instant visual feedback about activity status
- **Context awareness**: Different actions available based on current state

## 🔧 Technical Features

### Real-Time Status Management
- **Live updates**: All views update every second
- **Smart detection**: Automatic window status checking
- **Efficient queries**: Only active activities are monitored
- **Battery friendly**: Optimized timer usage

### Data Integrity
- **Safe operations**: Confirmation dialogs for destructive actions
- **Consistent state**: Real-time synchronization across all views
- **Reliable storage**: SwiftData persistence with error handling

## 📱 UI Excellence

### Visual Hierarchy
- **Purple**: Creation and new actions
- **Blue**: Waiting/countdown states  
- **Green**: Active/ready states
- **Red**: Destructive actions
- **Secondary**: Inactive states

### Icon Language
- `clock.badge.checkmark`: Activities (main tab)
- `clock.badge.plus`: Quick creation
- `clock.fill`: Activities list (countdown)
- `clock.badge.checkmark.fill`: Activities list (active)
- `plus`: New activity
- `ellipsis.circle`: Options menu
- `pencil`: Edit
- `trash`: Delete

This system provides the perfect balance of power and simplicity - multiple access points without overwhelming the interface, and smart contextual actions that adapt to your current needs.