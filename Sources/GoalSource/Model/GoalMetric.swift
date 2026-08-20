import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

public enum GoalMetric: String, Codable, Sendable, CaseIterable {
    case water
    case exerciseMinutes
    case activeEnergy
    case runningDistance
    case swimmingDistance
    case walkingDistance
    case stepCount
}

public extension GoalMetric {
    var displayUnitLabel: String {
        switch self {
        case .water: "L"
        case .exerciseMinutes: "min"
        case .activeEnergy: "kcal"
        case .runningDistance, .swimmingDistance, .walkingDistance: "km"
        case .stepCount: ""
        }
    }

    var isCumulative: Bool {
        switch self {
        case .water, .exerciseMinutes, .activeEnergy,
             .runningDistance, .swimmingDistance, .walkingDistance, .stepCount:
            true
        }
    }

    var isWritable: Bool {
        self == .water
    }

    var readsWorkouts: Bool {
        self == .runningDistance
    }
}

#if canImport(HealthKit)
public extension GoalMetric {
    var hkQuantityTypeIdentifier: HKQuantityTypeIdentifier {
        switch self {
        case .water: .dietaryWater
        case .exerciseMinutes: .appleExerciseTime
        case .activeEnergy: .activeEnergyBurned
        case .runningDistance: .distanceWalkingRunning
        case .swimmingDistance: .distanceSwimming
        case .walkingDistance: .distanceWalkingRunning
        case .stepCount: .stepCount
        }
    }

    var quantityType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: hkQuantityTypeIdentifier)
    }

    var preferredUnit: HKUnit {
        switch self {
        case .water: .liter()
        case .exerciseMinutes: .minute()
        case .activeEnergy: .kilocalorie()
        case .runningDistance, .swimmingDistance, .walkingDistance: .meterUnit(with: .kilo)
        case .stepCount: .count()
        }
    }
}
#endif

extension GoalMetric: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        GoalMetricCodingKey(stringValue: rawValue)
    }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(rawValue: codingKey.stringValue)
    }
}

private struct GoalMetricCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
