import XCTest
@testable import GoalSource

final class DailySnapshotTests: XCTestCase {
    private func progress(_ fraction: Double) -> GoalProgress {
        GoalProgress(goalID: UUID().uuidString, value: fraction, target: 1, lastUpdated: .now)
    }

    func testOverallFractionAveragesEveryGoal() {
        let snapshot = DailySnapshot(date: .now, progress: [progress(1), progress(0.5), progress(0), progress(0.5)])
        XCTAssertEqual(snapshot.overallFraction, 0.5, accuracy: 0.0001)
    }

    func testOverallFractionIsZeroWithoutGoals() {
        XCTAssertEqual(DailySnapshot(date: .now, progress: []).overallFraction, 0)
    }

    func testSnapshotIsCompleteOnlyWhenEveryGoalIs() {
        XCTAssertTrue(DailySnapshot(date: .now, progress: [progress(1), progress(1)]).isComplete)
        XCTAssertFalse(DailySnapshot(date: .now, progress: [progress(1), progress(0.9)]).isComplete)
        XCTAssertFalse(DailySnapshot(date: .now, progress: []).isComplete)
    }

    func testEmptySnapshotZeroesEveryGoal() {
        let goals = [Fixture.goal(target: 5, metric: .water), Fixture.goal(target: 1)]
        let snapshot = DailySnapshot.empty(for: goals, on: Fixture.noon)
        XCTAssertEqual(snapshot.progress.count, 2)
        XCTAssertEqual(snapshot.overallFraction, 0)
        XCTAssertEqual(snapshot.progress.first?.target, 5, "The target survives so the ring can still show 0 of 5.")
    }

    func testFractionsByGoalIsKeyedByGoal() {
        let goal = Fixture.goal(target: 4, metric: .stepCount)
        let snapshot = DailySnapshot(
            date: .now,
            progress: [GoalProgress(goalID: goal.id, value: 1, target: 4, lastUpdated: .now)]
        )
        XCTAssertEqual(snapshot.fractionsByGoal[goal.id], 0.25)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let original = DailySnapshot(date: Fixture.noon, progress: [progress(0.5)])
        let decoded = try JSONDecoder().decode(DailySnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
