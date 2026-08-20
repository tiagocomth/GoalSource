import Foundation

public struct GoalDefinition: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let target: Double
    public let metric: GoalMetric

    public init(id: String = UUID().uuidString, title: String, target: Double, metric: GoalMetric) {
        self.id = id
        self.title = title
        self.target = target
        self.metric = metric
    }
}

public extension Collection where Element == GoalDefinition {
    var metrics: Set<GoalMetric> {
        Set(map(\.metric))
    }
}
