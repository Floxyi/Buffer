import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    let onCategoryTitleChange: (String) -> Void

    @ObservedObject private var settings: SettingsManager
    @ObservedObject private var store: ClipboardStore

    @State private var selectedCategory: SettingsCategory? = nil
    @State private var detailRefreshToken = 0
    @State private var didPerformInitialNavigationRefresh = false

    private let about = AppMetadata.current

    private var activeCategory: SettingsCategory {
        selectedCategory ?? .general
    }

    private var detailIdentity: String {
        "\(activeCategory.title)-\(detailRefreshToken)"
    }

    init(
        settings: SettingsManager,
        store: ClipboardStore,
        onCategoryTitleChange: @escaping (String) -> Void = { _ in }
    ) {
        self._settings = ObservedObject(wrappedValue: settings)
        self._store = ObservedObject(wrappedValue: store)
        self.onCategoryTitleChange = onCategoryTitleChange
    }

    var body: some View {
        NavigationSplitView {
            SettingsCategoryList(selectedCategory: $selectedCategory)
        } detail: {
            NavigationStack {
                detailView(for: activeCategory)
                    .navigationTitle(activeCategory.title)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            SettingsSidebarToggleButton(action: toggleNativeSidebar)
                        }
                    }
            }
            .id(detailIdentity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 560)
        .task {
            await performInitialNavigationRefreshIfNeeded()
        }
        .onChange(of: selectedCategory) { _ in
            publishActiveCategoryTitle()
        }
    }

    @ViewBuilder
    private func detailView(for category: SettingsCategory) -> some View {
        Group {
            switch category {
            case .general:
                SettingsGeneralView(settings: settings, store: store)
            case .behaviour:
                SettingsBehaviourView(settings: settings)
            case .privacy:
                SettingsPrivacyView(settings: settings)
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
}

private struct SettingsCategoryList: View {
    @Binding var selectedCategory: SettingsCategory?

    var body: some View {
        List(SettingsCategory.allCases, selection: $selectedCategory) { category in
            Label(category.title, systemImage: category.icon)
                .tag(category)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        .listStyle(.sidebar)
    }
}

private struct SettingsSidebarToggleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Toggle Sidebar", systemImage: "sidebar.left")
        }
        .help("Toggle Sidebar")
    }
}
