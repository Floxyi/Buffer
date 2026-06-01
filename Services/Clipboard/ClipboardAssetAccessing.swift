import AppKit
import Foundation

protocol ClipboardAssetAccessing {
    func image(for item: ClipboardItem) -> NSImage?
    func thumbnail(for item: ClipboardItem, maxPixelSize: CGFloat) -> NSImage?
    func imageDimensions(for item: ClipboardItem) -> String?
    func saveImage(_ data: Data) -> String?
    func saveText(_ text: String) -> String?
    func fullText(for item: ClipboardItem) -> String?
    func textChunk(for item: ClipboardItem, charCount: Int) -> (text: String, totalBytes: Int, reachedEOF: Bool)?
    func itemSize(for item: ClipboardItem) -> Int?
}
