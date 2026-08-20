import XCTest
@testable import GoalSource

final class LiveSnapshotStreamTests: XCTestCase {
    private let health = MockHealthStore()

    private func makeStore(debounce: Duration, backgroundDelivery: Bool = false) -> HealthKitGoalStore {
        HealthKitGoalStore(
            configuration: .init(
                debounceInterval: debounce,
                enablesBackgroundDelivery: backgroundDelivery,
                calendar: Fixture.calendar(timeZone: "America/Sao_Paulo"),
                snapshotStore: InMemorySnapshotStore()
            ),
            healthStore: health
        )
    }

    private func collect(
        _ count: Int,
        from stream: AsyncStream<DailySnapshot>,
        timeout: Duration = .seconds(3)
    ) async -> [DailySnapshot] {
        let collector = Task { () -> [DailySnapshot] in
            var received: [DailySnapshot] = []
            for await snapshot in stream {
                received.append(snapshot)
                if received.count == count { break }
            }
            return received
        }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            collector.cancel()
        }
        let result = await collector.value
        timer.cancel()
        return result
    }

    func testStreamEmitsImmediatelyWithoutWaitingForTheDebounce() async throws {
        let goal = Fixture.goal(target: 1_000, metric: .stepCount)
        await health.setTotal(400, for: .stepCount)
        let store = makeStore(debounce: .seconds(30))
        try await store.requestAuthorization(for: [goal])

        let stream = await store.liveSnapshots(for: [goal])
        let received = await collect(1, from: stream, timeout: .seconds(2))

        XCTAssertEqual(received.count, 1, "The first frame must not wait on the debounce.")
        XCTAssertEqual(received.first?.progress.first?.value, 400)
    }

    func testBurstOfChangesCollapsesIntoOneEmission() async throws {
        let goal = Fixture.goal(target: 1_000, metric: .stepCount)
        await health.setTotal(100, for: .stepCount)
        let store = makeStore(debounce: .milliseconds(200))
        try await store.requestAuthorization(for: [goal])

        let stream = await store.liveSnapshots(for: [goal])
        let collector = Task { () -> [DailySnapshot] in
            var received: [DailySnapshot] = []
            for await snapshot in stream {
                received.append(snapshot)
            }
            return received
        }

        try await Task.sleep(for: .milliseconds(150))
        await health.setTotal(900, for: .stepCount)
        for _ in 0..<10 {
            await health.fireChange()
            try await Task.sleep(for: .milliseconds(10))
        }

        try await Task.sleep(for: .milliseconds(600))
        collector.cancel()
        let received = await collector.value

        XCTAssertEqual(received.count, 2, "One initial frame plus one debounced refresh, not eleven.")
        XCTAssertEqual(received.last?.progress.first?.value, 900)
    }

    func testChangesAfterTheDebounceWindowEmitAgain() async throws {
        let goal = Fixture.goal(target: 1_000, metric: .stepCount)
        await health.setTotal(100, for: .stepCount)
        let store = makeStore(debounce: .milliseconds(80))
        try await store.requestAuthorization(for: [goal])

        let stream = await store.liveSnapshots(for: [goal])
        let collector = Task { () -> Int in
            var count = 0
            for await _ in stream { count += 1 }
            return count
        }

        try await Task.sleep(for: .milliseconds(100))
        for _ in 0..<3 {
            await health.fireChange()
            try await Task.sleep(for: .milliseconds(250))
        }
        collector.cancel()
        let count = await collector.value

        XCTAssertEqual(count, 4, "Three well-spaced changes are three refreshes, plus the initial frame.")
    }

    func testDayRolloverEmptiesTheRingsImmediately() async throws {
        let goal = Fixture.goal(target: 1_000, metric: .stepCount)
        await health.setTotal(900, for: .stepCount)
        let store = makeStore(debounce: .seconds(30))
        try await store.requestAuthorization(for: [goal])

        let stream = await store.liveSnapshots(for: [goal])
        let collector = Task { () -> [DailySnapshot] in
            var received: [DailySnapshot] = []
            for await snapshot in stream {
                received.append(snapshot)
                if received.count == 2 { break }
            }
            return received
        }

        try await Task.sleep(for: .milliseconds(200))
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)

        let received = await collector.value
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0].overallFraction, 0.9, accuracy: 0.0001)
        XCTAssertEqual(received[1].overallFraction, 0, "Midnight empties the rings without waiting for the debounce.")
        XCTAssertEqual(received[1].progress.first?.target, 1_000, "The target stays so the ring keeps its scale.")
    }

    func testEndingTheStreamStopsTheHealthKitQueries() async throws {
        let goal = Fixture.goal(target: 1_000, metric: .stepCount)
        let store = makeStore(debounce: .milliseconds(50))
        try await store.requestAuthorization(for: [goal])

        do {
            let stream = await store.liveSnapshots(for: [goal])
            _ = await collect(1, from: stream, timeout: .seconds(2))
            let observing = await health.isObserving
            XCTAssertTrue(observing)
        }

        try await Task.sleep(for: .milliseconds(400))
        let cancelled = await health.cancelledObservations
        let observing = await health.isObserving
        XCTAssertGreaterThanOrEqual(cancelled, 1, "A dropped stream must not leak an HKObserverQuery.")
        XCTAssertFalse(observing)
    }

    func testBackgroundDeliveryIsEnabledOnlyWhenConfigured() async throws {
        let goal = Fixture.goal(target: 1_000, metric: .stepCount)
        let store = makeStore(debounce: .milliseconds(50), backgroundDelivery: true)
        try await store.requestAuthorization(for: [goal])

        let stream = await store.liveSnapshots(for: [goal])
        _ = await collect(1, from: stream, timeout: .seconds(2))
        try await Task.sleep(for: .milliseconds(200))

        let calls = await health.backgroundDeliveryCalls
        XCTAssertEqual(calls.first?.enabled, true)
        XCTAssertEqual(calls.first?.metrics, [.stepCount])
    }
}
