# Persistent Notes Structure Guide

## Overview
Persistent notes are your task's long-term memory. They guide AI suggestions and why statements. Use special tags to organize active vs completed items.

---

## Basic Structure

```
[Optional: General context or goals]

START
[Active tasks, guidelines, or items to focus on]
END

=Completed
[Finished items - AI will ignore these]
End
```

---

## Special Tags Explained

### `START` and `END`
- Marks **active content** that AI should focus on
- Everything between these tags is used for suggestions
- Optional but recommended for clarity

### `=Completed` and `End`
- Marks **finished items** that AI should ignore
- Keeps your progress visible without cluttering suggestions
- AI will NOT suggest anything from this section

---

## Real-World Examples

### 1. Learning AI for Full Stack Development

```
Goal: Integrate AI capabilities into web applications
Current Level: Intermediate full stack developer
Tech Stack: React, Node.js, Python, PostgreSQL

START
Topics to Master:
- Neural Networks (fundamentals, backpropagation, gradient descent)
- Transformer Architecture (self-attention, GPT models)
- Model Context Protocol (MCP) for AI agent communication
- Prompt Engineering (temperature, top-p, top-k sampling)
- RAG (Retrieval-Augmented Generation) with vector databases
- LangChain for building AI-powered apps

Focus Areas:
- Hands-on implementation over theory
- Building production-ready features
- Understanding trade-offs and best practices

Resources:
- 3Blue1Brown Neural Networks series
- "Attention Is All You Need" paper
- OpenAI Cookbook
- LangChain documentation
END

=Completed
✓ Set up OpenAI API account
✓ Completed "Intro to Machine Learning" course
✓ Built simple chatbot with GPT-3.5
✓ Read "Deep Learning Basics" chapters 1-3
End

Notes:
- Prefer practical examples over mathematical proofs
- Focus on tools I can use immediately in projects
```

---

### 2. Strength Training Program

```
Current Stats:
- Squat: 225 lbs x 5
- Bench: 185 lbs x 5
- Deadlift: 315 lbs x 5
- Body Weight: 180 lbs

Goal: Build strength and muscle mass
Program: Push/Pull/Legs split

START
Weekly Schedule:
Monday: Legs (Squats, RDLs, Leg Press, Lunges, Calves)
Tuesday: Chest & Triceps (Bench, Incline Press, Dips, Flyes)
Wednesday: Back & Biceps (Deadlifts, Rows, Pull-ups, Curls)
Thursday: Rest or Light Cardio
Friday: Shoulders & Arms (OHP, Lateral Raises, Face Pulls)
Saturday: Legs (Front Squats, Leg Curls, Bulgarian Splits)
Sunday: Rest

Focus Points:
- Progressive overload: Add 5 lbs or 1 rep each week
- Form over weight - no ego lifting
- 3-4 sets per exercise
- 60-90 second rest for compounds, 45-60 for accessories
- Track all lifts in notebook

Nutrition:
- Protein: 180g daily (1g per lb body weight)
- Calories: 2800 (slight surplus for muscle gain)
- Pre-workout: Banana + coffee 30 min before
- Post-workout: Protein shake within 2 hours
END

=Completed
✓ Mastered proper squat form with coach
✓ Hit 225 lb squat milestone
✓ Completed 12-week beginner program
✓ Learned meal prep basics
✓ Established consistent gym routine (6 months)
End

Injuries/Limitations:
- Previous right shoulder issue (2023) - fully healed
- Avoid behind-neck exercises
```

---

### 3. Mobile App Development Project

```
Project: FitTrack - Fitness tracking iOS app
Timeline: 3 months to MVP
Tech Stack: SwiftUI, Firebase, Core Data

START
Sprint 1 (Current):
- User authentication (email/password, Google Sign-In)
- Profile management (photo, bio, stats)
- Settings screen (dark mode, notifications, biometric auth)

Sprint 2 (Next):
- Workout logging (exercises, sets, reps, weight)
- Exercise library with search and filters
- Progress tracking with charts

Sprint 3 (Future):
- Social features (friends, sharing workouts)
- AI workout suggestions
- Apple Health integration

Technical Priorities:
- MVVM architecture for testability
- Combine for reactive programming
- Async/await for networking
- Unit tests for business logic
- Accessibility compliance (VoiceOver, Dynamic Type)

Current Blockers:
- Need to learn Firebase Cloud Functions
- Decide on chart library (Charts vs SwiftUI Charts)
END

=Completed
✓ Set up Xcode project with SPM
✓ Designed app architecture (MVVM)
✓ Created Figma mockups for all screens
✓ Set up Firebase project
✓ Implemented basic navigation structure
✓ Created reusable UI components library
✓ Set up CI/CD with GitHub Actions
End

Resources:
- Paul Hudson's "Hacking with SwiftUI"
- Firebase documentation
- Apple Human Interface Guidelines
```

---

### 4. Learning Spanish

```
Goal: Conversational fluency for travel to Spain
Current Level: A2 (Elementary)
Study Time: 30 min daily

START
Focus Areas:
- Verb conjugations (present, preterite, imperfect)
- Common phrases for travel (ordering food, directions, hotels)
- Listening comprehension (podcasts, TV shows)
- Speaking practice (language exchange partners)

Weekly Plan:
Monday: Grammar (verb conjugations)
Tuesday: Vocabulary (50 new words with Anki)
Wednesday: Listening (Spanish podcast 20 min)
Thursday: Speaking (iTalki lesson or language exchange)
Friday: Reading (news articles or short stories)
Weekend: Review + watch Spanish TV show with subtitles

Resources:
- Duolingo (daily streak maintenance)
- "Practice Makes Perfect: Spanish Verb Tenses"
- Coffee Break Spanish podcast
- iTalki for conversation practice
- SpanishDict for quick lookups

Current Vocabulary: ~800 words
Target: 2000 words in 6 months
END

=Completed
✓ Completed A1 level course
✓ Learned present tense conjugations
✓ Memorized 100 most common words
✓ Finished "Spanish for Beginners" book
✓ Can introduce myself and have basic conversations
✓ Completed Duolingo Spanish tree (first pass)
End

Notes:
- Focus on practical conversation over perfect grammar
- Immersion is key - change phone language to Spanish
- Don't be afraid to make mistakes when speaking
```

---

### 5. Side Project - E-commerce Website

```
Project: Handmade Crafts Marketplace
Tech: Next.js, Stripe, PostgreSQL, Vercel
Launch Target: 2 months

START
Phase 1 - Core Features (Weeks 1-4):
- Product catalog with search and filters
- Shopping cart and checkout (Stripe integration)
- User accounts (NextAuth.js)
- Seller dashboard (add/edit products)
- Order management system

Phase 2 - Enhanced Features (Weeks 5-6):
- Product reviews and ratings
- Wishlist functionality
- Email notifications (order confirmations, shipping updates)
- Admin panel (user management, analytics)

Phase 3 - Polish (Weeks 7-8):
- SEO optimization (meta tags, sitemap, structured data)
- Performance optimization (image optimization, caching)
- Mobile responsiveness testing
- Security audit (OWASP top 10)
- Load testing

Technical Decisions:
- Use Prisma ORM for database
- Implement server-side rendering for SEO
- Use React Query for data fetching
- Implement rate limiting for API routes
- Use Cloudinary for image hosting

Marketing Plan:
- Launch on Product Hunt
- Share on Reddit (r/webdev, r/entrepreneur)
- Create demo video for YouTube
- Write blog post about building process
END

=Completed
✓ Set up Next.js project with TypeScript
✓ Designed database schema
✓ Created wireframes in Figma
✓ Set up Vercel deployment
✓ Implemented basic routing structure
✓ Integrated Tailwind CSS
✓ Set up PostgreSQL database on Railway
✓ Implemented authentication with NextAuth
End

Lessons Learned:
- Start with MVP, add features iteratively
- Test payment flow early and often
- Mobile-first design is crucial
```

---

## Tips for Writing Great Persistent Notes

### 1. Be Specific
❌ Bad: "Learn programming"
✅ Good: "Learn React hooks (useState, useEffect, useContext), state management with Redux, async operations with Redux Thunk"

### 2. Include Context
- Your current level/stats
- Your goals and timeline
- Resources you're using
- Constraints or limitations

### 3. Use Day-Specific Info
```
START
Monday: Focus on algorithms
Tuesday: System design practice
Wednesday: Mock interviews
Thursday: Review weak areas
Friday: Leetcode contest
END
```

### 4. Track Progress with =Completed
- Move finished items to =Completed section
- Keeps you motivated seeing progress
- AI won't suggest completed items

### 5. Add "Why" Context
```
Goal: Build a SaaS product to generate passive income
Why: Financial freedom and location independence
Timeline: Launch MVP in 3 months
```

### 6. Include Numbers and Metrics
- Current stats (weight lifted, words known, projects completed)
- Target metrics (goal weight, vocabulary size, revenue)
- Time allocations (30 min daily, 2 hours on weekends)

### 7. List Resources
- Specific books, courses, articles
- Tools and libraries you're using
- People or communities for help

---

## Template for Quick Start

```
[Task Name/Goal]
Current Status: [Where you are now]
Target: [Where you want to be]
Timeline: [When you want to achieve it]

START
Active Focus Areas:
- [Item 1 with specific details]
- [Item 2 with specific details]
- [Item 3 with specific details]

Schedule/Plan:
[Day-by-day or step-by-step breakdown]

Resources:
- [Resource 1]
- [Resource 2]

Notes:
[Any additional context, preferences, or constraints]
END

=Completed
✓ [Finished item 1]
✓ [Finished item 2]
End

[Any other notes or reflections]
```

---

## Common Mistakes to Avoid

### ❌ Too Vague
```
START
Learn stuff
Practice more
Get better
END
```

### ✅ Specific and Actionable
```
START
Master React Hooks:
- useState for local state management
- useEffect for side effects and API calls
- useContext for global state
- Custom hooks for reusable logic

Practice: Build 3 projects using only hooks (no class components)
END
```

### ❌ No Structure
```
I want to learn AI and machine learning and also do some coding and maybe read some books about it
```

### ✅ Well-Structured
```
Goal: Become proficient in machine learning

START
Learning Path:
1. Python fundamentals (NumPy, Pandas)
2. Statistics and linear algebra basics
3. Supervised learning (regression, classification)
4. Neural networks and deep learning
5. Real-world project implementation

Current Focus: Step 2 - Statistics
END
```

---

## Summary

**Good persistent notes have:**
- Clear structure with START/END tags
- Specific, actionable items
- Context about your level and goals
- Completed section (=Completed/End) for tracking progress
- Resources and references
- Day-specific or phase-specific breakdowns
- Numbers and metrics where relevant

**The AI will:**
- Focus on content between START and END (or =Completed)
- Ignore everything in =Completed section
- Use your context to generate personalized suggestions
- Provide specific, technical recommendations based on your notes
