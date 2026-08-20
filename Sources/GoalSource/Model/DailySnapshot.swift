import Foundation

public struct DailySnapshot: Codable, Sendable, Hashable {
    public let date: Date
    public let progress: [GoalProgress]

    public init(date: Date, progress: [GoalProgress]) {
        self.date = date
        self.progress = progress
    }
}

public extension DailySnapshot {
    var overallFraction: Double {
        guard !progress.isEmpty else { return 0 }
        return progress.reduce(0) { $0 + $1.fraction } / Double(progress.count)
    }

    var isComplete: Bool {
        !progress.isEmpty && progress.allSatisfy(\.isComplete)
    }

    func progress(for goalID: GoalDefinition.ID) -> GoalProgress? {
        progress.first { $0.goalID == goalID }
    }

    var fractionsByGoal: [GoalDefinition.ID: Double] {
        Dictionary(uniqueKeysWithValues: progress.map { ($0.goalID, $0.fraction) })
    }

    static func empty(for goals: [GoalDefinition], on date: Date) -> DailySnapshot {
        DailySnapshot(
            date: date,
            progress: goals.map { GoalProgress.zero(for: $0, on: date) }
        )
    }
}
