import os

public enum Log {
    public static let subsystem = "pl.net.kurant.wyspa"

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
