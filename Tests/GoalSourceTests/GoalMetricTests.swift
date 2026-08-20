import XCTest
@testable import GoalSource

#if canImport(HealthKit)
import HealthKit
#endif

final class GoalMetricTests: XCTestCase {
    func testOnlyWaterIsWritable() {
        XCTAssertEqual(GoalMetric.allCases.filter(\.isWritable), [.water])
    }

    func testOnlyRunningReadsWorkouts() {
        XCTAssertEqual(GoalMetric.allCases.filter(\.readsWorkouts), [.runningDistance])
    }

    func testEveryMetricIsCumulative() {
        XCTAssertTrue(GoalMetric.allCases.allSatisfy(\.isCumulative))
    }

    func testDisplayLabelsMatchTheStoredUnit() {
        XCTAssertEqual(GoalMetric.water.displayUnitLabel, "L")
        XCTAssertEqual(GoalMetric.exerciseMinutes.displayUnitLabel, "min")
        XCTAssertEqual(GoalMetric.activeEnergy.displayUnitLabel, "kcal")
        XCTAssertEqual(GoalMetric.runningDistance.displayUnitLabel, "km")
        XCTAssertEqual(GoalMetric.stepCount.displayUnitLabel, "")
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(
            GoalMetric.allCases.map(\.rawValue),
            ["water", "exerciseMinutes", "activeEnergy", "runningDistance",
             "swimmingDistance", "walkingDistance", "stepCount"]
        )
    }

    func testMetricsDeduplicatesSoPermissionIsAskedOnce() {
        let goals = [
            Fixture.goal(metric: .water),
            Fixture.goal(metric: .stepCount),
            Fixture.goal(metric: .water)
        ]
        XCTAssertEqual(goals.metrics, [.water, .stepCount])
    }

    func testMetricKeyedDictionaryEncodesAsAnObject() throws {
        let statuses: [GoalMetric: MetricAuthorization] = [.water: .authorized]
        let json = String(data: try JSONEncoder().encode(statuses), encoding: .utf8)
        XCTAssertEqual(json, #"{"water":"authorized"}"#)
    }

    #if canImport(HealthKit)
    func testUnitsAreFixedPerMetricRegardlessOfLocale() {
        XCTAssertEqual(GoalMetric.water.preferredUnit, HKUnit.liter())
        XCTAssertEqual(GoalMetric.exerciseMinutes.preferredUnit, HKUnit.minute())
        XCTAssertEqual(GoalMetric.activeEnergy.preferredUnit, HKUnit.kilocalorie())
        XCTAssertEqual(GoalMetric.runningDistance.preferredUnit, HKUnit.meterUnit(with: .kilo))
        XCTAssertEqual(GoalMetric.swimmingDistance.preferredUnit, HKUnit.meterUnit(with: .kilo))
        XCTAssertEqual(GoalMetric.stepCount.preferredUnit, HKUnit.count())
    }

    func testKilometreUnitConvertsFromMetres() {
        let distance = HKQuantity(unit: .meter(), doubleValue: 5_000)
        XCTAssertEqual(distance.doubleValue(for: GoalMetric.runningDistance.preferredUnit), 5, accuracy: 0.0001)
    }

    func testEveryMetricResolvesToAQuantityType() {
        for metric in GoalMetric.allCases {
            XCTAssertNotNil(metric.quantityType, "\(metric.rawValue) has no quantity type on this OS.")
        }
    }
    #endif
}

final class GoalFactoryTests: XCTestCase {
    func testFactoriesBuildTheRightMetric() {
        XCTAssertEqual(GoalDefinition.water(2).metric, .water)
        XCTAssertEqual(GoalDefinition.steps(10_000).metric, .stepCount)
        XCTAssertEqual(GoalDefinition.exercise(minutes: 30).metric, .exerciseMinutes)
        XCTAssertEqual(GoalDefinition.activeEnergy(kilocalories: 500).metric, .activeEnergy)
        XCTAssertEqual(GoalDefinition.running(kilometers: 5).metric, .runningDistance)
        XCTAssertEqual(GoalDefinition.swimming(kilometers: 1).metric, .swimmingDistance)
        XCTAssertEqual(GoalDefinition.walking(kilometers: 3).metric, .walkingDistance)
    }

    func testFactoriesCarryTheTargetAndTitle() {
        let goal = GoalDefinition.running(kilometers: 5, title: "Corrida matinal")
        XCTAssertEqual(goal.target, 5)
        XCTAssertEqual(goal.title, "Corrida matinal")
    }

    func testFactoriesAcceptTheBackendsIdentity() {
        XCTAssertEqual(GoalDefinition.steps(10_000, id: "aBc123XyZ").id, "aBc123XyZ")
    }
}
