import AppKit
import Foundation

struct ClipboardLengthPrefixedBinaryEncoder {
    private(set) var data = Data()

    mutating func append(_ value: UInt8) {
        data.append(value)
    }

    mutating func appendFixedWidth(_ value: UInt64) {
        var bigEndianValue = value.bigEndian
        withUnsafeBytes(of: &bigEndianValue) { data.append(contentsOf: $0) }
    }

    mutating func appendLengthPrefixed(_ value: Data?) {
        guard let value else {
            appendFixedWidth(UInt64.max)
            return
        }
        appendFixedWidth(UInt64(value.count))
        data.append(value)
    }

    mutating func append(tag: UInt8, string: String?) {
        append(tag)
        appendLengthPrefixed(string.map { Data($0.utf8) })
    }
}

struct ClipboardTextChunk: Equatable, Sendable {
    let text: String
    let totalBytes: Int
    let reachedEOF: Bool
}

struct ClipboardAssetFilename: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        guard rawValue == URL(fileURLWithPath: rawValue).lastPathComponent,
            !rawValue.contains("/"),
            !rawValue.contains("\\"),
            rawValue.hasSuffix(".txt")
        else { return nil }
        let basename = String(rawValue.dropLast(4))
        guard UUID(uuidString: basename) != nil else { return nil }
        self.rawValue = rawValue
    }

    init(id: UUID = UUID()) {
        rawValue = id.uuidString + ".txt"
    }
}

struct ClipboardSearchAssetFingerprint: Equatable, Sendable {
    let fileIdentity: Data?
    let byteCount: Int64
    let modificationNanoseconds: Int64

    var encoded: Data {
        var encoder = ClipboardLengthPrefixedBinaryEncoder()
        encoder.appendLengthPrefixed(fileIdentity ?? Data())
        encoder.appendFixedWidth(UInt64(bitPattern: byteCount))
        encoder.appendFixedWidth(UInt64(bitPattern: modificationNanoseconds))
        return encoder.data
    }
}

struct ClipboardSearchAssetSnapshot: Sendable {
    let text: String
    let fingerprint: ClipboardSearchAssetFingerprint
}

protocol ClipboardSearchAssetAccessing: Sendable {
    func fingerprint(for item: ClipboardItem) throws -> ClipboardSearchAssetFingerprint
    func snapshot(
        for item: ClipboardItem,
        checkCancellation: @Sendable () throws -> Void
    ) throws -> ClipboardSearchAssetSnapshot
}

protocol ClipboardAssetAccessing: ClipboardSearchAssetAccessing, Sendable {
    func image(for item: ClipboardItem) -> NSImage?
    func imageData(for item: ClipboardItem) -> Data?
    func thumbnail(for item: ClipboardItem, maxPixelSize: CGFloat) -> NSImage?
    func imageDimensions(for item: ClipboardItem) -> String?
    func saveImage(_ data: Data) -> String?
    func saveText(_ text: String) -> String?
    func deleteImage(named filename: String)
    func deleteText(named filename: String)
    func fullText(for item: ClipboardItem) -> String?
    func textChunk(for item: ClipboardItem, charCount: Int) -> ClipboardTextChunk?
    func itemSize(for item: ClipboardItem) -> Int?
}
