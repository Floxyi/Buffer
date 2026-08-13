import AppKit

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case behaviour
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .behaviour: return String(localized: "Behaviour")
        case .privacy: return String(localized: "Privacy")
        case .about: return String(localized: "About")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .behaviour: return "slider.horizontal.3"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

struct AppMetadata {
    let name: String
    let version: String
    let build: String
    let licenseName: String
    let licenseText: String

    static let current = AppMetadata(
        name: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Buffer",
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
        licenseName: "MIT License",
        licenseText: """
            MIT License

            Copyright (c) 2026 Samir Patil
            Copyright (c) 2026 Florian Winkler

            Permission is hereby granted, free of charge, to any person obtaining a copy
            of this software and associated documentation files (the "Software"), to deal
            in the Software without restriction, including without limitation the rights
            to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
            copies of the Software, and to permit persons to whom the Software is
            furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all
            copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
            IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
            FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
            AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
            LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
            OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            SOFTWARE.
            """
    )
}

final class AppBundleOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }

        if isDirectory.boolValue {
            if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                return true
            }

            return !url.hasDirectoryPath || url.pathExtension.isEmpty
        }

        return false
    }
}

extension ExcludedApp {
    init?(url: URL) {
        let bundle = Bundle(url: url)
        let bundlePath = url.path
        let bundleIdentifier = bundle?.bundleIdentifier
        let displayName =
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle?.object(
                forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent

        guard !displayName.isEmpty else { return nil }
        self.init(name: displayName, bundleIdentifier: bundleIdentifier, bundlePath: bundlePath)
    }
}
