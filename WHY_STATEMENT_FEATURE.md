# Why Statement Feature

## Overview
Automatically generates motivational "why statements" for tasks using OpenAI's GPT-3.5 to help you understand your deeper purpose behind each task.

## Features

### Automatic Generation & Pinning
- When you open a task's action view, a why statement is automatically generated
- **The statement is automatically pinned after generation** (default behavior)
- Pinned statements are copied to new repeat tasks when you complete or mark as not completed
- **Uses rich context**: Task title, description, persistent notes (START/END tags), and current notes
- The statement has two parts:
  1. **Selfish reason**: Personal benefit (e.g., "to look good", "to feel confident")
  2. **Selfless reason**: Benefit to others (e.g., "to inspire others", "to help my team")

### Context-Aware Generation
- **START/END Tags**: Extracts specific content from persistent notes between these tags
- **Persistent Notes**: Uses long-term guidelines and context
- **Current Notes**: Considers what you've already written
- **Task Description**: Incorporates task tags and details
- More context = more personalized and specific why statements

### Pin/Unpin Functionality
- Statements are pinned by default after generation
- Click the pin icon to unpin if you want to regenerate
- Click "Regenerate" button (appears when unpinned) to create a new statement
- Pinned statements won't be regenerated when you reopen the task

### Repeat Task Behavior
- When you complete a task or mark it as not completed, a new repeat task is created
- **The why statement and pin status are automatically copied to the new task**
- This ensures your motivation carries forward to future instances of the habit

### Example Why Statements

#### Basic Task (Title Only)
- **Workout**: "I'm working out to build strength and confidence in my body. So I can inspire others to prioritize their health and show them what's possible."

#### With Persistent Notes Context
**Task**: "Strength Training"
**Persistent Notes**:
```
START
Monday: Legs - Building lower body strength
Tuesday: Chest - Upper body power
Wednesday: Back - Posture and core
END
```
**Generated Why**: "I'm training to build functional strength and athletic performance. So I can stay active with my family and show them the importance of physical fitness."

#### With Rich Context
**Task**: "Learning to code"
**Description**: "Python, Web Development"
**Persistent Notes**: "Goal: Build a side project to help local businesses"
**Generated Why**: "I'm learning to code to unlock creative freedom and build solutions that matter. So I can empower local businesses with technology and create opportunities in my community."

## Setup

### 1. Add Your OpenAI API Key
1. Open `FocusFlowSwift/Config.xcconfig`
2. Replace the dummy key with your actual OpenAI API key:
   ```
   OPENAI_API_KEY = sk-proj-your-actual-api-key-here
   ```
3. Get your API key from: https://platform.openai.com/api-keys

### 2. Security
- The `Config.xcconfig` file is already added to `.gitignore`
- Your API key will NOT be committed to version control
- Keep your API key private and never share it

## Usage

### For Best Results: Add Context First

1. **Set Up Persistent Notes** (Highly Recommended):
   - Open your task's action view
   - Click "Persistent Notes"
   - Add your goals, guidelines, or context
   - Optionally use START/END tags to highlight key information:
     ```
     My fitness journey goals:
     START
     - Build strength for daily activities
     - Improve cardiovascular health
     - Set a good example for my kids
     END
     
     Current focus: Consistency over intensity
     ```

2. **Add Task Description**:
   - Use tags or keywords that describe your task
   - Example: "fitness, strength, health"

3. **Generate Why Statement**:
   - Open the task's action view
   - The why statement generates automatically using all available context
   - Wait a few seconds for the AI to create your personalized statement
   - **The statement is automatically pinned after generation**

4. **Automatic Propagation**:
   - When you complete the task or mark it as not completed, the why statement is copied to the new repeat task
   - Your motivation carries forward automatically

5. **To Regenerate**:
   - Click the pin icon to unpin
   - Click "Regenerate" button
   - The AI will create a new statement using current context

## Technical Details

### Model Updates
- Added `whyStatement: String?` to Task model
- Added `whyStatementPinned: Bool` to Task model (default: `true`)
- Backward compatible with existing tasks
- Why statements are copied to repeat tasks when completed/not completed

### API Integration
- Uses OpenAI GPT-3.5-turbo model
- Temperature set to 0.8 for creative responses
- Max 100 tokens per generation
- Analyzes: task title, description, persistent notes (with START/END tag extraction), and current notes
- Generates context-aware, personalized motivation

## Cost Considerations
- Each why statement generation costs approximately $0.0001-0.0002
- Statements are automatically pinned and copied to repeat tasks to minimize regeneration
- Consider setting usage limits in your OpenAI account

## Troubleshooting

### "Failed to generate why statement"
- Check your API key is correct in Config.xcconfig
- Verify you have credits in your OpenAI account
- Check your internet connection

### Statement not generating
- Make sure the statement is not already pinned
- Check the console for error messages
- Verify the OpenAI service is accessible
