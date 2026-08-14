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

    var blocksPasteAttempt: Bool {
        isPasteInProgress || failure != nil
    }

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
protocol HistoryPasteCoordinatorDelegate: AnyObject {
    func pasteCoordinatorPresentFailure(_ failure: HistoryPasteFailurePresentation)
    func pasteCoordinatorDidDismissFailure()
    func pasteCoordinatorWillOrderOutForPaste()
    func pasteCoordinatorWillOpenPermissionSettings()
    func pasteCoordinatorShouldRestorePanel()
    func pasteCoordinatorDidCommitPaste()
}

/// Owns the complete copy/paste state machine. The window controller only
/// performs presentation transitions requested through the delegate.
@MainActor
final class HistoryPasteCoordinator {
    let state = HistoryPasteStateController()

    weak var delegate: (any HistoryPasteCoordinatorDelegate)?

    private let pasteController: any PasteControlling
    private let suppressCapturedChange: @MainActor (PasteboardWriteReceipt) -> Void
    private let openPermissionSettings: @MainActor () -> Void
    private var target: ApplicationTarget?
    private var activePlan: PastePlan?
    private var task: Task<Void, Never>?
    private var generation: UInt = 0

    init(
        pasteController: any PasteControlling,
        suppressCapturedChange: @escaping @MainActor (PasteboardWriteReceipt) -> Void,
        openPermissionSettings: @escaping @MainActor () -> Void =
            HistoryPasteCoordinator.openAccessibilitySettings
    ) {
        self.pasteController = pasteController
        self.suppressCapturedChange = suppressCapturedChange
        self.openPermissionSettings = openPermissionSettings
    }

    deinit {
        task?.cancel()
    }

    func beginSession(target: ApplicationTarget?) {
        cancelSession(discardPlan: true)
        self.target = target
    }

    func cancelSession(discardPlan: Bool) {
        let wasPresentingFailure = state.failure != nil
        generation &+= 1
        task?.cancel()
        task = nil
        pasteController.cancelPaste()

        if discardPlan {
            discardActivePlan()
        }
        state.finish()
        if wasPresentingFailure {
            delegate?.pasteCoordinatorDidDismissFailure()
        }
    }

    func copyToClipboard(_ items: [ClipboardItem]) async -> Bool {
        do {
            let receipt = try await pasteController.copyToClipboard(items)
            guard !Task.isCancelled else { return false }
            suppressCapturedChange(receipt)
            return true
        } catch is CancellationError {
            return false
        } catch {
            presentFailure(
                title: String(localized: "Copy Failed"),
                message: error.localizedDescription,
                recovery: .cancelOnly
            )
            return false
        }
    }

    func restoreTargetFocus() {
        guard let target, !target.isTerminated() else { return }
        target.activate()
    }

    func paste(_ items: [ClipboardItem]) {
        guard !items.isEmpty, !state.blocksPasteAttempt else { return }

        discardActivePlan()
        startTask()
        state.begin()
        let currentGeneration = generation

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let plan = try await pasteController.preparePastePlan(for: items)
                guard isCurrent(currentGeneration) else {
                    pasteController.discardPastePlan(plan)
                    return
                }
                activePlan = plan
                task = nil
                execute(plan, generation: currentGeneration)
            } catch is CancellationError {
                finishCancelledPreparation(generation: currentGeneration)
            } catch {
                guard isCurrent(currentGeneration) else { return }
                task = nil
                presentFailure(
                    title: String(localized: "Paste Failed"),
                    message: error.localizedDescription,
                    recovery: .cancelOnly
                )
            }
        }
    }

    func retry() {
        guard let activePlan else { return }
        state.clearFailure()
        startTask()
        execute(activePlan, generation: generation)
    }

    func dismissFailure() {
        let wasPresentingFailure = state.failure != nil
        discardActivePlan()
        state.finish()
        if wasPresentingFailure {
            delegate?.pasteCoordinatorDidDismissFailure()
        }
    }

    func requestPermission() {
        discardActivePlan()
        state.finish()
        delegate?.pasteCoordinatorWillOpenPermissionSettings()
        pasteController.requestPostEventAccess()
        openPermissionSettings()
    }

    private func execute(_ plan: PastePlan, generation: UInt) {
        guard let target else {
            presentFailure(
                title: String(localized: "No Paste Destination"),
                message: PasteFailure.missingDestination.localizedDescription,
                recovery: .cancelOnly
            )
            return
        }
        guard pasteController.hasPostEventAccess else {
            presentFailure(
                title: String(localized: "Permission Required"),
                message: PasteFailure.eventPermissionDenied.localizedDescription,
                recovery: .requestPermission
            )
            return
        }

        state.begin()
        delegate?.pasteCoordinatorWillOrderOutForPaste()
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await pasteController.executePaste(
                plan,
                target: target,
                suppressCapture: suppressCapturedChange
            )
            guard isCurrent(generation) else { return }
            handle(outcome, executedPlan: plan)
        }
    }

    private func handle(_ outcome: PasteOutcome, executedPlan: PastePlan) {
        task = nil

        switch outcome {
        case .success:
            pasteController.completePastePlan(executedPlan)
            activePlan = nil
            state.finish()
            delegate?.pasteCoordinatorDidCommitPaste()

        case .cancelled:
            state.finish()

        case .failure(let failure, let remainingPlan, let completedStepCount):
            activePlan = remainingPlan
            delegate?.pasteCoordinatorShouldRestorePanel()
            let partialPrefix =
                completedStepCount > 0
                ? String(localized: "The text was pasted, but the remaining images were not. ")
                : ""
            presentFailure(
                title: String(
                    localized: completedStepCount > 0
                        ? "Paste Partially Completed"
                        : "Paste Failed"
                ),
                message: partialPrefix + failure.localizedDescription,
                recovery: failure == .eventPermissionDenied ? .requestPermission : .retry
            )
        }
    }

    private func startTask() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    private func finishCancelledPreparation(generation: UInt) {
        guard isCurrent(generation) else { return }
        task = nil
        state.finish()
    }

    private func isCurrent(_ generation: UInt) -> Bool {
        !Task.isCancelled && self.generation == generation
    }

    private func discardActivePlan() {
        guard let activePlan else { return }
        pasteController.discardPastePlan(activePlan)
        self.activePlan = nil
    }

    private func presentFailure(
        title: String,
        message: String,
        recovery: HistoryPasteFailurePresentation.Recovery
    ) {
        let failure = HistoryPasteFailurePresentation(
            title: title,
            message: message,
            recovery: recovery
        )
        state.fail(failure)
        delegate?.pasteCoordinatorPresentFailure(failure)
    }

    static func openAccessibilitySettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class HistoryPanel: NSPanel {
    var onClickOutside: (() -> Void)?
    var dismissesWhenResigningKey = true
    private var surfaceCornerRadius = CGFloat.zero

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect, allowsResizing: Bool = false) {
        // Window-manager exclusion depends on these structural traits. Hiding the
        // controls of a titled panel still exposes an accessibility close button.
        var panelStyle: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if allowsResizing {
            panelStyle.insert(.resizable)
        }

        super.init(
            contentRect: contentRect,
            styleMask: panelStyle,
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

    func updateRoundedSurface(cornerRadius: CGFloat) {
        surfaceCornerRadius = cornerRadius
        applyRoundedSurface()
    }

    override var contentView: NSView? {
        didSet {
            applyRoundedSurface()
        }
    }

    override func resignKey() {
        super.resignKey()

        if !dismissesWhenResigningKey || attachedSheet != nil || NSApp.modalWindow?.parent == self {
            return
        }

        onClickOutside?()
    }

    private func applyRoundedSurface() {
        guard surfaceCornerRadius > 0 else { return }

        for view in [contentView, contentView?.superview].compactMap({ $0 }) {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.cornerRadius = surfaceCornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
            view.layer?.allowsEdgeAntialiasing = true
        }
    }
}

@MainActor
final class HistoryWindowController: NSWindowController, HistoryPasteCoordinatorDelegate {
    private let store: ClipboardStore
    private let settingsManager: SettingsManager
    private let activeApplicationProvider: ActiveApplicationProviding
    private let pasteController: PasteControlling
    private let suppressCapturedChange: @MainActor (PasteboardWriteReceipt) -> Void
    private let panelConfigurator: HistoryPanelConfigurator
    private let itemAssetProvider: ClipboardItemAssetProvider
    private let listAssetPrewarmer: ClipboardListAssetPrewarmer
    private let keyboardScrollRouter = HistoryKeyboardScrollRouter()
    private let openAnimator = HistoryWindowOpenAnimator()
    private let scrollRestorationCoordinator = HistoryListScrollRestorationCoordinator()
    private lazy var pasteCoordinator: HistoryPasteCoordinator = {
        let coordinator = HistoryPasteCoordinator(
            pasteController: pasteController,
            suppressCapturedChange: suppressCapturedChange
        )
        coordinator.delegate = self
        return coordinator
    }()
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
        windowConfiguration: HistoryWindowConfiguration = .standard,
        suppressCapturedChange: @escaping @MainActor (PasteboardWriteReceipt) -> Void
    ) {
        self.store = store
        self.settingsManager = settingsManager
        self.activeApplicationProvider = activeApplicationProvider
        self.pasteController = pasteController
        self.suppressCapturedChange = suppressCapturedChange
        self.panelConfigurator = HistoryPanelConfigurator(configuration: windowConfiguration)
        let itemAssetProvider = ClipboardItemAssetProvider(
            store: store,
            settings: settingsManager
        )
        self.itemAssetProvider = itemAssetProvider
        self.listAssetPrewarmer = ClipboardListAssetPrewarmer(assetProvider: itemAssetProvider)
        self.viewModel = HistoryViewModel(
            store: store,
            settingsManager: settingsManager,
            ocrService: ocrService,
            assetProvider: itemAssetProvider,
            keyboardScrollRouter: keyboardScrollRouter
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
        pasteCoordinator.beginSession(
            target: pasteController.applicationTarget(
                for: activeApplicationProvider.currentApplication
            )
        )
        historyPanel?.dismissesWhenResigningKey = true
        focusSearchOnNextOpen = focusSearch
        suppressQuickPasteUntilModifiersReleasedOnNextOpen = suppressQuickPasteUntilModifiersReleased

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
        pasteCoordinator.cancelSession(discardPlan: true)
        if let window, let attachedSheet = window.attachedSheet {
            window.endSheet(attachedSheet)
        }
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
            pasteState: pasteCoordinator.state,
            contentReader: store,
            itemAssetProvider: itemAssetProvider,
            listAssetPrewarmer: listAssetPrewarmer,
            keyboardScrollRouter: keyboardScrollRouter,
            onCopy: { [weak self] items in
                guard let self else { return false }
                return await self.pasteCoordinator.copyToClipboard(items)
            },
            onPaste: { [weak self] items in
                self?.pasteCoordinator.paste(items)
            },
            presentingWindow: { [weak self] in self?.window },
            onScrollOffsetProviderChanged: { [weak self] provider in
                self?.setListScrollOffsetProvider(provider)
            },
            onScrollOffsetRestorerChanged: { [weak self] restorer in
                self?.setListScrollOffsetRestorer(restorer)
            },
            onDismiss: { [weak self] in
                self?.close()
            },
            onRestoreFocus: { [weak self] in
                self?.pasteCoordinator.restoreTargetFocus()
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
        historyPanel?.dismissesWhenResigningKey = pasteCoordinator.state.failure == nil

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

    func pasteCoordinatorWillOpenPermissionSettings() {
        historyPanel?.dismissesWhenResigningKey = false
        openAnimator.cancelAnimations(for: window)
        scrollRestorationCoordinator.captureCurrentOffset()
        window?.orderOut(nil)
        historyPanel?.dismissesWhenResigningKey = true
    }

    func pasteCoordinatorPresentFailure(_ failure: HistoryPasteFailurePresentation) {
        historyPanel?.dismissesWhenResigningKey = false
        guard let window else {
            pasteCoordinator.dismissFailure()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = failure.title
        alert.informativeText = failure.message

        switch failure.recovery {
        case .cancelOnly:
            alert.addButton(withTitle: String(localized: "OK"))
        case .retry:
            alert.addButton(withTitle: String(localized: "Retry"))
            alert.addButton(withTitle: String(localized: "Cancel"))
        case .requestPermission:
            alert.addButton(withTitle: String(localized: "Open System Settings"))
            alert.addButton(withTitle: String(localized: "Cancel"))
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            self?.handlePasteFailureResponse(response, failure: failure)
        }

        if window.attachedSheet == nil,
            pasteCoordinator.state.failure?.id == failure.id
        {
            pasteCoordinator.dismissFailure()
        }
    }

    func pasteCoordinatorDidDismissFailure() {
        historyPanel?.dismissesWhenResigningKey = true
    }

    private func handlePasteFailureResponse(
        _ response: NSApplication.ModalResponse,
        failure: HistoryPasteFailurePresentation
    ) {
        guard pasteCoordinator.state.failure?.id == failure.id else { return }

        guard response == .alertFirstButtonReturn else {
            pasteCoordinator.dismissFailure()
            return
        }

        switch failure.recovery {
        case .cancelOnly:
            pasteCoordinator.dismissFailure()
        case .retry:
            pasteCoordinator.retry()
        case .requestPermission:
            pasteCoordinator.requestPermission()
        }
    }

    func pasteCoordinatorWillOrderOutForPaste() {
        historyPanel?.dismissesWhenResigningKey = false
        openAnimator.cancelAnimations(for: window)
        scrollRestorationCoordinator.captureCurrentOffset()
        window?.orderOut(nil)
    }

    func pasteCoordinatorShouldRestorePanel() {
        guard let window else { return }
        historyPanel?.dismissesWhenResigningKey = true
        shouldIgnoreNextDidBecomeKeyOpenHandling = true
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        window.makeKeyAndOrderFront(nil)
    }

    func pasteCoordinatorDidCommitPaste() {
        historyPanel?.dismissesWhenResigningKey = true
        viewModel.clearSearchAfterCommittedAction()
    }

    private var historyPanel: HistoryPanel? {
        window as? HistoryPanel
    }
}
