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
            "Os dados de Saúde não estão disponíveis neste aparelho."
        case let .authorizationDenied(metrics):
            "O acesso foi negado para: \(metrics.map(\.rawValue).sorted().joined(separator: ", "))."
        case let .unsupportedMetric(metric):
            "A métrica \(metric.rawValue) não é suportada nesta versão do sistema."
        case let .writeNotPermitted(metric):
            "O app não grava amostras de \(metric.rawValue)."
        case let .queryFailed(underlying):
            "A consulta ao Saúde falhou: \(underlying)."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .healthDataUnavailable:
            "Use metas manuais, ou abra o app no iPhone ou no Apple Watch."
        case .authorizationDenied:
            "Libere o dado da meta em Ajustes › Saúde › Acesso e Dispositivos."
        case .unsupportedMetric, .writeNotPermitted:
            "Escolha outra métrica para esta meta."
        case .queryFailed:
            "Tente de novo em instantes."
        }
    }

    static func wrapping(_ error: any Error) -> HealthKitGoalError {
        (error as? HealthKitGoalError) ?? .queryFailed(underlying: String(describing: error))
    }
}
