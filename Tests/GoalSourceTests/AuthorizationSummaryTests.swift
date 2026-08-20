import XCTest
@testable import GoalSource

final class AuthorizationSummaryTests: XCTestCase {
    func testPartialAuthorizationListsWhatIsMissing() {
        let summary = AuthorizationSummary(
            statuses: [
                .water: .denied,
                .stepCount: .requested,
                .activeEnergy: .notRequested
            ],
            isHealthDataAvailable: true
        )

        XCTAssertEqual(summary.deniedMetrics, [.water])
        XCTAssertEqual(summary.notRequestedMetrics, [.activeEnergy])
        XCTAssertEqual(summary.unavailableMetrics, [.water, .activeEnergy])
        XCTAssertFalse(summary.isFullyAuthorized)
        XCTAssertTrue(summary.needsPrompt)
    }

    func testFullyAuthorizedWhenNothingIsMissing() {
        let summary = AuthorizationSummary(
            statuses: [.water: .authorized, .stepCount: .requested],
            isHealthDataAvailable: true
        )
        XCTAssertTrue(summary.isFullyAuthorized)
        XCTAssertFalse(summary.needsPrompt)
        XCTAssertTrue(summary.unavailableMetrics.isEmpty)
    }

    func testNothingIsAuthorizedWithoutHealthData() {
        let summary = AuthorizationSummary(statuses: [.stepCount: .requested], isHealthDataAvailable: false)
        XCTAssertFalse(summary.isFullyAuthorized)
        XCTAssertFalse(summary.needsPrompt, "There is no sheet to present on a device without Health.")
    }

    func testUnknownMetricReadsAsNotRequested() {
        let summary = AuthorizationSummary(statuses: [:], isHealthDataAvailable: true)
        XCTAssertEqual(summary.status(for: .swimmingDistance), .notRequested)
    }
}
