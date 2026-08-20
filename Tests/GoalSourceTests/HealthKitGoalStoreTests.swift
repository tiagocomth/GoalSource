import XCTest
@testable import GoalSource

final class HealthKitGoalStoreTests: XCTestCase {
    private let health = MockHealthStore()
    private let cache = InMemorySnapshotStore()

    private func makeStore(
        debounce: Duration = .milliseconds(50),
        backgroundDelivery: Bool = false,
        timeZone: String = "America/Sao_Paulo"
    ) -> HealthKitGoalStore {
        HealthKitGoalStore(
            configuration: .init(
                debounceInterval: debounce,
                enablesBackgroundDelivery: backgroundDelivery,
                calendar: Fixture.calendar(timeZone: timeZone),
                snapshotStore: cache
            ),
            healthStore: health
        )
    }

    func testAuthorizationAsksOnlyForTheGroupsMetrics() async throws {
        let goals = [
            Fixture.goal(metric: .water),
            Fixture.goal(metric: .stepCount)
        ]
        let store = makeStore()

        try await store.requestAuthorization(for: goals)

        let read = await health.requestedRead
        let write = await health.requestedWrite
        XCTAssertEqual(read, [.water, .stepCount], "Only the metrics actually in play, never the catalog.")
        XCTAssertEqual(write, [.water], "Only water is ever written.")
    }

    func testAuthorizationIsNotRequestedWithoutGoals() async throws {
        let store = makeStore()
        try await store.requestAuthorization(for: [])
        let calls = await health.authorizationCallCount
        XCTAssertEqual(calls, 0, "No sheet should appear when there is nothing to read.")
    }

    func testAuthorizationThrowsWithoutHealthData() async {
        await health.setAvailable(false)
        let store = makeStore()
        do {
            try await store.requestAuthorization(for: [Fixture.goal(metric: .water)])
            XCTFail("Expected healthDataUnavailable.")
        } catch {
            XCTAssertEqual(error as? HealthKitGoalError, .healthDataUnavailable)
        }
    }

    func testSummaryReportsPartialAuthorization() async throws {
        await health.setWriteStatus(.denied, for: .water)
        let goals = [
            Fixture.goal(metric: .water),
            Fixture.goal(metric: .stepCount),
            Fixture.goal(metric: .activeEnergy)
        ]
        let store = makeStore()

        var summary = await store.authorizationStatus(for: goals)
        XCTAssertEqual(summary.notRequestedMetrics, [.stepCount, .activeEnergy])
        XCTAssertTrue(summary.needsPrompt)

        try await store.requestAuthorization(for: goals)

        summary = await store.authorizationStatus(for: goals)
        XCTAssertEqual(summary.deniedMetrics, [.water], "Water is writable, so its denial is knowable.")
        XCTAssertEqual(summary.status(for: .stepCount), .requested)
        XCTAssertTrue(summary.notRequestedMetrics.isEmpty)
        XCTAssertFalse(summary.isFullyAuthorized)
    }

    func testRequestedMetricsSurviveARestart() async throws {
        let goals = [Fixture.goal(metric: .stepCount)]
        try await makeStore().requestAuthorization(for: goals)

        let summary = await makeStore().authorizationStatus(for: goals)
        XCTAssertFalse(summary.needsPrompt)
        XCTAssertEqual(summary.status(for: .stepCount), .requested)
    }

    func testTrackedProgressUsesTheDaysTotal() async throws {
        let goal = Fixture.goal(target: 10_000, metric: .stepCount)
        await health.setTotal(2_500, for: .stepCount)
        let store = makeStore()
        try await store.requestAuthorization(for: [goal])

        let progress = try await store.progress(for: goal, on: Fixture.noon)

        XCTAssertEqual(progress.value, 2_500)
        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.0001)
        XCTAssertNil(progress.unavailableReason)
    }

    func testReadIsBoundedByTheUsersDay() async throws {
        let goal = Fixture.goal(target: 1, metric: .stepCount)
        let store = makeStore(timeZone: "Pacific/Kiritimati")
        try await store.requestAuthorization(for: [goal])

        _ = try await store.progress(for: goal, on: Fixture.noon)

        let queries = await health.totalQueries
        let calendar = Fixture.calendar(timeZone: "Pacific/Kiritimati")
        XCTAssertEqual(queries.count, 1)
        XCTAssertEqual(calendar.goalDayKey(for: queries[0].start), "2026-08-21")
        XCTAssertEqual(queries[0].end.timeIntervalSince(queries[0].start), 24 * 60 * 60)
    }

    func testUnaskedMetricReportsNoAuthorizationInsteadOfZero() async throws {
        let goal = Fixture.goal(target: 100, metric: .activeEnergy)
        await health.setTotal(80, for: .activeEnergy)

        let progress = try await makeStore().progress(for: goal, on: Fixture.noon)

        XCTAssertEqual(progress.fraction, 0)
        XCTAssertEqual(progress.unavailableReason, .authorizationNotRequested)
        let queries = await health.totalQueries
        XCTAssertTrue(queries.isEmpty, "There is no point querying a metric we never asked for.")
    }

    func testDeniedWriteMetricReportsDenial() async throws {
        let goal = Fixture.goal(target: 2, metric: .water)
        await health.setWriteStatus(.denied, for: .water)
        let store = makeStore()
        try await store.requestAuthorization(for: [goal])

        let progress = try await store.progress(for: goal, on: Fixture.noon)
        XCTAssertEqual(progress.unavailableReason, .authorizationDenied)
    }

    func testEmptyDayIsReportedAsNoSamplesNotAsAFailure() async throws {
        let goal = Fixture.goal(target: 5, metric: .swimmingDistance)
        await health.setTotal(0, for: .swimmingDistance)
        let store = makeStore()
        try await store.requestAuthorization(for: [goal])

        let progress = try await store.progress(for: goal, on: Fixture.noon)
        XCTAssertEqual(progress.value, 0)
        XCTAssertEqual(progress.unavailableReason, .noSamples)
    }

    func testMetricMissingFromTheDeviceIsReportedAsSuch() async throws {
        let goal = Fixture.goal(target: 5, metric: .swimmingDistance)
        await health.setTotal(nil, for: .swimmingDistance)
        let store = makeStore()
        try await store.requestAuthorization(for: [goal])

        let progress = try await store.progress(for: goal, on: Fixture.noon)
        XCTAssertEqual(progress.unavailableReason, .metricUnavailableOnDevice)
    }

    func testSnapshotKeepsGoalOrderAndAveragesThem() async throws {
        let steps = Fixture.goal(target: 10_000, metric: .stepCount)
        let water = Fixture.goal(target: 2, metric: .water)
        await health.setTotal(10_000, for: .stepCount)
        await health.setTotal(1, for: .water)
        let store = makeStore()
        try await store.requestAuthorization(for: [steps, water])

        let snapshot = try await store.snapshot(for: [steps, water], on: Fixture.noon)

        XCTAssertEqual(snapshot.progress.map(\.goalID), [steps.id, water.id])
        XCTAssertEqual(snapshot.overallFraction, 0.75, accuracy: 0.0001)
        XCTAssertEqual(Fixture.calendar(timeZone: "America/Sao_Paulo").goalDayKey(for: snapshot.date), "2026-08-20")
    }

    func testTodayFractionsAreKeyedByGoal() async throws {
        let steps = Fixture.goal(target: 1_000, metric: .stepCount)
        let water = Fixture.goal(target: 2, metric: .water)
        await health.setTotal(500, for: .stepCount)
        await health.setTotal(2, for: .water)
        let store = makeStore()
        try await store.requestAuthorization(for: [steps, water])

        let fractions = try await store.todayFractions(for: [steps, water])

        XCTAssertEqual(fractions[steps.id], 0.5)
        XCTAssertEqual(fractions[water.id], 1)
    }

    func testLoggingWaterReachesHealthKit() async throws {
        try await makeStore().log(0.25, for: .water, at: Fixture.noon)

        let writes = await health.writes
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.amount, 0.25)
        XCTAssertEqual(writes.first?.metric, .water)
    }

    func testLoggingASensorMetricIsRefused() async {
        do {
            try await makeStore().log(500, for: .stepCount, at: Fixture.noon)
            XCTFail("Expected writeNotPermitted.")
        } catch {
            XCTAssertEqual(error as? HealthKitGoalError, .writeNotPermitted(.stepCount))
        }
        let writes = await health.writes
        XCTAssertTrue(writes.isEmpty)
    }

    func testLoggingNothingIsANoOp() async throws {
        try await makeStore().log(0, for: .water, at: Fixture.noon)
        let writes = await health.writes
        XCTAssertTrue(writes.isEmpty)
    }

    func testSnapshotIsCachedForTheNextLaunch() async throws {
        let goal = Fixture.goal(target: 1_000, metric: .stepCount)
        await health.setTotal(750, for: .stepCount)
        let store = makeStore()
        try await store.requestAuthorization(for: [goal])
        _ = try await store.snapshot(for: [goal], on: Fixture.noon)

        let restored = await makeStore().cachedSnapshot()
        XCTAssertEqual(restored?.progress.first?.value, 750)
        XCTAssertEqual(restored?.overallFraction ?? 0, 0.75, accuracy: 0.0001)
    }

    func testNoCachedSnapshotOnAFirstLaunch() async {
        let restored = await makeStore().cachedSnapshot()
        XCTAssertNil(restored)
    }
}
