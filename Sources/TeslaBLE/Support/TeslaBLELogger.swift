import os

/// Severity level for a log message. Ordered from most verbose to most severe.
public enum TeslaBLELogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Sink for internal TeslaBLE diagnostic messages.
///
/// The `message` parameter is `@autoclosure` so that call sites can build
/// expensive strings inline without paying for them when the logger chooses
/// to drop the message. Implementations **must** decide whether to log before
/// evaluating the closure — evaluating it unconditionally defeats the purpose
/// of `@autoclosure`.
///
/// `category` maps to OSLog categories (e.g. `"transport"`, `"bridge"`,
/// `"session"`, `"addkey"`). Callers use a small fixed set of categories so
/// Console.app filters remain usable.
public protocol TeslaBLELogger: Sendable {
    func log(
        _ level: TeslaBLELogLevel,
        category: String,
        _ message: @autoclosure () -> String,
    )
}

/// Default `os.Logger`-backed `TeslaBLELogger`.
///
/// Messages below `minimumLevel` are dropped without evaluating the message
/// closure. Every interpolated value is logged with `privacy: .private` by
/// default, because BLE session traffic routinely contains key material, VIN
/// fragments, and session tokens that should not appear in Console.app on
/// non-developer devices. Set `publicMessages: true` only for development
/// builds where you have explicitly audited the call sites.
public struct OSLogTeslaBLELogger: TeslaBLELogger {
    private let subsystem: String
    private let minimumLevel: TeslaBLELogLevel
    private let publicMessages: Bool

    public init(
        subsystem: String = "TeslaBLE",
        minimumLevel: TeslaBLELogLevel = .debug,
        publicMessages: Bool = false,
    ) {
        self.subsystem = subsystem
        self.minimumLevel = minimumLevel
        self.publicMessages = publicMessages
    }

    public func log(
        _ level: TeslaBLELogLevel,
        category: String,
        _ message: @autoclosure () -> String,
    ) {
        guard level >= minimumLevel else { return }
        let logger = Logger(subsystem: subsystem, category: category)
        let text = message()
        if publicMessages {
            logPublic(logger, level: level, text: text)
        } else {
            logPrivate(logger, level: level, text: text)
        }
    }

    private func logPrivate(_ logger: Logger, level: TeslaBLELogLevel, text: String) {
        switch level {
        case .debug: logger.debug("\(text, privacy: .private)")
        case .info: logger.info("\(text, privacy: .private)")
        case .warning: logger.notice("\(text, privacy: .private)")
        case .error: logger.error("\(text, privacy: .private)")
        }
    }

    private func logPublic(_ logger: Logger, level: TeslaBLELogLevel, text: String) {
        switch level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .warning: logger.notice("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        }
    }
}
