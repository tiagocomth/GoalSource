import Foundation

public enum MetricAuthorization: String, Codable, Sendable {
    case notRequested
    case requested
    case denied
    case authorized
}

public struct AuthorizationSummary: Codable, Sendable, Hashable {
    public let statuses: [GoalMetric: MetricAuthorization]
    public let isHealthDataAvailable: Bool

    public init(statuses: [GoalMetric: MetricAuthorization], isHealthDataAvailable: Bool) {
        self.statuses = statuses
        self.isHealthDataAvailable = isHealthDataAvailable
    }
}

public extension AuthorizationSummary {
    var notRequestedMetrics: Set<GoalMetric> {
        metrics(matching: .notRequested)
    }

    var deniedMetrics: Set<GoalMetric> {
        metrics(matching: .denied)
    }

    var unavailableMetrics: Set<GoalMetric> {
        notRequestedMetrics.union(deniedMetrics)
    }

    var needsPrompt: Bool {
        isHealthDataAvailable && !notRequestedMetrics.isEmpty
    }

    var isFullyAuthorized: Bool {
        isHealthDataAvailable && unavailableMetrics.isEmpty
    }

    func status(for metric: GoalMetric) -> MetricAuthorization {
        statuses[metric] ?? .notRequested
    }

    private func metrics(matching status: MetricAuthorization) -> Set<GoalMetric> {
        Set(statuses.filter { $0.value == status }.keys)
    }
}
