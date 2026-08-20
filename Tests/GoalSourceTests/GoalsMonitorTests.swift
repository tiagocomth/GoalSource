import XCTest
@testable import GoalSource

@MainActor
final class GoalsMonitorTests: XCTestCase {
    private let health = MockHealthStore()

    private func makeMonitor(goals: [GoalDefinition]) -> GoalsMonitor {
        let store = HealthKitGoalStore(
            configuration: .init(
                debounceInterval: .milliseconds(50),
                calendar: Fixture.calendar(timeZone: "America/Sao_Paulo"),
                snapshotStore: InMemorySnapshotStore()
            ),
            healthStore: health
        )
        return GoalsMonitor(goals: goals, store: store)
    }

    private func run(_ monitor: GoalsMonitor) -> Task<Void, Never> {
        let task = Task { await monitor.start() }
        addTeardownBlock { task.cancel() }
        return task
    }

    private func waitForSnapshot(_ monitor: GoalsMonitor, timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while monitor.snapshot == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testReadingBeforeTheFirstSnapshotIsSafe() {
        let goal = GoalDefinition.steps(10_000)
        let monitor = makeMonitor(goals: [goal])

        XCTAssertNil(monitor.snapshot)
        XCTAssertEqual(monitor.fraction(for: goal), 0, "A view body must render before the first read lands.")
        XCTAssertEqual(monitor.overallFraction, 0)
        XCTAssertFalse(monitor.isComplete(goal))
        XCTAssertFalse(monitor.needsHealthAccess(for: goal))
    }

    func testStartRequestsAuthorizationAndPublishesProgress() async {
        let goal = GoalDefinition.steps(10_000)
        await health.setTotal(4_000, for: .stepCount)
        let monitor = makeMonitor(goals: [goal])

        _ = run(monitor)
        await waitForSnapshot(monitor)

        XCTAssertEqual(monitor.fraction(for: goal), 0.4, accuracy: 0.0001)
        XCTAssertFalse(monitor.isLoading)
        XCTAssertNil(monitor.lastError)
        let read = await health.requestedRead
        XCTAssertEqual(read, [.stepCount])
    }

    func testStartCanSkipThePromptSoOnboardingOwnsIt() async {
        let goal = GoalDefinition.steps(10_000)
        let monitor = makeMonitor(goals: [goal])

        let task = Task { await monitor.start(requestingAuthorization: false) }
        addTeardownBlock { task.cancel() }
        await waitForSnapshot(monitor)

        let calls = await health.authorizationCallCount
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(monitor.authorization?.needsPrompt, true)
        XCTAssertTrue(monitor.needsHealthAccess(for: goal), "The ring should offer to open Health, not read as 0%.")
    }

    func testFailedWriteSurfacesAsLastError() async {
        let monitor = makeMonitor(goals: [GoalDefinition.steps(10_000)])

        await monitor.log(500, for: .stepCount)

        XCTAssertEqual(monitor.lastError, .writeNotPermitted(.stepCount))
    }

    func testSuccessfulWriteClearsThePreviousError() async {
        let monitor = makeMonitor(goals: [GoalDefinition.water(2)])
        await monitor.log(500, for: .stepCount)
        XCTAssertNotNil(monitor.lastError)

        await monitor.log(0.25, for: .water)

        XCTAssertNil(monitor.lastError)
    }

    func testRefreshReadsAgainOnDemand() async {
        let goal = GoalDefinition.steps(1_000)
        await health.setTotal(100, for: .stepCount)
        let monitor = makeMonitor(goals: [goal])

        _ = run(monitor)
        await waitForSnapshot(monitor)
        await health.setTotal(900, for: .stepCount)
        await monitor.refresh()

        XCTAssertEqual(monitor.fraction(for: goal), 0.9, accuracy: 0.0001)
    }

    func testSwappingGoalsClearsTheStaleSnapshot() async {
        let steps = GoalDefinition.steps(1_000)
        await health.setTotal(500, for: .stepCount)
        let monitor = makeMonitor(goals: [steps])

        _ = run(monitor)
        await waitForSnapshot(monitor)
        XCTAssertNotNil(monitor.snapshot)

        monitor.setGoals([GoalDefinition.water(2)])
        XCTAssertNil(monitor.snapshot, "Rings must not keep drawing the previous group's numbers.")
        XCTAssertEqual(monitor.goals.count, 1)
    }

    func testPreviewMonitorWorksWithoutHealthKit() async {
        let steps = GoalDefinition.steps(10_000)
        let water = GoalDefinition.water(2)
        let monitor = GoalsMonitor.preview(goals: [steps, water], totals: [.stepCount: 7_500, .water: 0.5])

        let task = Task { await monitor.start() }
        addTeardownBlock { task.cancel() }
        await waitForSnapshot(monitor)

        XCTAssertEqual(monitor.fraction(for: steps), 0.75, accuracy: 0.0001)
        XCTAssertEqual(monitor.overallFraction, 0.5, accuracy: 0.0001)
    }
}
