import Foundation

enum AppLaunchEnvironment {
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            && uiValidationConfiguration == nil
    }

    #if BUFFER_UI_VALIDATION
        static let uiValidationConfiguration: BufferUIValidationConfiguration? =
            BufferUIValidationConfiguration.currentProcess()
    #elseif DEBUG
        static var uiValidationConfiguration: BufferUIValidationConfiguration? {
            BufferUIValidationConfiguration(
                environment: ProcessInfo.processInfo.environment,
                arguments: ProcessInfo.processInfo.arguments
            )
        }
    #else
        static var uiValidationConfiguration: BufferUIValidationConfiguration? { nil }
    #endif
}

struct BufferUIValidationConfiguration: Sendable {
    private enum EnvironmentKey {
        static let enabled = "BUFFER_UI_VALIDATION"
        static let storageDirectory = "BUFFER_UI_VALIDATION_STORAGE_DIRECTORY"
        static let itemCount = "BUFFER_UI_VALIDATION_ITEM_COUNT"
    }

    private enum Argument {
        static let enabled = "--buffer-ui-validation"
        static let storageDirectory = "--buffer-ui-validation-storage-directory"
        static let itemCount = "--buffer-ui-validation-item-count"
    }

    let storageDirectory: URL
    let itemCount: Int

    #if BUFFER_UI_VALIDATION
        static func currentProcess() -> BufferUIValidationConfiguration {
            BufferUIValidationConfiguration(
                storageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "Buffer-UI-Validation-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                ),
                itemCount: 900
            )
        }
    #endif

    init?(environment: [String: String], arguments: [String]) {
        let argumentValues = Self.argumentValues(arguments)
        let isEnabled =
            environment[EnvironmentKey.enabled] == "1"
            || argumentValues[Argument.enabled] == "1"
        let rawStoragePath =
            environment[EnvironmentKey.storageDirectory]
            ?? argumentValues[Argument.storageDirectory]

        guard isEnabled,
            let rawStoragePath,
            let storageDirectory = Self.validatedTemporaryDirectory(rawStoragePath)
        else { return nil }

        let requestedItemCount =
            (environment[EnvironmentKey.itemCount] ?? argumentValues[Argument.itemCount])
            .flatMap(Int.init) ?? 600
        self.storageDirectory = storageDirectory
        self.itemCount = requestedItemCount.clamped(to: 20...10_000)
    }

    private init(storageDirectory: URL, itemCount: Int) {
        self.storageDirectory = storageDirectory
        self.itemCount = itemCount
    }

    @MainActor
    func makeSettingsManager() -> SettingsManager {
        let suiteName = "Buffer.UIValidation.\(storageDirectory.lastPathComponent)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated UI-validation defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsManager(
            defaults: defaults,
            launchAtLoginController: BufferUIValidationLaunchAtLoginController()
        )
        settings.setHistoryLimit(10_000)
        settings.setSearchBehavior(
            SearchBehaviorSettings(
                keepSearchTextAfterPaste: false,
                keepSearchTextAfterClosing: false,
                confirmDeleteWithKeyboardShortcut: false
            )
        )
        settings.setPrivacySettings(
            PrivacySettings(
                historyRetentionPeriod: .never,
                enableWebsitePreviews: false
            )
        )
        settings.setHistoryWindowOpenBehavior(.selectFirstNonPinnedItem)
        return settings
    }

    func prepareStorage() throws -> ClipboardStoragePaths {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: storageDirectory.path) {
            try fileManager.removeItem(at: storageDirectory)
        }
        try fileManager.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        let paths = ClipboardStoragePaths(
            storageDirectory: storageDirectory,
            historyFileURL: storageDirectory.appendingPathComponent("history.json"),
            imagesDirectory: storageDirectory.appendingPathComponent("images", isDirectory: true),
            textsDirectory: storageDirectory.appendingPathComponent("texts", isDirectory: true)
        )
        do {
            try fileManager.createDirectory(
                at: paths.imagesDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: paths.textsDirectory,
                withIntermediateDirectories: true
            )
            try ClipboardHistoryPersistence(paths: paths).saveHistory(makeFixtureItems())
            return paths
        } catch {
            try? fileManager.removeItem(at: storageDirectory)
            throw error
        }
    }

    func removeStorage() {
        try? FileManager.default.removeItem(at: storageDirectory)
    }

    private func makeFixtureItems() -> [ClipboardItem] {
        let calendar = Self.fixtureCalendar
        guard
            let referenceDate = calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 10,
                    day: 31,
                    hour: 12
                )
            )
        else {
            preconditionFailure("Unable to construct the UI-validation reference date")
        }

        return (0..<itemCount).map { index in
            let dayOffset = -(index / 3)
            let minuteOffset = -(index % 3)
            let timestamp = referenceDate.addingTimeInterval(
                TimeInterval(dayOffset * 86_400 + minuteOffset * 60)
            )
            return ClipboardItem(
                id: Self.fixtureID(index: index),
                type: .text,
                timestamp: timestamp,
                sourceApp: "Buffer UI Validation",
                sourceAppBundleIdentifier: "de.floxyi.buffer.ui-validation",
                textContent: String(format: "UI Fixture %04d", index),
                isPinned: index < 3,
                pinnedAt: index < 3 ? timestamp : nil
            )
        }
    }

    private static func fixtureID(index: Int) -> UUID {
        let suffix = String(format: "%012X", index + 1)
        guard let id = UUID(uuidString: "10000000-0000-4000-8000-\(suffix)") else {
            preconditionFailure("Unable to construct the UI-validation item identifier")
        }
        return id
    }

    private static var fixtureCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func validatedTemporaryDirectory(_ path: String) -> URL? {
        let candidate = resolvingSymlinksInExistingAncestors(
            of: URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        )
        let temporaryRoot = FileManager.default.temporaryDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath =
            temporaryRoot.path.hasSuffix("/")
            ? temporaryRoot.path : temporaryRoot.path + "/"
        guard candidate.path.hasPrefix(rootPath), candidate.path != temporaryRoot.path else {
            return nil
        }
        return candidate
    }

    /// `URL.resolvingSymlinksInPath()` does not resolve an intermediate
    /// symlink when the final child does not exist yet. Resolve the nearest
    /// existing ancestor first, then append the missing path components.
    private static func resolvingSymlinksInExistingAncestors(of url: URL) -> URL {
        let fileManager = FileManager.default
        var existingAncestor = url
        var missingComponents: [String] = []

        while existingAncestor.path != "/",
            !fileManager.fileExists(atPath: existingAncestor.path)
        {
            missingComponents.append(existingAncestor.lastPathComponent)
            existingAncestor.deleteLastPathComponent()
        }

        var resolvedURL = existingAncestor.resolvingSymlinksInPath()
        for component in missingComponents.reversed() {
            resolvedURL.appendPathComponent(component)
        }
        return resolvedURL.standardizedFileURL
    }

    private static func argumentValues(_ arguments: [String]) -> [String: String] {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == Argument.enabled {
                values[argument] = "1"
            } else if argument == Argument.storageDirectory || argument == Argument.itemCount,
                arguments.indices.contains(index + 1)
            {
                values[argument] = arguments[index + 1]
                index += 1
            }
            index += 1
        }
        return values
    }
}

private final class BufferUIValidationLaunchAtLoginController: LaunchAtLoginControlling {
    func isEnabled() -> Bool { false }
    func setEnabled(_: Bool) throws {}
}
