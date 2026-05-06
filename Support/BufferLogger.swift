import OSLog

enum BufferLogger {
    static let app = Logger(subsystem: subsystem, category: "app")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let ui = Logger(subsystem: subsystem, category: "ui")

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.buffer.app"
}
