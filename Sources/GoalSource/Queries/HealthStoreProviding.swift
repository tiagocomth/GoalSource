import Foundation

public protocol HealthStoreProviding: Sendable {
    var isHealthDataAvailable: Bool { get async }

    func requestAuthorization(read: Set<GoalMetric>, write: Set<GoalMetric>) async throws

    func writeAuthorizationStatus(for metric: GoalMetric) async -> MetricAuthorization

    func total(for metric: GoalMetric, from start: Date, to end: Date) async throws -> Double?

    func write(_ amount: Double, for metric: GoalMetric, at date: Date) async throws

    func observe(
        _ metrics: Set<GoalMetric>,
        onChange: @escaping @Sendable () -> Void
    ) async throws -> HealthObservationToken

    func setBackgroundDelivery(enabled: Bool, for metrics: Set<GoalMetric>) async throws
}
