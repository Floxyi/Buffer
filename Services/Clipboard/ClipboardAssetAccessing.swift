import AppKit
import Foundation

struct ClipboardTextChunk: Equatable, Sendable {
    let text: String
    let totalBytes: Int
    let reachedEOF: Bool
}

protocol ClipboardAssetAccessing: Sendable {
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
