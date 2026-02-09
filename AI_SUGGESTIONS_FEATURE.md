# AI Task Suggestions Feature

## Overview
Get intelligent, context-aware suggestions for your tasks using AI. The system analyzes your task title, persistent notes, current day, and existing notes to generate specific, actionable recommendations.

## Features

### Deep, Specific Recommendations
- Goes beyond surface-level advice to provide concrete, actionable details
- Includes specific technologies, frameworks, concepts, and techniques
- Provides WHY each item matters and HOW it connects to bigger goals
- Includes time estimates and resource suggestions

### Smart Context Analysis
The AI considers multiple factors to generate relevant suggestions:
1. **Task Title**: Understanding what the task is about
2. **Persistent Notes**: Long-term guidelines and instructions (especially content between START/END tags)
3. **Day of Week**: Tailors suggestions based on the current day
4. **Current Date**: Provides time-relevant recommendations
5. **Existing Notes**: Builds upon what you've already written

### Enhanced Output Quality
- **Specific Concepts**: Instead of "learn AI", get "study Transformer architecture, self-attention mechanism"
- **Concrete Tools**: Actual library names, frameworks, and technologies
- **Detailed Steps**: Break down complex tasks into implementable sub-tasks
- **Resource Links**: Suggestions for specific articles, documentation, or tools
- **Time Estimates**: Realistic time allocations for each item
- **Context & Why**: Explains why each item matters and how it fits the bigger picture

### START/END Tags (Optional)
Use special tags in your **Persistent Notes** to define structured guidelines:

```
START
Monday: Legs - Squats, Lunges, Leg Press
Tuesday: Chest - Bench Press, Push-ups, Dumbbell Flyes
Wednesday: Back - Pull-ups, Rows, Deadlifts
Thursday: Shoulders - Overhead Press, Lateral Raises
Friday: Arms - Bicep Curls, Tricep Extensions
END
```

The AI will extract and prioritize content between these tags when generating suggestions.

## Usage

### Step 1: Set Up Persistent Notes (Optional but Recommended)
1. Open your task's action view
2. Click "Persistent Notes"
3. Add your guidelines, optionally using START/END tags:
   ```
   Workout Plan:
   START
   Monday: Legs (3 sets each)
   - Squats
   - Lunges
   - Leg Press
   - Calf Raises
   
   Tuesday: Chest & Triceps (3 sets each)
   - Bench Press
   - Incline Dumbbell Press
   - Cable Flyes
   - Tricep Dips
   END
   
   Always warm up for 5 minutes before starting.
   ```

### Step 2: Get AI Suggestions
1. Open your task's action view
2. Click "Notes"
3. Click the "Get AI Suggestions" button (sparkles icon)
4. Wait a few seconds for the AI to generate suggestions
5. The suggestions will be appended to your notes
6. Edit or save as needed

## Example Use Cases

### 1. Learning AI for Full Stack Development
**Task**: "Learn AI for Full Stack Development"

**Persistent Notes**:
```
START
Goal: Integrate AI into web applications
Current level: Intermediate full stack developer
Tech stack: React, Node.js, Python
END
```

**AI Suggestion (Enhanced)**:
```
--- AI Suggestions ---
Comprehensive AI Learning Path for Full Stack Developers:

1. Foundation - Neural Networks Fundamentals (60 min)
   CORE CONCEPTS:
   - Study: Perceptron model and activation functions (ReLU, Sigmoid, Tanh)
   - Understand: Forward propagation and backpropagation algorithm
   - Learn: Gradient descent optimization (SGD, Adam, RMSprop)
   - Practice: Build a simple neural network from scratch in NumPy
   WHY: Understanding the math helps you debug ML models and choose right architectures

2. Modern AI Architecture - Transformers (50 min)
   KEY TOPICS:
   - Study: Self-attention mechanism (Query, Key, Value matrices)
   - Read: "Attention Is All You Need" paper (sections 3.1-3.2)
   - Understand: How GPT models generate text token by token
   - Explore: Hugging Face Transformers library basics
   WHY: Transformers power GPT, BERT, and most modern AI - essential for integration

3. AI Integration Patterns (45 min)
   PRACTICAL IMPLEMENTATION:
   - Learn: Model Context Protocol (MCP) for AI agent communication
   - Study: Sampling strategies (temperature, top-p, top-k) for text generation
   - Understand: Prompt engineering best practices
   - Explore: LangChain for building AI-powered applications
   WHY: These patterns let you integrate AI APIs into your full stack apps

4. Hands-On Project Setup (45 min)
   BUILD:
   - Set up OpenAI API in Node.js backend
   - Create React component for AI chat interface
   - Implement streaming responses with Server-Sent Events
   - Add error handling and rate limiting
   - Store conversation history in MongoDB
   WHY: Practical experience solidifies theoretical knowledge

5. Advanced Topics - RAG & Vector Databases (40 min)
   CONCEPTS:
   - Study: Retrieval-Augmented Generation (RAG) architecture
   - Learn: Vector embeddings and semantic search
   - Explore: Pinecone or Weaviate for vector storage
   - Understand: Chunking strategies for document processing
   WHY: RAG enables AI to work with your custom data - key for real applications

RESOURCES:
- 3Blue1Brown: Neural Networks series (YouTube)
- Fast.ai: Practical Deep Learning course
- OpenAI Cookbook: Best practices and examples
- LangChain documentation: Integration patterns

TOTAL TIME: 4 hours
NEXT STEPS: Build a simple AI-powered feature in your existing project
```

### 2. Workout Planning
**Task**: "Strength Training"

**Persistent Notes**:
```
START
Monday: Legs
Tuesday: Chest
Wednesday: Back
Thursday: Shoulders
Friday: Arms
END
```

**AI Suggestion (on Monday)**:
```
--- AI Suggestions ---
Today's Leg Day Workout:

1. Warm-up (5 minutes)
   - Light cardio or dynamic stretching

2. Main Exercises:
   - Barbell Squats: 3 sets x 8-10 reps
   - Romanian Deadlifts: 3 sets x 10-12 reps
   - Leg Press: 3 sets x 12-15 reps
   - Walking Lunges: 3 sets x 10 reps per leg
   - Calf Raises: 3 sets x 15-20 reps

3. Cool-down (5 minutes)
   - Static stretching focusing on quads, hamstrings, and calves

Rest 60-90 seconds between sets. Focus on proper form.
```

### 2. Study Planning
**Task**: "Study Computer Science"

**Persistent Notes**:
```
START
Topics to cover:
- Data Structures
- Algorithms
- System Design
- Database Design
END

Focus on practical implementation, not just theory.
```

**AI Suggestion (Enhanced)**:
```
--- AI Suggestions ---
Deep Dive Learning Plan for Today:

1. Data Structures - Hash Tables (45 min)
   - Study collision resolution: Chaining vs Open Addressing
   - Implement a hash table from scratch in your preferred language
   - Understand load factor and when to resize
   - Practice: LeetCode #1 (Two Sum) using hash maps
   WHY: Hash tables are O(1) lookup - critical for optimizing algorithms

2. Algorithms - Binary Search Variations (40 min)
   - Master binary search on rotated sorted arrays
   - Study: Finding peak element in array
   - Implement: Search in 2D matrix (treat as 1D sorted array)
   - Key insight: Recognize when problem space can be halved
   WHY: Binary search pattern appears in 20% of interview questions

3. System Design - Caching Strategies (35 min)
   - Study: LRU Cache implementation (Doubly Linked List + HashMap)
   - Understand: Cache invalidation strategies
   - Read: Redis architecture and use cases
   - Practice: Design a simple cache with TTL
   WHY: Caching is fundamental to scalable system design

Resources:
- "Designing Data-Intensive Applications" (Chapter 3)
- Visualgo.net for algorithm visualization
- System Design Primer on GitHub

Total: 2 hours of focused, deep learning
```

### 3. Project Work
**Task**: "Mobile App Development"

**Persistent Notes**:
```
START
Current sprint goals:
- User authentication
- Profile management
- Settings screen
END
```

**AI Suggestion (Enhanced)**:
```
--- AI Suggestions ---
Detailed Implementation Plan:

1. User Authentication - Firebase Integration (90 min)
   SETUP:
   - Install Firebase SDK via CocoaPods/SPM
   - Configure GoogleService-Info.plist
   - Initialize Firebase in AppDelegate
   
   IMPLEMENTATION:
   - Create AuthenticationManager singleton
   - Implement email/password sign up with validation
   - Add Google Sign-In (OAuth 2.0 flow)
   - Handle auth state changes with Combine publishers
   - Store auth tokens securely in Keychain
   WHY: Proper auth is security foundation - never store passwords in UserDefaults

2. Profile Management - MVVM Architecture (60 min)
   DATA MODEL:
   - Create User model (Codable) with: id, name, email, photoURL, bio
   - Design ProfileViewModel with @Published properties
   - Implement image picker for profile photo
   
   NETWORKING:
   - POST /api/users/{id}/profile endpoint
   - Use URLSession with async/await
   - Handle multipart/form-data for image upload
   - Add loading states and error handling
   WHY: MVVM separates concerns - easier testing and maintenance

3. Settings Screen - UserDefaults + SwiftUI (45 min)
   FEATURES:
   - Toggle: Dark mode, notifications, biometric auth
   - Picker: Language preference
   - Button: Logout, delete account
   
   IMPLEMENTATION:
   - Use @AppStorage for UserDefaults binding
   - Create SettingsViewModel for business logic
   - Add confirmation alerts for destructive actions
   - Implement biometric auth with LocalAuthentication framework
   WHY: Settings affect app-wide behavior - needs centralized state management

4. Testing & Polish (25 min)
   - Write unit tests for AuthenticationManager
   - Test edge cases: network failure, invalid credentials
   - Add loading indicators and error messages
   - Test on different screen sizes

TOTAL: 3.5 hours
PRIORITY: Auth → Profile → Settings (in order)
```

## Features

### Smart Context Extraction
- Automatically finds and uses content between START/END tags
- Falls back to using all persistent notes if tags aren't present
- Considers the current day of the week for day-specific suggestions

### Flexible Integration
- Suggestions are appended to existing notes (doesn't overwrite)
- Can generate multiple times with different contexts
- Edit suggestions before saving

### Day-Aware Recommendations
- Generates different suggestions based on the day of the week
- Perfect for weekly workout routines, study schedules, or rotating tasks

## Tips for Best Results

1. **Be Specific in Persistent Notes**: The more detailed your guidelines, the better the suggestions
   - Instead of: "Learn programming"
   - Use: "Learn React hooks, state management with Redux, async operations with Redux Thunk"

2. **Use START/END Tags**: Helps the AI focus on the most relevant information
   ```
   START
   Current focus: Neural networks
   Specific topics: Backpropagation, gradient descent, activation functions
   Goal: Build image classifier
   END
   ```

3. **Include Day-Specific Info**: Mention days of the week in your persistent notes for day-aware suggestions
   - "Monday: Focus on algorithms, Tuesday: System design practice"

4. **Iterate**: Generate suggestions, review them, and refine your persistent notes for better future suggestions

5. **Combine with Task Description**: Use the task description field for additional context
   - Task: "Learn AI"
   - Description: "machine learning, neural networks, deep learning, PyTorch"

6. **Add Your Current Level**: Mention your skill level for appropriately challenging suggestions
   - "Intermediate Python developer learning advanced concepts"

7. **State Your Goals**: Include what you want to achieve
   - "Goal: Build a recommendation system for e-commerce site"

## Technical Details

### API Integration
- Uses OpenAI GPT-3.5-turbo model
- Temperature: 0.7 (balanced creativity and consistency)
- Max tokens: 500 (detailed, comprehensive suggestions)
- Enhanced prompt engineering for deep, specific recommendations
- Considers task date and day of week

### Cost Considerations
- Each suggestion generation costs approximately $0.0003-0.0005 (increased due to longer responses)
- Suggestions are not automatically saved (you control when to save)
- Higher quality = slightly higher cost, but more valuable output
- Consider setting usage limits in your OpenAI account

## Troubleshooting

### "Failed to generate suggestions"
- Check your API key in Config.xcconfig
- Verify you have credits in your OpenAI account
- Check your internet connection

### Suggestions not relevant
- Add more detail to your persistent notes
- Use START/END tags to focus the AI
- Include day-specific information in your guidelines
- Make sure your task title is descriptive

### Suggestions too generic
- Be more specific in persistent notes
- Include numbers (sets, reps, time durations)
- Add context about your goals or preferences
