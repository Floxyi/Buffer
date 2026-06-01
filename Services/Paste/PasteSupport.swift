import Cocoa
import UniformTypeIdentifiers

protocol PasteAutomating {
    func simulatePaste(after delay: TimeInterval)
}

struct PasteAutomation: PasteAutomating {
    func simulatePaste(after delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay.nanoseconds)
            simulatePaste()
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

@MainActor
struct PasteImageExporter: PasteImageExporting {
    func saveImageToTemp(_ image: NSImage, fileName: String) -> URL? {
        guard let tempDirectory = tempDirectory() else { return nil }
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            BufferLogger.clipboard.error("Failed to write temp image \(fileName, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func saveImageToDisk(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "Image-\(formatter.string(from: Date()))"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            BufferLogger.clipboard.error("Failed to create PNG data from image")
            return
        }

        do {
            try pngData.write(to: url, options: .atomic)
        } catch {
            BufferLogger.clipboard.error("Failed to save image to disk: \(String(describing: error), privacy: .public)")
        }
    }

    private func tempDirectory() -> URL? {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BufferPaste")
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            return tempDirectory
        } catch {
            BufferLogger.clipboard.error("Failed to create temp paste directory: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

@MainActor
enum PasteImageSupport {
    static func saveImageToTemp(_ image: NSImage, fileName: String) -> URL? {
        PasteImageExporter().saveImageToTemp(image, fileName: fileName)
    }

    static func saveImageToDisk(_ image: NSImage) {
        PasteImageExporter().saveImageToDisk(image)
    }
}

extension TimeInterval {
    var nanoseconds: UInt64 {
        UInt64((self * 1_000_000_000).rounded())
    }
}
