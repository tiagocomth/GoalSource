import Foundation

public enum HealthKitGoalError: LocalizedError, Sendable, Equatable {
    case healthDataUnavailable
    case authorizationDenied(Set<GoalMetric>)
    case unsupportedMetric(GoalMetric)
    case writeNotPermitted(GoalMetric)
    case queryFailed(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "Health data is not available on this device."
        case let .authorizationDenied(metrics):
            "Access was denied for: \(metrics.map(\.rawValue).sorted().joined(separator: ", "))."
        case let .unsupportedMetric(metric):
            "The metric \(metric.rawValue) is not supported on this OS version."
        case let .writeNotPermitted(metric):
            "This app does not write \(metric.rawValue) samples."
        case let .queryFailed(underlying):
            "The Health query failed: \(underlying)."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .healthDataUnavailable:
            "Open the app on an iPhone or Apple Watch."
        case .authorizationDenied:
            "Enable this data in Settings, Health, Data Access & Devices."
        case .unsupportedMetric, .writeNotPermitted:
            "Pick a different metric for this goal."
        case .queryFailed:
            "Try again in a moment."
        }
    }

    static func wrapping(_ error: any Error) -> HealthKitGoalError {
        (error as? HealthKitGoalError) ?? .queryFailed(underlying: String(describing: error))
    }
}
