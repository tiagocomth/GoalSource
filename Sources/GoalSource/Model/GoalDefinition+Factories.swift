import Foundation

public extension GoalDefinition {
    static func water(_ liters: Double, title: String = "Água", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: liters, metric: .water)
    }

    static func steps(_ count: Double, title: String = "Passos", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: count, metric: .stepCount)
    }

    static func exercise(minutes: Double, title: String = "Exercício", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: minutes, metric: .exerciseMinutes)
    }

    static func activeEnergy(kilocalories: Double, title: String = "Calorias", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: kilocalories, metric: .activeEnergy)
    }

    static func running(kilometers: Double, title: String = "Corrida", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: kilometers, metric: .runningDistance)
    }

    static func swimming(kilometers: Double, title: String = "Natação", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: kilometers, metric: .swimmingDistance)
    }

    static func walking(kilometers: Double, title: String = "Caminhada", id: String = UUID().uuidString) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: kilometers, metric: .walkingDistance)
    }
}
