import Foundation

public enum ProgressUnavailableReason: String, Codable, Sendable {
    case authorizationNotRequested
    case authorizationDenied
    case noSamples
    case metricUnavailableOnDevice
}

public struct GoalProgress: Codable, Sendable, Hashable, Identifiable {
    public let goalID: GoalDefinition.ID
    public let value: Double
    public let target: Double
    public let fraction: Double
    public let isComplete: Bool
    public let lastUpdated: Date
    public let unavailableReason: ProgressUnavailableReason?

    public var id: GoalDefinition.ID { goalID }

    public init(
        goalID: GoalDefinition.ID,
        value: Double,
        target: Double,
        lastUpdated: Date,
        unavailableReason: ProgressUnavailableReason? = nil
    ) {
        let sanitizedValue = value.isFinite ? max(0, value) : 0
        let sanitizedTarget = target.isFinite ? target : 0

        self.goalID = goalID
        self.value = sanitizedValue
        self.target = sanitizedTarget
        self.lastUpdated = lastUpdated
        self.unavailableReason = unavailableReason

        if sanitizedTarget > 0 {
            fraction = min(1, sanitizedValue / sanitizedTarget)
            isComplete = sanitizedValue >= sanitizedTarget
        } else {
            Log.model.warning("Meta \(goalID, privacy: .public) tem target não positivo; reportando 0%.")
            fraction = 0
            isComplete = false
        }
    }
}

public extension GoalProgress {
    static func zero(
        for goal: GoalDefinition,
        on date: Date,
        unavailableReason: ProgressUnavailableReason? = nil
    ) -> GoalProgress {
        GoalProgress(
            goalID: goal.id,
            value: 0,
            target: goal.target,
            lastUpdated: date,
            unavailableReason: unavailableReason
        )
    }

    var isUnavailable: Bool { unavailableReason != nil }
}
