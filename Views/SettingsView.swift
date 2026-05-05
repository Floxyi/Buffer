import SwiftUI
import AppKit

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .privacy: return "Privacy"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

private struct AppMetadata {
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

struct SettingsView: View {
    let onCategoryTitleChange: (String) -> Void

    @StateObject private var settings = SettingsViewModel()
    @State private var selectedCategory: SettingsCategory? = .general
    @State private var isRecording = false
    @State private var showingTrimAlert = false
    @State private var pendingTier: HistoryLimit?

    private let about = AppMetadata.current
    private var activeCategory: SettingsCategory { selectedCategory ?? .general }

    init(onCategoryTitleChange: @escaping (String) -> Void = { _ in }) {
        self.onCategoryTitleChange = onCategoryTitleChange
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                detailView(for: activeCategory)
                    .navigationTitle(activeCategory.title)
            }
            .id(activeCategory)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            if selectedCategory == nil {
                selectedCategory = .general
            }
            onCategoryTitleChange(activeCategory.title)
        }
        .onChange(of: selectedCategory) { _ in
            onCategoryTitleChange(activeCategory.title)
        }
        .alert("Reduce History Limit?", isPresented: $showingTrimAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reduce & Delete", role: .destructive) {
                if let tier = pendingTier {
                    settings.historyLimit = tier
                    settings.save()
                }
            }
        } message: {
            Text("This will permanently delete your oldest unpinned items to fit the new size. This action cannot be undone.")
        }
        .background(KeyRecorder(isRecording: $isRecording) { keyCode, modifiers in
            settings.hotkeyKeyCode = keyCode
            settings.hotkeyModifiers = modifiers
            settings.save()
            isRecording = false
        })
    }

    private var generalView: some View {
        Form {
            Section("Launch at Login") {
                Toggle("Open Buffer when you sign in", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { newValue in
                        SettingsManager.shared.toggleLaunchAtLogin(newValue)
                        DispatchQueue.main.async {
                            settings.launchAtLogin = SettingsManager.shared.launchAtLogin
                        }
                    }
                Text("Keep clipboard history running automatically in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History Size") {
                Picker("Saved History", selection: $settings.historyLimit) {
                    ForEach(HistoryLimit.allCases, id: \.self) { tier in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tier.label)
                            Text(tier.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(tier)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: settings.historyLimit) { newValue in
                    guard newValue != SettingsManager.shared.historyLimit else { return }
                    if newValue.rawValue < SettingsManager.shared.historyLimit.rawValue {
                        pendingTier = newValue
                        settings.historyLimit = SettingsManager.shared.historyLimit
                        showingTrimAlert = true
                    } else {
                        settings.save()
                    }
                }
            }

            Section("Keyboard Shortcut") {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text(settings.hotkeyModifiers.displayString)
                        Text(keyCodeNames[settings.hotkeyKeyCode] ?? "?")
                    }
                    .font(.system(.body).weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                    )

                    Button(isRecording ? "Cancel" : "Change") {
                        isRecording.toggle()
                    }
                    
                    Spacer()

                    Button("Restore") {
                        settings.restoreDefaultHotkey()
                        isRecording = false
                    }
                }

                Text(isRecording ? "Press your new shortcut... (use at least one modifier key)" : "Keyboard Shortcut to open clipboard history.")
                    .font(.caption)
                    .foregroundStyle(isRecording ? Color.accentColor : .secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var privacyView: some View {
        Form {
            Section("Excluded Apps") {
                Text("Buffer will ignore copied text and images from these apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    if settings.excludedApps.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "hand.raised")
                                .font(.system(size: 22))
                                .foregroundStyle(.secondary)
                            Text("No Excluded Apps")
                                .font(.headline)
                            Text("Add apps like password managers to keep their copied content out of Buffer history.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(settings.excludedApps) { app in
                                ExcludedAppRow(app: app) {
                                    settings.removeExcludedApp(app)
                                }

                                if app.id != settings.excludedApps.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .frame(height: 220)

                HStack {
                    Spacer()
                    Button(action: pickExcludedApp) {
                        Image(systemName: "plus")
                    }
                    .help("Add App")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutView: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(about.name)
                            .font(.title3.weight(.semibold))
                        Text("Version \(about.version) (\(about.build))")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Check for Updates") {
                    }
                    .padding(.trailing, 6)
                }
            }

            Section("License") {
                ScrollView {
                    Text(about.licenseText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(height: 300)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func detailView(for category: SettingsCategory) -> some View {
        Group {
            switch category {
            case .general:
                generalView
            case .privacy:
                privacyView
            case .about:
                aboutView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func pickExcludedApp() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return
        }

        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = true
            panel.canChooseFiles = true
            panel.resolvesAliases = true
            panel.treatsFilePackagesAsDirectories = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            panel.prompt = "Add"
            panel.message = "Select an app whose copied content Buffer should ignore."
            let pickerDelegate = AppBundleOpenPanelDelegate()
            panel.delegate = pickerDelegate

            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                guard let app = ExcludedApp(url: url) else { return }
                settings.addExcludedApp(app)
            }
        }
    }

}

private final class AppBundleOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
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

struct KeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (UInt16, HotkeyModifiers) -> Void

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: KeyRecorderView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class KeyRecorderView: NSView {
    var isRecording = false
    var onRecord: ((UInt16, HotkeyModifiers) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 56 || event.keyCode == 59 || event.keyCode == 58 || event.keyCode == 55 {
            return
        }

        let mods = HotkeyModifiers(
            shift: event.modifierFlags.contains(.shift),
            command: event.modifierFlags.contains(.command),
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )

        if mods.shift || mods.command || mods.option || mods.control {
            onRecord?(event.keyCode, mods)
        }
    }
}

private struct ExcludedAppRow: View {
    let app: ExcludedApp
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                Text(app.bundleIdentifier ?? app.bundlePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Remove app")
        }
        .padding(.vertical, 8)
    }
}

private extension ExcludedApp {
    init?(url: URL) {
        let bundle = Bundle(url: url)
        let bundlePath = url.path
        let bundleIdentifier = bundle?.bundleIdentifier
        let displayName =
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            url.deletingPathExtension().lastPathComponent

        guard !displayName.isEmpty else { return nil }
        self.init(name: displayName, bundleIdentifier: bundleIdentifier, bundlePath: bundlePath)
    }
}

class SettingsViewModel: ObservableObject {
    private static let defaultHotkeyModifiers = HotkeyModifiers(shift: true, command: true, option: false, control: false)
    private static let defaultHotkeyKeyCode: UInt16 = 9

    @Published var hotkeyModifiers: HotkeyModifiers
    @Published var hotkeyKeyCode: UInt16
    @Published var launchAtLogin: Bool
    @Published var historyLimit: HistoryLimit
    @Published var excludedApps: [ExcludedApp]

    private let defaults = UserDefaults.standard
    private let hotkeyModifiersKey = "hotkeyModifiers"
    private let hotkeyKeyCodeKey = "hotkeyKeyCode"

    init() {
        if let savedMods = defaults.array(forKey: hotkeyModifiersKey) as? [String] {
            self.hotkeyModifiers = HotkeyModifiers(from: savedMods)
        } else {
            self.hotkeyModifiers = Self.defaultHotkeyModifiers
        }

        let savedKeyCode = defaults.integer(forKey: hotkeyKeyCodeKey)
        self.hotkeyKeyCode = savedKeyCode > 0 ? UInt16(savedKeyCode) : Self.defaultHotkeyKeyCode
        self.launchAtLogin = SettingsManager.shared.launchAtLogin

        let rawLimit = defaults.integer(forKey: "historyLimit")
        self.historyLimit = HistoryLimit(rawValue: rawLimit) ?? .essential
        self.excludedApps = SettingsManager.shared.excludedApps
    }

    func save() {
        defaults.set(hotkeyModifiers.toArray(), forKey: hotkeyModifiersKey)
        defaults.set(Int(hotkeyKeyCode), forKey: hotkeyKeyCodeKey)
        defaults.set(historyLimit.rawValue, forKey: "historyLimit")

        SettingsManager.shared.hotkeyModifiers = hotkeyModifiers
        SettingsManager.shared.hotkeyKeyCode = hotkeyKeyCode
        SettingsManager.shared.historyLimit = historyLimit
        SettingsManager.shared.excludedApps = excludedApps
        SettingsManager.shared.save()

        NotificationCenter.default.post(name: .bufferHotkeyChanged, object: nil)
        NotificationCenter.default.post(name: .bufferHistoryLimitChanged, object: nil)
    }

    func restoreDefaultHotkey() {
        hotkeyModifiers = Self.defaultHotkeyModifiers
        hotkeyKeyCode = Self.defaultHotkeyKeyCode
        save()
    }

    func addExcludedApp(_ app: ExcludedApp) {
        guard !excludedApps.contains(where: { $0.id == app.id }) else { return }
        excludedApps.append(app)
        excludedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    func removeExcludedApp(_ app: ExcludedApp) {
        excludedApps.removeAll { $0.id == app.id }
        save()
    }
}
