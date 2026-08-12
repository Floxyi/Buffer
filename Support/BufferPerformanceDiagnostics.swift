import Foundation
import OSLog

enum BufferPerformanceEvent: String {
    case clipboardCapture = "clipboard_capture"
    case historyFilter = "history_filter"
    case thumbnailLoad = "thumbnail_load"
    case previewLoad = "preview_load"
    case jumpScroll = "jump_scroll"
    case keyboardSelection = "keyboard_selection"
    case keyboardScroll = "keyboard_scroll"
    case ocr = "ocr"

    var signpostName: StaticString {
        switch self {
        case .clipboardCapture: "Clipboard Capture"
        case .historyFilter: "History Filter"
        case .thumbnailLoad: "Thumbnail Load"
        case .previewLoad: "Preview Load"
        case .jumpScroll: "Jump Scroll"
        case .keyboardSelection: "Keyboard Selection"
        case .keyboardScroll: "Keyboard Scroll"
        case .ocr: "OCR"
        }
    }
}

enum BufferPerformanceDiagnostics {
    struct Token {
        let event: BufferPerformanceEvent
        let start: ContinuousClock.Instant
        let signpostID: OSSignpostID
    }

    static let sampleLimit = 256
    private static let signpostLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "Buffer",
        category: "Performance"
    )

    #if DEBUG
        private static let lock = NSLock()
        nonisolated(unsafe) private static var samples: [BufferPerformanceEvent: [TimeInterval]] = [:]
    #endif

    static func begin(_ event: BufferPerformanceEvent) -> Token {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(
            .begin,
            log: signpostLog,
            name: event.signpostName,
            signpostID: signpostID
        )
        return Token(event: event, start: .now, signpostID: signpostID)
    }

    static func end(_ token: Token) {
        os_signpost(
            .end,
            log: signpostLog,
            name: token.event.signpostName,
            signpostID: token.signpostID
        )
        #if DEBUG
            record(token.start.duration(to: .now), for: token.event)
        #endif
    }

    static func measure<T>(_ event: BufferPerformanceEvent, operation: () -> T) -> T {
        let token = begin(event)
        defer { end(token) }
        return operation()
    }

    static func recordElapsed(
        since start: ContinuousClock.Instant,
        for event: BufferPerformanceEvent
    ) {
        let duration = start.duration(to: .now)
        os_signpost(
            .event,
            log: signpostLog,
            name: event.signpostName,
            "%{public}f seconds",
            duration.timeInterval
        )
        #if DEBUG
            record(duration, for: event)
        #endif
    }

    #if DEBUG
        static func samples(for event: BufferPerformanceEvent) -> [TimeInterval] {
            lock.lock()
            defer { lock.unlock() }
            return samples[event] ?? []
        }

        static func reset() {
            lock.lock()
            defer { lock.unlock() }
            samples.removeAll()
        }

        private static func record(_ duration: Duration, for event: BufferPerformanceEvent) {
            let seconds = duration.components.seconds
            let attoseconds = duration.components.attoseconds
            let interval = TimeInterval(seconds) + (TimeInterval(attoseconds) / 1_000_000_000_000_000_000)

            lock.lock()
            samples[event, default: []].append(interval)
            let overflow = (samples[event]?.count ?? 0) - sampleLimit
            if overflow > 0 {
                samples[event]?.removeFirst(overflow)
            }
            lock.unlock()
        }
    #else
        static func samples(for event: BufferPerformanceEvent) -> [TimeInterval] { [] }
        static func reset() {}
    #endif
}

extension Duration {
    fileprivate var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
