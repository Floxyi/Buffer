import Foundation

struct ClipboardItemSourceApplication: Equatable, Sendable {
    let name: String?
    let bundleIdentifier: String?
    let bundlePath: String?

    init(sourceApplication: SourceApplicationInfo?) {
        name = sourceApplication?.name
        bundleIdentifier = sourceApplication?.bundleIdentifier
        bundlePath = sourceApplication?.bundlePath
    }
}

extension ClipboardItem {
    var normalizedSourceAppBundleIdentifier: String? {
        guard
            let bundleIdentifier = sourceAppBundleIdentifier?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !bundleIdentifier.isEmpty
        else {
            return nil
        }
        return bundleIdentifier
    }

    var sourceAppDisplayName: String? {
        if let sourceApp, !sourceApp.isEmpty {
            return sourceApp
        }

        if let sourceAppBundlePath, !sourceAppBundlePath.isEmpty {
            return URL(fileURLWithPath: sourceAppBundlePath)
                .deletingPathExtension()
                .lastPathComponent
        }

        if let normalizedSourceAppBundleIdentifier {
            return normalizedSourceAppBundleIdentifier
        }

        return nil
    }

    static func sourceApplicationValues(
        from sourceApplication: SourceApplicationInfo?
    ) -> ClipboardItemSourceApplication {
        ClipboardItemSourceApplication(sourceApplication: sourceApplication)
    }
}
