import SwiftUI
import AppKit

@MainActor
struct SettingsView: View {
    let onCategoryTitleChange: (String) -> Void

    @ObservedObject private var settings: SettingsManager

    @State private var selectedCategory: SettingsCategory? = nil
    @State private var detailRefreshToken = 0
    @State private var didPerformInitialNavigationRefresh = false

    @State private var isRecording = false
    @State private var showingTrimAlert = false
    @State private var pendingTier: HistoryLimit?

    private let about = AppMetadata.current

    private var activeCategory: SettingsCategory {
        selectedCategory ?? .general
    }

    private var detailIdentity: String {
        "\(activeCategory.title)-\(detailRefreshToken)"
    }

    init(settings: SettingsManager, onCategoryTitleChange: @escaping (String) -> Void = { _ in }) {
        self._settings = ObservedObject(wrappedValue: settings)
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
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                toggleNativeSidebar()
                            } label: {
                                Label("Toggle Sidebar", systemImage: "sidebar.left")
                            }
                            .help("Toggle Sidebar")
                        }
                    }
            }
            .id(detailIdentity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 520)
        .task {
            await performInitialNavigationRefreshIfNeeded()
        }
        .onChange(of: selectedCategory) { _ in
            publishActiveCategoryTitle()
        }
        .alert("Reduce History Limit?", isPresented: $showingTrimAlert) {
            Button("Cancel", role: .cancel) { }

            Button("Reduce & Delete", role: .destructive) {
                if let tier = pendingTier {
                    settings.setHistoryLimit(tier)
                }
            }
        } message: {
            Text("This will permanently delete your oldest unpinned items to fit the new size. This action cannot be undone.")
        }
        .background(
            KeyRecorder(isRecording: $isRecording) { keyCode, modifiers in
                settings.setHotkey(keyCode: keyCode, modifiers: modifiers)
                isRecording = false
            }
        )
    }

    @ViewBuilder
    private func detailView(for category: SettingsCategory) -> some View {
        Group {
            switch category {
            case .general:
                SettingsGeneralView(
                    settings: settings,
                    isRecording: $isRecording,
                    showingTrimAlert: $showingTrimAlert,
                    pendingTier: $pendingTier
                )

            case .privacy:
                SettingsPrivacyView(
                    settings: settings,
                    onPickExcludedApp: pickExcludedApp
                )

            case .about:
                SettingsAboutView(about: about)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func performInitialNavigationRefreshIfNeeded() async {
        guard !didPerformInitialNavigationRefresh else {
            return
        }

        didPerformInitialNavigationRefresh = true

        await Task.yield()

        if selectedCategory == nil {
            selectedCategory = .general
        }

        detailRefreshToken += 1
        publishActiveCategoryTitle()
    }

    private func publishActiveCategoryTitle() {
        let title = activeCategory.title

        Task { @MainActor in
            await Task.yield()
            onCategoryTitleChange(title)
        }
    }

    private func toggleNativeSidebar() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return
        }

        let handledByResponder = window.firstResponder?
            .tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil) ?? false

        if !handledByResponder {
            NSApp.sendAction(
                #selector(NSSplitViewController.toggleSidebar(_:)),
                to: nil,
                from: nil
            )
        }
    }

    private func pickExcludedApp() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return
        }

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
