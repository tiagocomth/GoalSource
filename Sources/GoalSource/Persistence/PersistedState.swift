import Foundation

public struct PersistedState: Codable, Sendable, Equatable {
    public var lastSnapshot: DailySnapshot?
    public var requestedMetrics: Set<GoalMetric>

    public init(
        lastSnapshot: DailySnapshot? = nil,
        requestedMetrics: Set<GoalMetric> = []
    ) {
        self.lastSnapshot = lastSnapshot
        self.requestedMetrics = requestedMetrics
    }
}
