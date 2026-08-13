import AppKit
import SwiftUI

enum BufferAppearanceMode: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

enum BufferSurfaceStyle: String, CaseIterable, Codable, Sendable {
    case glass
    case transparent
    case opaque
}

struct BufferAppearanceConfiguration: Equatable, Sendable {
    var mode: BufferAppearanceMode = .system
    var surfaceStyle: BufferSurfaceStyle = .glass

    static let systemGlass = BufferAppearanceConfiguration()
}

private struct BufferAppearanceEnvironmentKey: EnvironmentKey {
    static let defaultValue = BufferAppearanceConfiguration.systemGlass
}

extension EnvironmentValues {
    var bufferAppearance: BufferAppearanceConfiguration {
        get { self[BufferAppearanceEnvironmentKey.self] }
        set { self[BufferAppearanceEnvironmentKey.self] = newValue }
    }
}
