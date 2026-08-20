import Foundation
import os

enum Log {
    private static let subsystem = "com.goalsource"

    static let model = Logger(subsystem: subsystem, category: "model")

    static let store = Logger(subsystem: subsystem, category: "store")

    static let queries = Logger(subsystem: subsystem, category: "queries")

    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
