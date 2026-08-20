# GoalSource

A HealthKit SDK. You hand it the goals you want tracked, it gives you today's progress for each one, and it keeps that fresh on its own.

It knows nothing about your backend, your UI, your colors, your theme, your groups or your users. Goals the user ticks by hand ("read 20 pages") are out of scope too, since they have nothing to do with HealthKit and your app already owns that state.

- Swift 5.10, iOS 17+ and watchOS 10+, no external dependencies
- Fully async/await, one actor, everything `Sendable`
- HealthKit is imported conditionally, so the package builds and its tests run on CI machines that don't have it

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/tiagocomth/GoalSource.git", from: "1.0.0")
]
```

```swift
.target(name: "App", dependencies: ["GoalSource"])
```

In Xcode: **File › Add Package Dependencies…**, paste `https://github.com/tiagocomth/GoalSource`, and pick *Up to Next Major* from `1.0.0`.

## Setting up your app

### Info.plist

On both targets, iPhone and Watch:

```xml
<key>NSHealthShareUsageDescription</key>
<string>To track your activity goals alongside your group.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>To log the water you drank toward your hydration goal.</string>
```

You only need `NSHealthUpdateUsageDescription` if a group can have a water goal, but the system wants the key before your app is in any position to know that. Ship both.

### Capabilities

| Capability | Where | Why |
|---|---|---|
| HealthKit | iPhone and Watch | any read at all |
| HealthKit › Background Delivery | iPhone only | `enablesBackgroundDelivery: true` |
| App Groups | iPhone and Watch | sharing the cache with widgets and complications |

App Groups work **within a single device**: they connect your app to its extensions. They do not span an iPhone and its Apple Watch. Since watchOS 2 the watch app runs on the watch with its own container, so each one keeps its own cache. Without an App Group the package still works, your widget just won't see the last snapshot.

The two devices can even use different identifiers. Using the same one is convenient, not required.

## Usage

Create one instance somewhere you can reach it:

```swift
import GoalSource

enum Goals {
    static let store = HealthKitGoalStore(
        configuration: .appGroup("group.com.example.goalsource")
    )
}
```

Goals come from your backend. The shortcuts save you from spelling out `metric:` every time:

```swift
let goals = [
    GoalDefinition.water(2, id: remote[0].id),
    GoalDefinition.steps(10_000, id: remote[1].id),
    GoalDefinition.running(kilometers: 5, id: remote[2].id)
]
```

Pass only the tracked goals. Manual ones are your app's business.

`id` is an opaque `String`. Pass whatever your backend already uses, no conversion needed. It comes back on `GoalProgress.goalID` so you can match answers to questions.

On screen, use `GoalsMonitor`. It's `@MainActor @Observable`, so your view body reads plain properties with no `await` in sight:

```swift
struct MyPartView: View {
    @State private var monitor = GoalsMonitor(goals: goals, store: Goals.store)

    var body: some View {
        VStack {
            ForEach(monitor.goals) { goal in
                GoalRing(fraction: monitor.fraction(for: goal))
            }
        }
        .task { await monitor.start() }
    }
}
```

`start()` runs until the surrounding task is cancelled, which is exactly what SwiftUI does when the view goes away. The HealthKit queries unregister themselves.

If you'd rather talk to the actor directly, everything is still there:

```swift
let snapshot = try await Goals.store.snapshot(for: goals, on: .now)
try await Goals.store.log(0.25, for: .water, at: .now)
```

`DailySnapshot` is the package's answer: a date plus that day's progress, glued together. It's `Codable` and carries nothing from HealthKit, but don't assume it's your storage format. If your backend keeps one row per goal, the snapshot is input to the write, and the translation belongs in your sync layer, which is also where it meets your manual goals.

To decide which day you're publishing under, use `await Goals.store.dayKey(for: date)`. It returns the same `yyyy-MM-dd` the package uses to read HealthKit. Rolling your own puts a participant in another time zone writing to a different day than the one you read.

### The "no Health access" state

A tracked goal never fails for lack of permission. It comes back at zero with an `unavailableReason`, and your UI decides what to show:

```swift
switch progress.unavailableReason {
case nil:                          RingView(fraction: progress.fraction)
case .noSamples:                   RingView(fraction: 0)          // a real zero, or a denied read
case .authorizationNotRequested:   AskForHealthAccessView()
case .authorizationDenied:         OpenHealthSettingsView()
case .metricUnavailableOnDevice:   UnsupportedMetricView()
}
```

## SwiftUI example: four live rings

Colors come from your theme. The package doesn't know about them.

```swift
import SwiftUI
import GoalSource

struct MyPartView: View {
    @State private var monitor: GoalsMonitor
    let palette: [String: Color]

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                ForEach(Array(monitor.goals.enumerated()), id: \.element.id) { index, goal in
                    GoalRing(
                        fraction: monitor.fraction(for: goal),
                        color: palette[goal.id] ?? .accentColor,
                        lineWidth: 18
                    )
                    .padding(CGFloat(index) * 24)
                }
            }
            .frame(width: 240, height: 240)
            .animation(.snappy, value: monitor.snapshot)

            ForEach(monitor.goals) { goal in
                GoalRow(
                    goal: goal,
                    progress: monitor.progress(for: goal),
                    needsAccess: monitor.needsHealthAccess(for: goal),
                    color: palette[goal.id] ?? .accentColor
                )
            }
        }
        .padding()
        .task { await monitor.start() }
    }
}

struct GoalRing: View {
    let fraction: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct GoalRow: View {
    let goal: GoalDefinition
    let progress: GoalProgress?
    let needsAccess: Bool
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(goal.title)
            Spacer()
            if needsAccess {
                Image(systemName: "heart.slash").foregroundStyle(.secondary)
            } else {
                Text(progress?.fraction ?? 0, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

### Previews and the simulator

The simulator has no Health app, so every real read comes back empty. To get numbers on screen in a preview, or while running on a simulator:

```swift
#Preview {
    MyPartView(
        monitor: .preview(goals: goals, totals: [.stepCount: 7_500, .water: 1.4]),
        palette: [:]
    )
}
```

`GoalsMonitor.preview` wires up a `StubHealthStore` and an in-memory cache. No HealthKit, no disk. `HealthKitGoalStore.preview(totals:)` does the same if you're not using the monitor.

## watchOS

The same target builds on the Watch, with the same API:

```swift
let fractions = try await store.todayFractions(for: goals)   // [String: Double], keyed by goal id
```

watchOS has its own HealthKit store, already holding whatever the watch's sensors recorded. The Watch doesn't need to ask the iPhone for anything to draw its rings.

What changes:

- background delivery is ignored, since the API doesn't exist on watchOS, and the stream still works in the foreground
- creating goals and settings stay iPhone-only, which the package doesn't enforce; your app just doesn't offer them there

### What crosses between devices

| | How it reaches the other side |
|---|---|
| Tracked goal (HealthKit) | the system already mirrors the watch's samples to the iPhone, no code from you |
| Manual goal (checkmark) | out of scope here, it's app state and your app syncs it |

Watch to iPhone mirroring isn't instant either. It depends on the devices talking to each other and takes anywhere from seconds to minutes, so the number on the watch can run ahead of the phone for a while. That's the system's behavior, not the package's.

## Tests

```
swift test
```

Runs on any Mac, no simulator and no HealthKit. The actor depends on the `HealthStoreProviding` protocol, and the test target injects a `MockHealthStore`. The 71 assertions cover fraction math (clamping, zero targets, `NaN`), day and time zone boundaries including a daylight saving day, partial authorization, stream debounce, the day rollover, cancelling without leaking an observer, and the cache persisting and restoring. `GoalsMonitor` has its own: reading safely before the first snapshot, an optional prompt, write errors turning into `lastError`, and swapping goals clearing the stale snapshot.

The tests that need a real `HKUnit` sit behind `#if canImport(HealthKit)` and only run when you build for iOS or watchOS:

```
xcodebuild -scheme GoalSource -destination 'generic/platform=iOS' build
xcodebuild -scheme GoalSource -destination 'generic/platform=watchOS' build
```

## Architecture

```
Model/         GoalMetric, GoalDefinition (+ shortcuts), GoalProgress, DailySnapshot,
               AuthorizationSummary, errors
Store/         HealthKitGoalStore (the actor), Configuration, GoalsMonitor (@Observable)
Queries/       HealthStoreProviding, LiveHealthStore (HKHealthStore), StubHealthStore,
               HealthObservationToken
Persistence/   SnapshotStoring, FileSnapshotStore, InMemorySnapshotStore, PersistedState
Support/       Logger, day and calendar math
```

There are two doors into the same thing. `HealthKitGoalStore` is the actor, and that's where the logic lives. `GoalsMonitor` is a `@MainActor` shell on top of it so SwiftUI doesn't have to deal with `await` inside a view body. Use the monitor on screen and the actor everywhere else. Neither one holds anything back from you.

The boundary that matters is `HealthStoreProviding`: no HealthKit type crosses it. Units stay inside `LiveHealthStore`, day math stays inside `HealthKitGoalStore`. That's what makes the whole actor testable on a machine with no HealthKit at all.

No `print` anywhere. Everything goes through `Logger` under the `com.goalsource` subsystem, in the `model`, `store`, `queries` and `persistence` categories.

## Limitations and decisions

**Running is not the same as walking.** HealthKit has no "distance while running" quantity type: `distanceWalkingRunning` counts your whole day, trip to the bakery included. So `runningDistance` sums the distance recorded *inside running workouts* (`HKSampleQuery` over `predicateForWorkouts(with: .running)`), while `walkingDistance` uses the day's total. Both point at the same `hkQuantityTypeIdentifier` because that's the type needing permission; `GoalMetric.readsWorkouts` is what separates them. The consequence is that a running goal only moves if there's a recorded workout. Running without starting one doesn't count, and for a running goal that's the correct behavior.

**Swimming uses the quantity type, not workouts.** `distanceSwimming` is only ever produced by swim workouts, so the simple query is already accurate. A second code path wouldn't buy anything.

**Only water is writable.** Steps, distance and energy come from sensors, and writing them by hand would corrupt the user's Health data. Anything but water throws `writeNotPermitted`.

**Logging workouts is out.** A workout is an `HKWorkout`, not an `HKQuantitySample`, so it doesn't fit the `log(_ amount: Double, for metric:)` signature. Recording one needs `HKWorkoutBuilder`, a session, an activity type, a duration and energy. That's a whole surface of its own, and inventing it now wasn't the right call. If the product needs it, it arrives as `startWorkout` and `endWorkout` in a separate file without disturbing any of this.

**No `HKAnchoredObjectQuery`.** The ring needs the day's total, not the new samples. `HKObserverQuery` says something changed and the package recomputes the day with `HKStatisticsQuery`. An anchor would only help if the package processed samples one by one, which it doesn't. If incremental history ever matters, that's when to revisit.

**No `HKStatisticsCollectionQuery`.** That one exists for multi-day series. Here the window is always a single day, and a plain statistics query is cheaper.

**The debounce is trailing, with no ceiling.** A continuous burst of samples postpones the emission for as long as it lasts. In practice HealthKit batches and the burst ends; if a pathological case ever shows up, the fix is a max wait.

**A denied read is indistinguishable from an empty day.** That's deliberate on Apple's side: an app must not be able to discover that a user hid their data. So `MetricAuthorization` only reports `.denied` and `.authorized` for water, the one writable metric, and for everything else it reports `.notRequested` or `.requested` based on what the package recorded having asked for. `ProgressUnavailableReason.noSamples` means "zero or no access", and your UI should pick wording that works for both.

**A zero target doesn't complete a goal.** `target <= 0` yields a fraction of 0 and `isComplete == false`, with a warning in the log. A malformed goal showing up as a full ring hides the bug from whoever created it.

**`isCumulative` is `true` for all seven metrics.** The flag exists because the query layer picks `.cumulativeSum` based on it. It only turns `false` the day weight or heart rate shows up.

**`.macOS(.v14)` is in the platform list.** It isn't a shipping platform. It's there so `swift test` runs on a CI machine without Xcode; without a macOS minimum, even `Logger` fails to compile.

**The package syncs nothing.** It produces `DailySnapshot` and stops. Publishing, receiving your teammates' progress, sending nudges and resolving conflicts all belong to your sync layer.

**It doesn't sync between iPhone and Watch either.** The cache is local to each device. For tracked goals that doesn't matter, because the system mirrors the samples from the watch to the phone on its own.

**Manual goals are entirely out.** A "read 20 pages" checkmark has nothing to do with HealthKit, your app already owns that state, and it already publishes it. Letting the SDK store it too would create a second owner for the same fact. Your app merges the two sources when it builds the rings, which is where it already knows about both.
