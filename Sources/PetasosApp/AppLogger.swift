import Foundation
import os

/// Thin os.Logger wrapper. Single subsystem; one category for now.
/// Adopting os.Logger means messages route to Console.app with subsystem filtering.
public struct AppLogger: Sendable {
    private let logger: Logger

    public init(subsystem: String = "com.petasos", category: String = "app") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    public func error(_ error: Error) {
        logger.error("\(String(describing: error), privacy: .public)")
    }

    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}
