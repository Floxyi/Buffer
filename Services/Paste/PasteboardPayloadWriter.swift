import AppKit

enum BufferPasteboardProvenance {
    static let pasteboardType = NSPasteboard.PasteboardType("de.floxyi.buffer.source-application")
    static let marker = "buffer"

    static func add(to item: NSPasteboardItem) throws {
        guard item.setString(marker, forType: pasteboardType) else {
            throw PasteboardWriteError.encodeFailed
        }
    }

    static func matches(_ markerValue: String?) -> Bool {
        markerValue == marker
    }
}

struct PasteboardWriteReceipt: Equatable {
    let changeCount: Int
}

enum PasteboardWriteError: LocalizedError, Equatable {
    case encodeFailed
    case writeRejected

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            String(localized: "Buffer could not encode the selected clipboard content.")
        case .writeRejected:
            String(localized: "macOS rejected the clipboard write.")
        }
    }
}

@MainActor
protocol PastePayloadWriting {
    func write(_ payload: PastePayload) throws -> PasteboardWriteReceipt
}

struct PasteboardPayloadWriter: PastePayloadWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(_ payload: PastePayload) throws -> PasteboardWriteReceipt {
        let objects: [NSPasteboardWriting]

        switch payload {
        case .string(let text):
            let item = NSPasteboardItem()
            guard item.setString(text, forType: .string) else {
                throw PasteboardWriteError.encodeFailed
            }
            try BufferPasteboardProvenance.add(to: item)
            objects = [item]

        case .fileURLs(let urls):
            guard !urls.isEmpty else { throw PasteboardWriteError.encodeFailed }
            objects = urls.map { $0 as NSURL }

        case .tiff(let data):
            let item = NSPasteboardItem()
            guard item.setData(data, forType: .tiff) else {
                throw PasteboardWriteError.encodeFailed
            }
            try BufferPasteboardProvenance.add(to: item)
            objects = [item]
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects(objects) else {
            throw PasteboardWriteError.writeRejected
        }
        return PasteboardWriteReceipt(changeCount: pasteboard.changeCount)
    }
}
