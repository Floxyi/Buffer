import Cocoa
import UniformTypeIdentifiers

@MainActor
protocol PasteEventSending {
    var hasPostEventAccess: Bool { get }
    @discardableResult func requestPostEventAccess() -> Bool
    func sendPasteShortcut() -> Bool
}

@MainActor
struct PasteEventSender: PasteEventSending {
    var hasPostEventAccess: Bool {
        CGPreflightPostEventAccess()
    }

    @discardableResult
    func requestPostEventAccess() -> Bool {
        CGRequestPostEventAccess()
    }

    func sendPasteShortcut() -> Bool {
        guard hasPostEventAccess else { return false }

        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}

@MainActor
struct PasteImageExporter: PasteImageExporting {
    private static let staleSessionAge: TimeInterval = 24 * 60 * 60

    func saveImageToTemp(_ image: NSImage, sessionID: UUID, fileName: String) -> URL? {
        guard let sessionDirectory = sessionDirectory(for: sessionID, createIfNeeded: true) else { return nil }
        let fileURL = sessionDirectory.appendingPathComponent(fileName, isDirectory: false)

        guard let tiffData = image.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData),
            let pngData = bitmapImage.representation(using: .png, properties: [:])
        else {
            return nil
        }

        do {
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            BufferLogger.clipboard.error(
                "Failed to write temporary paste image \(fileName, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    func removePasteSession(_ sessionID: UUID) {
        guard let directory = sessionDirectory(for: sessionID, createIfNeeded: false) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch  where (error as NSError).code == NSFileNoSuchFileError {
            return
        } catch {
            BufferLogger.clipboard.error(
                "Failed to clean paste session \(sessionID.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    func removeStalePasteSessions() {
        let root = pasteRootDirectory
        guard
            let directories = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return }

        let cutoff = Date().addingTimeInterval(-Self.staleSessionAge)
        for directory in directories {
            guard
                let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                values.isDirectory == true,
                values.contentModificationDate.map({ $0 < cutoff }) == true
            else { continue }

            try? FileManager.default.removeItem(at: directory)
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
            let pngData = bitmapRep.representation(using: .png, properties: [:])
        else {
            BufferLogger.clipboard.error("Failed to create PNG data from image")
            return
        }

        do {
            try pngData.write(to: url, options: .atomic)
        } catch {
            BufferLogger.clipboard.error(
                "Failed to save image to disk: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private var pasteRootDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("BufferPaste", isDirectory: true)
    }

    private func sessionDirectory(for sessionID: UUID, createIfNeeded: Bool) -> URL? {
        let root = pasteRootDirectory
        let directory = root.appendingPathComponent(sessionID.uuidString, isDirectory: true)

        if createIfNeeded {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                BufferLogger.clipboard.error(
                    "Failed to create temporary paste directory: \(String(describing: error), privacy: .public)"
                )
                return nil
            }
        }

        return directory
    }
}

@MainActor
enum PasteImageSupport {
    static func saveImageToDisk(_ image: NSImage) {
        PasteImageExporter().saveImageToDisk(image)
    }
}
