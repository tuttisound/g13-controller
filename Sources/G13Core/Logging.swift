import Foundation
import os

/// Centralized loggers. Use `log stream --predicate 'subsystem == "dev.tuttisound.G13Manager"'`
/// to follow at runtime.
public enum Log {
    public static let subsystem = "dev.tuttisound.G13Manager"
    public static let device = Logger(subsystem: subsystem, category: "device")
    public static let input = Logger(subsystem: subsystem, category: "input")
    public static let action = Logger(subsystem: subsystem, category: "action")
    public static let config = Logger(subsystem: subsystem, category: "config")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
