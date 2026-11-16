import Foundation
import os

/// Subsystem-wide logging. Categories map one-to-one onto modules so
/// `log stream --predicate 'subsystem == "com.macshot.app"'` can be narrowed to one subsystem.
public enum MSLog {
    public static let subsystem = "com.macshot.app"

    public enum Category: String, Sendable, CaseIterable {
        case app, capture, overlay, annotate, pin, export, hotkey, settings, session, history

        public var logger: Logger { Logger(subsystem: MSLog.subsystem, category: rawValue) }
    }

    public static func logger(_ category: Category) -> Logger { category.logger }

    /// Public privacy: these strings never carry captured pixel data or file contents,
    /// only geometry and identifiers, which is what makes them safe to keep in a console log.
    public static func debug(_ category: Category, _ message: @autoclosure @escaping () -> String) {
        logger(category).debug("\(message(), privacy: .public)")
    }

    public static func info(_ category: Category, _ message: @autoclosure @escaping () -> String) {
        logger(category).info("\(message(), privacy: .public)")
    }

    public static func error(_ category: Category, _ message: @autoclosure @escaping () -> String) {
        logger(category).error("\(message(), privacy: .public)")
    }
}
