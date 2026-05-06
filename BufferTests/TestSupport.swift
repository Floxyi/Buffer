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
    timeoutNanoseconds: UInt64 = 1_000_000_000,
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
