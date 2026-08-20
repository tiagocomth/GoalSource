import Foundation

public actor StubHealthStore: HealthStoreProviding {
    private var totals: [GoalMetric: Double]
    private let available: Bool
    private var onChange: (@Sendable () -> Void)?

    public init(totals: [GoalMetric: Double] = [:], isHealthDataAvailable: Bool = true) {
        self.totals = totals
        self.available = isHealthDataAvailable
    }

    public func setTotal(_ total: Double, for metric: GoalMetric) {
        totals[metric] = total
        onChange?()
    }

    public var isHealthDataAvailable: Bool {
        get async { available }
    }

    public func requestAuthorization(read: Set<GoalMetric>, write: Set<GoalMetric>) async throws {}

    public func writeAuthorizationStatus(for metric: GoalMetric) async -> MetricAuthorization {
        .authorized
    }

    public func total(for metric: GoalMetric, from start: Date, to end: Date) async throws -> Double? {
        totals[metric] ?? 0
    }

    public func write(_ amount: Double, for metric: GoalMetric, at date: Date) async throws {
        totals[metric, default: 0] += amount
        onChange?()
    }

    public func observe(
        _ metrics: Set<GoalMetric>,
        onChange: @escaping @Sendable () -> Void
    ) async throws -> HealthObservationToken {
        self.onChange = onChange
        return HealthObservationToken {}
    }

    public func setBackgroundDelivery(enabled: Bool, for metrics: Set<GoalMetric>) async throws {}
}
