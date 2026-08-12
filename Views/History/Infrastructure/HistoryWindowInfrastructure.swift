import Cocoa
import SwiftUI

@MainActor
final class HistoryPanel: NSPanel {
    var onClickOutside: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        // Window-manager exclusion depends on these structural traits. Hiding the
        // controls of a titled panel still exposes an accessibility close button.
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func close() {
        orderOut(nil)
    }

    override func resignKey() {
        super.resignKey()

        if attachedSheet != nil || NSApp.modalWindow?.parent == self {
            return
        }

        onClickOutside?()
    }
}

@MainActor
final class HistoryWindowController: NSWindowController {
    private let store: ClipboardStore
    private let settingsManager: SettingsManager
    private let activeApplicationProvider: ActiveApplicationProviding
    private let pasteController: PasteControlling
    private let ignoreNextCapturedChange: @MainActor () -> Void
    private let panelConfigurator = HistoryPanelConfigurator()
    private let openAnimator = HistoryWindowOpenAnimator()
    private let scrollRestorationCoordinator = HistoryListScrollRestorationCoordinator()

    private var previousApp: NSRunningApplication?
    nonisolated(unsafe) private var keyObserver: NSObjectProtocol?

    private let viewModel: HistoryViewModel
    private var focusSearchOnNextOpen = true
    private var suppressQuickPasteUntilModifiersReleasedOnNextOpen = false
    private var shouldIgnoreNextDidBecomeKeyOpenHandling = false

    init(
        store: ClipboardStore,
        settingsManager: SettingsManager,
        activeApplicationProvider: ActiveApplicationProviding,
        pasteController: PasteControlling,
        ocrService: OCRServicing,
        ignoreNextCapturedChange: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.settingsManager = settingsManager
        self.activeApplicationProvider = activeApplicationProvider
        self.pasteController = pasteController
        self.ignoreNextCapturedChange = ignoreNextCapturedChange
        self.viewModel = HistoryViewModel(
            store: store,
            settingsManager: settingsManager,
            ocrService: ocrService
        )

        let panel = panelConfigurator.makePanel()

        super.init(window: panel)

        panel.onClickOutside = { [weak self] in
            self?.close()
        }

        setupPanel(panel)
        setupContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
        }
    }

    override func showWindow(_ sender: Any?) {
        showWindow(
            sender,
            focusSearch: true,
            activateApp: true,
            suppressQuickPasteUntilModifiersReleased: false
        )
    }

    func showWindow(
        _ sender: Any?,
        focusSearch: Bool,
        activateApp: Bool,
        suppressQuickPasteUntilModifiersReleased: Bool
    ) {
        focusSearchOnNextOpen = focusSearch
        suppressQuickPasteUntilModifiersReleasedOnNextOpen = suppressQuickPasteUntilModifiersReleased
        previousApp = activeApplicationProvider.currentApplication

        guard let window else {
            return
        }

        let presentation = openAnimator.beginPresentationCycle(for: window)

        window.center()

        shouldIgnoreNextDidBecomeKeyOpenHandling = true
        viewModel.handleWindowOpen(
            focusSearch: focusSearchOnNextOpen,
            suppressQuickPasteUntilModifiersReleased: suppressQuickPasteUntilModifiersReleasedOnNextOpen
        )

        super.showWindow(sender)

        if activateApp {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        }

        window.makeKeyAndOrderFront(nil)

        if settingsManager.historyWindowOpenBehavior == .keepLastSelection {
            scrollRestorationCoordinator.restoreIfNeeded(for: settingsManager.historyWindowOpenBehavior)
        }

        openAnimator.animateOpenIfNeeded(
            window: window,
            shouldAnimate: presentation.shouldAnimate,
            generation: presentation.generation
        )
    }

    override func close() {
        openAnimator.cancelAnimations(for: window)
        scrollRestorationCoordinator.captureCurrentOffset()
        window?.orderOut(nil)
    }

    private func setupPanel(_ panel: HistoryPanel) {
        keyObserver = panelConfigurator.configure(panel) { [weak self] in
            self?.handlePanelDidBecomeKey()
        }
    }

    private func setupContent() {
        let rootView = HistoryContentView(
            viewModel: viewModel,
            settings: settingsManager,
            store: store,
            onCopyToClipboard: { [weak self] item in
                self?.copyToClipboard(item)
            },
            onCopyMultipleToClipboard: { [weak self] items in
                self?.copyToClipboard(items)
            },
            onPaste: { [weak self] item in
                self?.pasteItem(item)
            },
            onPasteMultiple: { [weak self] items in
                self?.pasteMultiple(items)
            },
            onScrollOffsetProviderChanged: { [weak self] provider in
                self?.setListScrollOffsetProvider(provider)
            },
            onScrollOffsetRestorerChanged: { [weak self] restorer in
                self?.setListScrollOffsetRestorer(restorer)
            },
            onDismiss: { [weak self] in
                self?.close()
            }
        )

        let contentConfiguration = panelConfigurator.makeContentConfiguration(
            rootView: rootView,
            frame: window?.contentView?.bounds ?? .zero
        )

        openAnimator.setAnimatedContentView(contentConfiguration.animatedContentView)
        window?.contentView = contentConfiguration.containerView
    }

    private func handlePanelDidBecomeKey() {
        if shouldIgnoreNextDidBecomeKeyOpenHandling {
            shouldIgnoreNextDidBecomeKeyOpenHandling = false
            return
        }

        viewModel.handleWindowOpen(
            focusSearch: focusSearchOnNextOpen,
            suppressQuickPasteUntilModifiersReleased: suppressQuickPasteUntilModifiersReleasedOnNextOpen
        )

        if settingsManager.historyWindowOpenBehavior == .keepLastSelection {
            scrollRestorationCoordinator.restoreIfNeeded(for: settingsManager.historyWindowOpenBehavior)
        }
    }

    private func setListScrollOffsetProvider(_ provider: (() -> CGFloat)?) {
        scrollRestorationCoordinator.setOffsetProvider(provider)
    }

    private func setListScrollOffsetRestorer(_ restorer: ((CGFloat) -> Void)?) {
        scrollRestorationCoordinator.setOffsetRestorer(restorer)
    }

    private func copyToClipboard(_ item: ClipboardItem) {
        ignoreNextCapturedChange()
        pasteController.copyToClipboard(item)
    }

    private func copyToClipboard(_ items: [ClipboardItem]) {
        ignoreNextCapturedChange()
        pasteController.copyMultipleToClipboard(items)
    }

    private func pasteItem(_ item: ClipboardItem) {
        let appToRestore = previousApp

        close()

        pasteController.paste(
            item,
            previousApp: appToRestore,
            ignoreNextCapturedChange: ignoreNextCapturedChange
        )
    }

    private func pasteMultiple(_ items: [ClipboardItem]) {
        let appToRestore = previousApp

        close()

        pasteController.pasteMultiple(
            items,
            previousApp: appToRestore,
            ignoreNextCapturedChange: ignoreNextCapturedChange
        )
    }
}
