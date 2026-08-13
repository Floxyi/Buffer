import AppKit
import Foundation
import XCTest

@testable import Buffer

struct TestStorageFactory {
    static func makePaths(testName: String = UUID().uuidString) -> ClipboardStoragePaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufferTests", isDirectory: true)
            .appendingPathComponent(testName, isDirectory: true)

        return ClipboardStoragePaths(
            storageDirectory: root,
            historyFileURL: root.appendingPathComponent("history.json"),
            imagesDirectory: root.appendingPathComponent("images", isDirectory: true),
            textsDirectory: root.appendingPathComponent("texts", isDirectory: true)
        )
    }
}

final class FakeLaunchAtLoginController: LaunchAtLoginControlling {
    var enabled = false

    func isEnabled() -> Bool {
        enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        self.enabled = enabled
    }
}

@MainActor
struct FakeOCRService: OCRServicing {
    let result: String?

    func recognizeText(from image: NSImage) async -> String? {
        result
    }
}

func makeTestDefaults(testName: String = UUID().uuidString) -> UserDefaults {
    let suiteName = "BufferTests.\(testName)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func eventually(
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping @Sendable @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await MainActor.run(body: condition) {
            return
        }

        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    let finalValue = await MainActor.run(body: condition)
    XCTAssertTrue(finalValue, file: file, line: line)
}

@MainActor
func makeTestImage(
    size: NSSize = NSSize(width: 8, height: 8),
    color: NSColor = .systemBlue
) -> NSImage {
    NSImage(data: makePNGData(size: size, color: color))!
}

@MainActor
func makePNGData(
    size: NSSize = NSSize(width: 8, height: 8),
    color: NSColor = .systemBlue
) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    color.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    NSGraphicsContext.restoreGraphicsState()

    return try! XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
}
