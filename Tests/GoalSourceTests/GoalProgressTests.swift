import XCTest
@testable import GoalSource

final class GoalProgressTests: XCTestCase {
    private let goalID = "goal-1"

    private func progress(value: Double, target: Double) -> GoalProgress {
        GoalProgress(goalID: goalID, value: value, target: target, lastUpdated: .now)
    }

    func testFractionIsTheRatioBelowTarget() {
        let result = progress(value: 1.5, target: 2)
        XCTAssertEqual(result.fraction, 0.75, accuracy: 0.0001)
        XCTAssertFalse(result.isComplete)
    }

    func testFractionClampsAboveTarget() {
        let result = progress(value: 12, target: 2)
        XCTAssertEqual(result.fraction, 1)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.value, 12, "The raw value survives the clamp; only the ring is capped.")
    }

    func testReachingTheTargetExactlyCompletes() {
        let result = progress(value: 2, target: 2)
        XCTAssertEqual(result.fraction, 1)
        XCTAssertTrue(result.isComplete)
    }

    func testZeroTargetReportsNoProgressInsteadOfCompleting() {
        let result = progress(value: 5, target: 0)
        XCTAssertEqual(result.fraction, 0)
        XCTAssertFalse(result.isComplete, "A malformed goal must not render as a finished ring.")
    }

    func testNegativeTargetIsTreatedLikeZero() {
        let result = progress(value: 5, target: -3)
        XCTAssertEqual(result.fraction, 0)
        XCTAssertFalse(result.isComplete)
    }

    func testNegativeValueClampsToZero() {
        let result = progress(value: -4, target: 2)
        XCTAssertEqual(result.value, 0)
        XCTAssertEqual(result.fraction, 0)
    }

    func testNonFiniteInputsDoNotProduceNaNFractions() {
        let fromNaN = progress(value: .nan, target: 2)
        XCTAssertEqual(fromNaN.fraction, 0)

        let fromInfinity = progress(value: .infinity, target: 2)
        XCTAssertEqual(fromInfinity.fraction, 0)

        let infiniteTarget = progress(value: 1, target: .infinity)
        XCTAssertEqual(infiniteTarget.fraction, 0)
    }

    func testUnavailableReasonSurvivesRoundTrip() throws {
        let original = GoalProgress(
            goalID: goalID,
            value: 0,
            target: 2,
            lastUpdated: .now,
            unavailableReason: .authorizationNotRequested
        )
        let decoded = try JSONDecoder().decode(
            GoalProgress.self,
            from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded.unavailableReason, .authorizationNotRequested)
        XCTAssertTrue(decoded.isUnavailable)
    }
}
