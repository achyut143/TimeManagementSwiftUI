# Creating Workouts with AI

Paste or type a description of one or more workouts, and the app builds them for you. You check each one before it is saved.

## Where to find it

1. On the home screen (Tasks), tap the red running-figure icon next to the Daily Notes icon.
2. On the Workouts screen, tap **+** and choose **Create with AI**.
3. Paste or type your description. The **Paste** button at the bottom drops in whatever you have copied.
4. Tap **Create**.

## What happens next

- **One workout:** it opens straight in the editor. Check it, add pictures if you want, and tap **Save**.
- **Several workouts:** a **Review workouts** list shows each one's name, type and summary.
  - Tap the circle next to a workout to include or skip it.
  - Tap a workout to open it in the editor, change it, and save it on its own. It then shows as **Saved**.
  - **Save all (N)** saves every ticked workout that is not saved yet.

Nothing is saved until you tap Save or Save all.

## Let another AI write it for you

On the Create with AI screen, tap **Copy format for AI** (bottom left). It copies a set of instructions explaining this app's workout format.

1. Paste the instructions into ChatGPT, Claude or another AI chat.
2. Add your workout plan after them, e.g. a program name, a worksheet, or a rough list.
3. Copy the AI's reply and paste it into Create with AI.

## How to write the description

Give each workout a name and its own short paragraph. Leave a blank line between workouts so the AI can tell them apart. The wording does not need to be exact.

### Tabata (timed intervals)

Include:

| What | Example |
| --- | --- |
| Name | Insanity warm up 1 |
| Prepare time | 10s prepare |
| Work time | 40s work |
| Rest time | no rest, or 10s rest |
| Rounds (Tabatas) | 3 rounds |
| Rest between rounds | 30s between rounds |
| Exercises, in order | Jog, jumping jacks, heismans… |

Each exercise becomes one cycle, so 7 exercises means 7 cycles per round.

If you leave something out, these defaults are used:

| Setting | Default |
| --- | --- |
| Prepare | 10 seconds |
| Work | 20 seconds |
| Rest | 10 seconds |
| Rounds | 1 |
| Rest between rounds | none |

### One Tabata with several parts

A Tabata can have several **parts** that run back to back as one workout, e.g. a warm up followed by circuits. Each part has its own prepare, work and rest times, cycles, rounds and exercises.

There are three ways to make one:

1. **Write it as one Tabata.** Put "(one Tabata, N parts)" after the name, start each part with "Part <name>:", and keep everything in one paragraph:

   ```
   Insanity Max 30 Cardio Challenge (one Tabata, 3 parts).
   Part Warm up: 10s prepare, 30s work, no rest, 2 rounds.
   Chest open jack, jack uppercut, 1-2-3 knee, cross jack, high knee jab.
   Part Circuit 1: 30s prepare, 30s work, no rest, 3 rounds.
   Squat kick, pike-up spider, 10 and 2.
   Part Circuit 2: 30s prepare, 30s work, no rest, 3 rounds.
   Medicine ball twist, plank jack plus in and out, 4 jab plus 4 high knee.
   ```

2. **Combine on the review screen.** If the AI makes separate Tabatas, tap **Combine N Tabatas into one**. It merges every ticked Tabata, in list order. The shared start of their names becomes the workout name, and the rest becomes each part's name (e.g. "warm up", "circuit 1"). Untick any you want to keep separate first.

3. **In the editor.** Open a Tabata and tap **Add part** for a blank part, or **Add a saved Tabata as a part** to copy in one you already saved. Each part's ⋯ menu can move, duplicate or delete it.

A part's prepare time works as the break before it. While running, the screen shows "PART 2 OF 6 · circuit 1", cycle and round counts are per part, and the voice announces each new part.

### Rep workout (weight training)

Include:

| What | Example |
| --- | --- |
| Name | Upper body A |
| Sets and repeats | Set 1 × 3 |
| Exercise, reps, weight | bench press 10 reps 90 lb |
| Rest between sets (optional) | 90s rest between sets |
| Notes (optional) | slow on the way down |

## Example: three workouts in one message

```
Insanity warm up 1: 10s prepare, 40s work, no rest, 3 rounds, 30s rest between rounds.
Jog, jumping jacks, heismans, 1-2-3, butt kicks, high knees, mummy kicks.

Core finisher: 20s work, 10s rest, 8 rounds, no prepare.
Plank, mountain climbers.

Upper body A, 90s rest between sets.
Set 1 × 3: bench press 10 reps 90 lb, bent-over row 10 reps 65 lb.
Set 2 × 2: shoulder press 12 reps 35 lb, bicep curl 12 reps 25 lb (slow on the way down).
```

This creates two Tabatas and one rep workout.

## Tips

- **Times** can be written as `40s`, `0:40`, or `40 seconds`. `1:30` means 90 seconds.
- **Unclear times:** if the text contradicts itself, e.g. "0:30 sec (40 seconds)", the number in brackets or in words is used.
- **Rep ranges** like "8–12 reps" are saved as 8, with the full range kept in the exercise note.
- **Weights** without a unit are in pounds (lb), the default. You can switch to kg under the gear icon → Weight unit; weights written in the other unit are converted.
- **Messy text is fine.** You can copy a workout straight from a website, a video description, or a note.
- **Pictures** can't be added by AI. Add them in the editor afterwards by tapping the photo box on a cycle or exercise.
- **Always check before saving**, especially cycle counts and weights.

## Long programs

You can paste a whole program, e.g. 5 or more long workouts. The app splits the text at blank lines and reads the pieces in parallel, so keep a blank line between workouts. Very large pastes take longer; pasting one batch (about 5 workouts) at a time works best.

## If something goes wrong

| Message | What to do |
| --- | --- |
| Couldn't read a workout from that description | Add more detail, such as times, rounds or reps, and try again. |
| The AI didn't send anything back | Check your internet connection and try again. |
| No OpenAI API key is set up | The app's OpenAI key is missing from `Config.xcconfig`. |
| A workout is missing from the review list | That one couldn't be read. Create it again on its own with more detail. |
| "Some parts of your text couldn't be read" | Check which workouts are missing and paste those again on their own. |
| That description is too long to read at once | Put a blank line between workouts, or paste fewer at a time. |
