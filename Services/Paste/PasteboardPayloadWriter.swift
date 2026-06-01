import AppKit

protocol PastePayloadWriting {
    func write(_ payload: PastePayload)
}

struct PasteboardPayloadWriter: PastePayloadWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(_ payload: PastePayload) {
        pasteboard.clearContents()

        switch payload {
        case .string(let text):
            pasteboard.setString(text, forType: .string)
        case .fileURLs(let urls):
            pasteboard.writeObjects(urls as [NSPasteboardWriting])
        case .tiff(let data):
            pasteboard.setData(data, forType: .tiff)
        }
    }
}
