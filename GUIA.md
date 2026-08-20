# Reading guide

This file is for studying the code. The source has no comments: what it does is in the names, and the why is here.

## Reading order

Read in this order. Each step only uses what came before it.

**1. `Model/GoalMetric.swift`**

The simplest type in the package, an enum. Three things to notice. The raw value is stable, and there's a test pinning the list because those strings reach your backend. The `#if canImport(HealthKit)` block is the mechanism that lets everything run on CI. And `readsWorkouts` is the one piece of business logic living inside an enum.

**2. `Model/GoalDefinition.swift`**

Four fields and nothing else. Notice what's missing: color, user, group, ordering, and any notion of a manual goal. All of that belongs to the app. At the bottom, `metrics` on a `Collection` extension, which is what enforces "only ask for what the group actually uses".

**3. `Model/GoalProgress.swift`**

An init that computes instead of accepting finished values. Work out why `fraction` isn't a parameter: the type doesn't trust its caller, it derives. Read the three defenses (zero target, negative value, `NaN`), then open `Tests/GoalSourceTests/GoalProgressTests.swift` and find each one tested.

**4. `Model/DailySnapshot.swift`**

Why the date and the progress values are glued into one type. Two reasons, both with tests. At midnight the stream emits zeros, and without the date you can't tell a day rollover from a failed read. And the cache needs to know whether what it stored is from today or yesterday.

**5. `Persistence/SnapshotStoring.swift`**

The first protocol in the package. This is where the core idea starts: anything that talks to the outside world comes in through a protocol. Two implementations in the same file, one of them three lines long.

**6. `Queries/HealthStoreProviding.swift`**

The most important file for understanding the architecture. Notice that no HealthKit type appears in any signature. Ask yourself why before moving on. The answer is item 2 under "Five decisions" below.

**7. `Store/HealthKitGoalStore.swift`**

The actor. Read top to bottom until the session plumbing, stop, and only then come back for `runSession`. It's the hardest part of the package and it doesn't make sense before the rest.

**8. `Store/GoalsMonitor.swift`**

The main actor shell. Short, with no logic of its own; everything here is delegation. Good for seeing what `@Observable` actually solves.

**9. `Queries/LiveHealthStore.swift`**

Save this for last. It's the only file with no tests, and the only one that needs a real device.

## Swift concepts in here, and where to find them

| Concept | Where | What to look at |
|---|---|---|
| `actor` | `HealthKitGoalStore` | why it replaces a lock |
| `Sendable` | everywhere | what the compiler is guaranteeing |
| `@unchecked Sendable` | `HealthObservationToken`, `UncheckedBox` | when lying to the compiler is legitimate |
| `AsyncStream` | `liveSnapshots` | bridging callbacks to `for await` |
| `withCheckedThrowingContinuation` | `LiveHealthStore.sum` | bridging callbacks to `async` |
| `withThrowingTaskGroup` | `snapshot(for:on:)` | parallelism, and why it reorders at the end |
| `Task` cancellation | `runSession`, `GoalsMonitor.start` | how SwiftUI shuts it all down for you |
| `@Observable` | `GoalsMonitor` | what replaced `ObservableObject` |
| `#if canImport` | `GoalMetric`, `LiveHealthStore` | conditional compilation per platform |
| protocol injection | `HealthStoreProviding`, `SnapshotStoring` | why the tests can exist at all |

## Five decisions that explain the rest

1. **Errors are only for "can't continue".** An empty read becomes data (`ProgressUnavailableReason`), not an exception, because the other rings still have to draw. See `HealthKitGoalError`.
2. **No HealthKit type crosses `HealthStoreProviding`.** Units on one side, calendar on the other. It's what lets 71 tests run without HealthKit.
3. **The package knows exactly one person, and only what a sensor produced.** No `userId`, no group, no manual goals. If it doesn't come from a sensor, it doesn't come in here.
4. **The cache is local to the device.** App Groups connect an app to its widgets, not an iPhone to a Watch.
5. **HealthKit never reveals read authorization.** Half of `AuthorizationSummary` comes from Apple and half from what the package wrote down. See `MetricAuthorization`.

## Exercises

You learn more by breaking things than by reading. The tests will tell you exactly what broke.

1. In `GoalProgress.init`, replace `min(1, ...)` with `sanitizedValue / sanitizedTarget`. Run `swift test`. Which test catches it, and what would happen on screen without it?
2. In `HealthKitGoalStore.snapshot`, delete the `.sorted { $0.0 < $1.0 }`. The test may pass a few times before it fails. Why?
3. In `runSession`, delete the `token?.cancel()` at the end. Which test catches it, and what would the symptom be in a real app after entering and leaving the screen twenty times?
4. In `progress(for:on:in:)`, swap the first two `guard` statements. Which test catches it, and what wrong information would the user see?
5. Add a new metric to `GoalMetric` and change nothing else. How many compile errors do you get, and why is that a good thing?

## Running it

```
swift build          # builds for macOS, without HealthKit
swift test           # 71 tests, none of them need a device
xcodebuild -scheme GoalSource -destination 'generic/platform=iOS' build
xcodebuild -scheme GoalSource -destination 'generic/platform=watchOS' build
```

Those last two are the only ones that actually compile `LiveHealthStore`.
