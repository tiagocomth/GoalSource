import Foundation

public extension GoalDefinition {
    static func water(_ liters: Double, title: String = "Water", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: liters, metric: .water)
    }

    static func steps(_ count: Double, title: String = "Steps", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: count, metric: .stepCount)
    }

    static func exercise(minutes: Double, title: String = "Exercise", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: minutes, metric: .exerciseMinutes)
    }

    static func activeEnergy(kilocalories: Double, title: String = "Calories", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: kilocalories, metric: .activeEnergy)
    }

    static func running(kilometers: Double, title: String = "Running", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: kilometers, metric: .runningDistance)
    }

    static func swimming(kilometers: Double, title: String = "Swimming", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: kilometers, metric: .swimmingDistance)
    }

    static func walking(kilometers: Double, title: String = "Walking", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: kilometers, metric: .walkingDistance)
    }
}
