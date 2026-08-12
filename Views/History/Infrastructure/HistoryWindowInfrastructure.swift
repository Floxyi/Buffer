import Cocoa
import SwiftUI

struct HistoryPasteFailurePresentation: Identifiable, Equatable {
    enum Recovery: Equatable {
        case cancelOnly
        case retry
        case requestPermission
    }

    let id = UUID()
    let title: String
    let message: String
    let recovery: Recovery
}

@MainActor
final class HistoryPasteStateController: ObservableObject {
    @Published private(set) var isPasteInProgress = false
    @Published var failure: HistoryPasteFailurePresentation?

    func begin() {
        isPasteInProgress = true
        failure = nil
    }

    func finish() {
        isPasteInProgress = false
        failure = nil
    }

    func fail(_ failure: HistoryPasteFailurePresentation) {
        isPasteInProgress = false
        self.failure = failure
    }

    func clearFailure() {
        failure = nil
    }
}

@MainActor
final class HistoryPanel: NSPanel {
    var onClickOutside: (() -> Void)?
    var dismissesWhenResigningKey = true

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

        if !dismissesWhenResigningKey || attachedSheet != nil || NSApp.modalWindow?.parent == self {
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
    private let suppressCapturedChange: @MainActor (PasteboardWriteReceipt) -> Void
    private let panelConfigurator = HistoryPanelConfigurator()
    private let openAnimator = HistoryWindowOpenAnimator()
    private let scrollRestorationCoordinator = HistoryListScrollRestorationCoordinator()
    private let pasteStateController = HistoryPasteStateController()

    private var pasteTarget: ApplicationTarget?
    private var activePastePlan: PastePlan?
    private var pasteTask: Task<Void, Never>?
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
        suppressCapturedChange: @escaping @MainActor (PasteboardWriteReceipt) -> Void
    ) {
        self.store = store
        self.settingsManager = settingsManager
        self.activeApplicationProvider = activeApplicationProvider
        self.pasteController = pasteController
        self.suppressCapturedChange = suppressCapturedChange
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
        pasteTask?.cancel()
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
        cancelPasteSession(discardPlan: true)
        historyPanel?.dismissesWhenResigningKey = true
        focusSearchOnNextOpen = focusSearch
        suppressQuickPasteUntilModifiersReleasedOnNextOpen = suppressQuickPasteUntilModifiersReleased
        pasteTarget = pasteController.applicationTarget(for: activeApplicationProvider.currentApplication)

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
        cancelPasteSession(discardPlan: true)
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
            pasteState: pasteStateController,
            store: store,
            onCopyToClipboard: { [weak self] item in
                self?.copyToClipboard([item]) == true
            },
            onCopyMultipleToClipboard: { [weak self] items in
                self?.copyToClipboard(items) == true
            },
            onPaste: { [weak self] item in
                self?.pasteItems([item])
            },
            onPasteMultiple: { [weak self] items in
                self?.pasteItems(items)
            },
            onScrollOffsetProviderChanged: { [weak self] provider in
                self?.setListScrollOffsetProvider(provider)
            },
            onScrollOffsetRestorerChanged: { [weak self] restorer in
                self?.setListScrollOffsetRestorer(restorer)
            },
            onDismiss: { [weak self] in
                self?.close()
            },
            onRetryPaste: { [weak self] in self?.retryPaste() },
            onDismissPasteFailure: { [weak self] in self?.dismissPasteFailure() },
            onRequestPastePermission: { [weak self] in self?.requestPastePermission() }
        )

        let contentConfiguration = panelConfigurator.makeContentConfiguration(
            rootView: rootView,
            frame: window?.contentView?.bounds ?? .zero
        )

        openAnimator.setAnimatedContentView(contentConfiguration.animatedContentView)
        window?.contentView = contentConfiguration.containerView
    }

    private func handlePanelDidBecomeKey() {
        historyPanel?.dismissesWhenResigningKey = true

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

    private func copyToClipboard(_ items: [ClipboardItem]) -> Bool {
        do {
            let receipt = try pasteController.copyToClipboard(items)
            suppressCapturedChange(receipt)
            return true
        } catch {
            presentPasteFailure(
                title: "Copy Failed",
                message: error.localizedDescription,
                recovery: .cancelOnly
            )
            return false
        }
    }

    private func pasteItems(_ items: [ClipboardItem]) {
        guard !pasteStateController.isPasteInProgress else { return }

        if let activePastePlan {
            pasteController.discardPastePlan(activePastePlan)
            self.activePastePlan = nil
        }

        do {
            let plan = try pasteController.preparePastePlan(for: items)
            activePastePlan = plan
            startPaste(plan)
        } catch {
            presentPasteFailure(
                title: "Paste Failed",
                message: error.localizedDescription,
                recovery: .cancelOnly
            )
        }
    }

    private func startPaste(_ plan: PastePlan) {
        guard pasteTarget != nil else {
            presentPasteFailure(
                title: "No Paste Destination",
                message: PasteFailure.missingDestination.localizedDescription,
                recovery: .cancelOnly
            )
            return
        }
        guard pasteController.hasPostEventAccess else {
            presentPasteFailure(
                title: "Permission Required",
                message: PasteFailure.eventPermissionDenied.localizedDescription,
                recovery: .requestPermission
            )
            return
        }

        pasteStateController.begin()
        orderOutForPaste()
        pasteTask?.cancel()
        pasteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await pasteController.executePaste(
                plan,
                target: pasteTarget,
                suppressCapture: suppressCapturedChange
            )
            guard !Task.isCancelled else { return }
            handlePasteOutcome(outcome, executedPlan: plan)
        }
    }

    private func handlePasteOutcome(_ outcome: PasteOutcome, executedPlan: PastePlan) {
        pasteTask = nil

        switch outcome {
        case .success:
            historyPanel?.dismissesWhenResigningKey = true
            pasteController.completePastePlan(executedPlan)
            activePastePlan = nil
            pasteStateController.finish()
            viewModel.clearSearchAfterCommittedAction()

        case .cancelled:
            historyPanel?.dismissesWhenResigningKey = true
            pasteStateController.finish()

        case .failure(let failure, let remainingPlan, let completedStepCount):
            activePastePlan = remainingPlan
            restorePanelAfterPasteFailure()
            let partialPrefix =
                completedStepCount > 0
                ? "The text was pasted, but the remaining images were not. "
                : ""
            presentPasteFailure(
                title: completedStepCount > 0 ? "Paste Partially Completed" : "Paste Failed",
                message: partialPrefix + failure.localizedDescription,
                recovery: failure == .eventPermissionDenied ? .requestPermission : .retry
            )
        }
    }

    private func retryPaste() {
        guard let activePastePlan else { return }
        pasteStateController.clearFailure()
        startPaste(activePastePlan)
    }

    private func dismissPasteFailure() {
        if let activePastePlan {
            pasteController.discardPastePlan(activePastePlan)
        }
        activePastePlan = nil
        pasteStateController.finish()
    }

    private func requestPastePermission() {
        dismissPasteFailure()
        orderOutForPermissionSetup()

        pasteController.requestPostEventAccess()
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    private func orderOutForPermissionSetup() {
        historyPanel?.dismissesWhenResigningKey = false
        openAnimator.cancelAnimations(for: window)
        scrollRestorationCoordinator.captureCurrentOffset()
        window?.orderOut(nil)
        historyPanel?.dismissesWhenResigningKey = true
    }

    private func presentPasteFailure(
        title: String,
        message: String,
        recovery: HistoryPasteFailurePresentation.Recovery
    ) {
        pasteStateController.fail(
            HistoryPasteFailurePresentation(
                title: title,
                message: message,
                recovery: recovery
            )
        )
    }

    private func orderOutForPaste() {
        historyPanel?.dismissesWhenResigningKey = false
        openAnimator.cancelAnimations(for: window)
        scrollRestorationCoordinator.captureCurrentOffset()
        window?.orderOut(nil)
    }

    private func restorePanelAfterPasteFailure() {
        guard let window else { return }
        historyPanel?.dismissesWhenResigningKey = true
        shouldIgnoreNextDidBecomeKeyOpenHandling = true
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        window.makeKeyAndOrderFront(nil)
    }

    private func cancelPasteSession(discardPlan: Bool) {
        historyPanel?.dismissesWhenResigningKey = true
        pasteTask?.cancel()
        pasteTask = nil
        pasteController.cancelPaste()

        if discardPlan, let activePastePlan {
            pasteController.discardPastePlan(activePastePlan)
            self.activePastePlan = nil
        }
        pasteStateController.finish()
    }

    private var historyPanel: HistoryPanel? {
        window as? HistoryPanel
    }
}
