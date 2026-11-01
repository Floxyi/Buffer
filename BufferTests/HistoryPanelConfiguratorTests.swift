import SwiftUI
import XCTest

@testable import Buffer

@MainActor
final class HistoryPanelConfiguratorTests: XCTestCase {
    private var retainedSplitCoordinators: [HistoryPaneSplitCoordinator] = []

    func testMakePanelCreatesVisuallyBorderlessNonactivatingResizablePopup() {
        let panel = makeEphemeralConfigurator().makePanel()

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(panel.styleMask.contains(.closable))
        XCTAssertFalse(panel.styleMask.contains(.miniaturizable))
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertEqual(panel.titleVisibility, .hidden)
        XCTAssertTrue(panel.standardWindowButton(.closeButton)?.isHidden == true)
        XCTAssertTrue(panel.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        XCTAssertTrue(panel.standardWindowButton(.zoomButton)?.isHidden == true)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isReleasedWhenClosed)
    }

    func testConfigureAppliesPanelAppearanceAndSizing() {
        let configurator = makeEphemeralConfigurator()
        let panel = configurator.makePanel()
        configurator.configure(panel)

        XCTAssertEqual(panel.level, .popUpMenu)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.isExcludedFromWindowsMenu)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.transient))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
        XCTAssertEqual(panel.contentMinSize, HistoryWindowStyle.minimumContentSize)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.isMovable)
        XCTAssertFalse(panel.isMovableByWindowBackground)
        XCTAssertTrue(panel.hasShadow)
        XCTAssertEqual(panel.contentView?.layer?.cornerRadius, HistoryWindowStyle.panelCornerRadius)
        XCTAssertTrue(panel.contentView?.layer?.masksToBounds == true)
    }

    func testConfigurationCanCreateFixedSizePanel() {
        let contentSize = NSSize(width: 720, height: 460)
        let configuration = HistoryWindowConfiguration(
            initialContentSize: contentSize,
            minimumContentSize: contentSize,
            maximumContentSize: contentSize,
            allowsResizing: false,
            frameAutosaveName: nil,
            paneSplitConfiguration: .ephemeral
        )
        let configurator = HistoryPanelConfigurator(configuration: configuration)
        let panel = configurator.makePanel()
        configurator.configure(panel)

        XCTAssertFalse(panel.styleMask.contains(.resizable))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertEqual(panel.contentMinSize, contentSize)
        XCTAssertEqual(panel.contentMaxSize, contentSize)
    }

    func testConfigurationControlsSizingAndWindowCapabilities() {
        let minimumSize = NSSize(width: 640, height: 400)
        let maximumSize = NSSize(width: 1_200, height: 900)
        let configurator = HistoryPanelConfigurator(
            configuration: HistoryWindowConfiguration(
                initialContentSize: NSSize(width: 900, height: 600),
                minimumContentSize: minimumSize,
                maximumContentSize: maximumSize,
                allowsResizing: true,
                allowsMoving: true,
                frameAutosaveName: nil,
                paneSplitConfiguration: .ephemeral,
                appearance: BufferAppearanceConfiguration(
                    mode: .dark,
                    surfaceStyle: .opaque
                )
            )
        )
        let panel = configurator.makePanel()
        configurator.configure(panel)

        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertEqual(panel.contentMinSize, minimumSize)
        XCTAssertEqual(panel.contentMaxSize, maximumSize)
        XCTAssertTrue(panel.isMovable)
        XCTAssertTrue(panel.isMovableByWindowBackground)
        XCTAssertEqual(panel.appearance?.name, .darkAqua)
    }

    func testCloseOrdersPanelOutForReuse() {
        let panel = makeEphemeralConfigurator().makePanel()
        panel.orderFront(nil)
        XCTAssertTrue(panel.isVisible)

        panel.close()

        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.isReleasedWhenClosed)
    }

    func testProgrammaticPasteDismissalDoesNotTriggerClickOutsideHandling() {
        let panel = makeEphemeralConfigurator().makePanel()
        var clickOutsideCount = 0
        panel.onClickOutside = { clickOutsideCount += 1 }
        panel.dismissesWhenResigningKey = false

        panel.resignKey()

        XCTAssertEqual(clickOutsideCount, 0)
    }

    func testNativeAlertAttachesToVisuallyBorderlessHistoryPanel() {
        let configurator = makeEphemeralConfigurator()
        let panel = configurator.makePanel()
        configurator.configure(panel)
        panel.orderFront(nil)
        defer { panel.close() }

        let alert = NSAlert()
        alert.messageText = "Permission Required"
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: panel)

        let attachedSheet = panel.attachedSheet
        XCTAssertNotNil(attachedSheet)
        XCTAssertTrue(panel.contentView?.layer?.masksToBounds == true)
        XCTAssertTrue(panel.contentView?.superview?.layer?.masksToBounds == true)
        if let attachedSheet {
            panel.endSheet(attachedSheet)
        }
    }

    func testReplacingPanelContentPreservesRoundedSurfaceForDialogs() {
        let configurator = makeEphemeralConfigurator()
        let panel = configurator.makePanel()
        configurator.configure(panel)

        let replacement = NSView(
            frame: NSRect(origin: .zero, size: HistoryWindowStyle.initialContentSize)
        )
        panel.contentView = replacement

        XCTAssertEqual(replacement.layer?.cornerRadius, HistoryWindowStyle.panelCornerRadius)
        XCTAssertEqual(replacement.layer?.cornerCurve, .continuous)
        XCTAssertTrue(replacement.layer?.masksToBounds == true)
        XCTAssertTrue(replacement.layer?.allowsEdgeAntialiasing == true)
    }

    func testMakeContentConfigurationReturnsAnimatedEffectContainer() {
        let configurator = makeEphemeralConfigurator()
        let configuration = configurator.makeContentConfiguration(
            rootView: Color.clear,
            frame: NSRect(x: 0, y: 0, width: 120, height: 80)
        )

        XCTAssertEqual(configuration.containerView.subviews.count, 1)
        XCTAssertTrue(configuration.containerView.subviews[0] === configuration.animatedContentView)
        XCTAssertTrue(
            configuration.hostedContentView.isDescendant(
                of: configuration.animatedContentView
            )
        )
        if #available(macOS 26.0, *) {
            XCTAssertTrue(configuration.animatedContentView is BufferLiquidGlassEffectView)
        }
        XCTAssertEqual(
            configuration.containerView.layer?.cornerRadius,
            HistoryWindowStyle.panelCornerRadius
        )
        XCTAssertTrue(configuration.containerView.layer?.masksToBounds == true)
    }

    func testClassicMaterialUsesPreviousFrostedEffectView() {
        var configuration = HistoryWindowConfiguration.ephemeral
        configuration.appearance.historyWindowMaterial = .classic
        let contentConfiguration = HistoryPanelConfigurator(configuration: configuration)
            .makeContentConfiguration(
                rootView: Color.clear,
                frame: NSRect(x: 0, y: 0, width: 120, height: 80)
            )

        XCTAssertTrue(
            contentConfiguration.animatedContentView is BufferFrostedGlassEffectView
        )
    }

    func testWindowGeometryClampsInvalidAndOutOfRangeSizes() {
        let fallback = NSSize(width: 800, height: 500)
        let minimum = NSSize(width: 680, height: 420)
        let maximum = NSSize(width: 1_200, height: 760)

        XCTAssertEqual(
            HistoryWindowGeometry.clampedContentSize(
                NSSize(width: 500, height: 300),
                fallbackSize: fallback,
                minimumSize: minimum,
                maximumSize: maximum
            ),
            minimum
        )
        XCTAssertEqual(
            HistoryWindowGeometry.clampedContentSize(
                NSSize(width: 1_500, height: 900),
                fallbackSize: fallback,
                minimumSize: minimum,
                maximumSize: maximum
            ),
            maximum
        )
        XCTAssertEqual(
            HistoryWindowGeometry.clampedContentSize(
                NSSize(width: CGFloat.nan, height: CGFloat.infinity),
                fallbackSize: fallback,
                minimumSize: minimum,
                maximumSize: maximum
            ),
            fallback
        )
    }

    func testFrameAutosaveRestoresContentSize() {
        let autosaveName = NSWindow.FrameAutosaveName("BufferTests.\(#function).\(UUID())")
        defer { NSWindow.removeFrame(usingName: autosaveName) }

        var configuration = HistoryWindowConfiguration.ephemeral
        configuration.frameAutosaveName = autosaveName
        let firstConfigurator = HistoryPanelConfigurator(configuration: configuration)
        let firstPanel = firstConfigurator.makePanel()
        firstConfigurator.configure(firstPanel)
        firstPanel.setContentSize(NSSize(width: 760, height: 460))
        firstPanel.saveFrame(usingName: autosaveName)

        let secondConfigurator = HistoryPanelConfigurator(configuration: configuration)
        let secondPanel = secondConfigurator.makePanel()
        secondConfigurator.configure(secondPanel)

        XCTAssertEqual(
            secondPanel.contentRect(forFrameRect: secondPanel.frame).size,
            NSSize(width: 760, height: 460)
        )
    }

    func testPaneSplitEnforcesNativeLayoutContract() {
        let configuration = HistoryPaneSplitConfiguration.ephemeral
        let splitView = HistoryPaneNativeSplitView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 300)
        )
        let coordinator = HistoryPaneSplitCoordinator(configuration: configuration)
        coordinator.install(
            in: splitView,
            leading: AnyView(Color.clear),
            trailing: AnyView(Color.clear)
        )
        splitView.frame = NSRect(x: 0, y: 0, width: 800, height: 300)
        splitView.adjustSubviews()

        XCTAssertTrue(splitView.isVertical)
        XCTAssertEqual(splitView.dividerStyle, .thin)
        XCTAssertEqual(splitView.dividerThickness, 1)
        XCTAssertEqual(splitView.arrangedSubviews.count, 2)
        XCTAssertFalse(
            coordinator.splitView(splitView, canCollapseSubview: splitView.arrangedSubviews[0])
        )
        XCTAssertFalse(coordinator.splitView(splitView, shouldHideDividerAt: 0))
        XCTAssertGreaterThan(
            splitView.holdingPriorityForSubview(at: 0),
            splitView.holdingPriorityForSubview(at: 1)
        )
        XCTAssertEqual(
            coordinator.splitView(
                splitView,
                constrainSplitPosition: 100,
                ofSubviewAt: 0
            ),
            configuration.minimumListWidth
        )
        XCTAssertEqual(
            coordinator.splitView(
                splitView,
                constrainSplitPosition: 700,
                ofSubviewAt: 0
            ),
            800 - splitView.dividerThickness - configuration.minimumDetailWidth
        )
        XCTAssertEqual(
            coordinator.splitView(splitView, additionalEffectiveRectOfDividerAt: 0).width,
            configuration.dividerHitWidth
        )
        XCTAssertEqual(splitView.dividerHitWidth, configuration.dividerHitWidth)
        XCTAssertEqual(
            splitView.dividerInteractionRect(at: 0)?.width,
            configuration.dividerHitWidth
        )

        splitView.updateTrackingAreas()
        let cursorTrackingArea = splitView.trackingAreas.first {
            $0.owner === splitView && $0.options.contains(.cursorUpdate)
        }
        XCTAssertEqual(cursorTrackingArea?.rect.width, configuration.dividerHitWidth)
        XCTAssertTrue(cursorTrackingArea?.options.contains(.activeAlways) == true)
    }

    func testPaneContentUpdatesDoNotResetDividerPosition() {
        let configuration = HistoryPaneSplitConfiguration.ephemeral
        let splitView = HistoryPaneNativeSplitView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 300)
        )
        let coordinator = HistoryPaneSplitCoordinator(configuration: configuration)
        coordinator.install(
            in: splitView,
            leading: AnyView(Text("Before")),
            trailing: AnyView(Color.clear)
        )
        splitView.frame = NSRect(x: 0, y: 0, width: 800, height: 300)
        splitView.adjustSubviews()
        splitView.setPosition(340, ofDividerAt: 0)
        let dividerPosition = splitView.arrangedSubviews[0].frame.maxX

        coordinator.update(
            configuration: configuration,
            leading: AnyView(Text("After")),
            trailing: AnyView(Text("Updated")),
            in: splitView
        )

        XCTAssertEqual(splitView.arrangedSubviews[0].frame.maxX, dividerPosition)
    }

    func testPaneParentUpdatesKeepLeadingScrollViewAndViewportAlive() throws {
        let configuration = HistoryPaneSplitConfiguration.ephemeral
        let splitView = HistoryPaneNativeSplitView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 420)
        )
        let coordinator = HistoryPaneSplitCoordinator(configuration: configuration)
        let probe = HistoryPaneScrollProbe()
        coordinator.install(
            in: splitView,
            leading: AnyView(HistoryPaneScrollProbeView(probe: probe)),
            trailing: AnyView(Text("Before"))
        )
        splitView.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(probe.scrollView)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 320))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        coordinator.update(
            configuration: configuration,
            leading: AnyView(Text("An unrelated parent update")),
            trailing: AnyView(Text("After")),
            in: splitView
        )
        splitView.layoutSubtreeIfNeeded()

        XCTAssertTrue(scrollView.isDescendant(of: try XCTUnwrap(coordinator.leadingHostingView)))
        XCTAssertEqual(scrollView.contentView.bounds.minY, 320)
    }

    func testPaneLayoutHonorsMinimumWidthsAndKeepsListWidthWhileGrowing() {
        let configuration = HistoryPaneSplitConfiguration.ephemeral
        let splitView = HistoryPaneNativeSplitView(
            frame: NSRect(x: 0, y: 0, width: 680, height: 420)
        )
        let coordinator = HistoryPaneSplitCoordinator(configuration: configuration)
        coordinator.install(
            in: splitView,
            leading: AnyView(Color.clear),
            trailing: AnyView(Color.clear)
        )
        splitView.setPosition(configuration.preferredListWidth, ofDividerAt: 0)

        for size in [
            NSSize(width: 680, height: 420),
            NSSize(width: 800, height: 500),
            NSSize(width: 1_200, height: 760),
        ] {
            splitView.frame = NSRect(origin: .zero, size: size)

            let listFrame = splitView.arrangedSubviews[0].frame
            let detailFrame = splitView.arrangedSubviews[1].frame
            XCTAssertGreaterThanOrEqual(listFrame.width, configuration.minimumListWidth)
            XCTAssertGreaterThanOrEqual(detailFrame.width, configuration.minimumDetailWidth)
            XCTAssertGreaterThanOrEqual(listFrame.minX, splitView.bounds.minX)
            XCTAssertLessThanOrEqual(detailFrame.maxX, splitView.bounds.maxX)
            XCTAssertEqual(listFrame.width, configuration.preferredListWidth)
        }
    }

    func testPaneUsesPreferredListWidthDuringInitialSwiftUILayout() {
        let configuration = HistoryPaneSplitConfiguration.ephemeral
        let splitView = HistoryPaneNativeSplitView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: configuration.preferredListWidth
                    + configuration.minimumDetailWidth + 1,
                height: 1
            )
        )
        let coordinator = HistoryPaneSplitCoordinator(configuration: configuration)
        retainedSplitCoordinators.append(coordinator)
        coordinator.install(
            in: splitView,
            leading: AnyView(Color.clear),
            trailing: AnyView(Color.clear)
        )

        XCTAssertEqual(
            splitView.arrangedSubviews[0].frame.width,
            configuration.preferredListWidth
        )
    }

    func testPaneLayoutRemainsConsistentAtTransientZeroSize() {
        let splitView = makeSplitView(configuration: .ephemeral)

        splitView.frame = .zero
        splitView.adjustSubviews()

        XCTAssertEqual(splitView.arrangedSubviews[0].frame, .zero)
        XCTAssertEqual(splitView.arrangedSubviews[1].frame, .zero)
    }

    func testTransientCompressionDoesNotOverwritePersistedListWidth() {
        let persistenceIdentifier = "BufferTests.\(#function).\(UUID())"
        let defaultsKey = HistoryLayoutPersistence.paneListWidthDefaultsKey(
            for: persistenceIdentifier
        )
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let configuration = HistoryPaneSplitConfiguration(
            minimumListWidth: 260,
            preferredListWidth: 300,
            minimumDetailWidth: 360,
            dividerHitWidth: 9,
            persistenceIdentifier: persistenceIdentifier
        )
        let splitView = makeSplitView(configuration: configuration)
        splitView.setPosition(340, ofDividerAt: 0)

        splitView.frame.size.width = 621
        XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, 260)
        XCTAssertEqual(UserDefaults.standard.double(forKey: defaultsKey), 340)

        splitView.frame.size.width = 800
        XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, 340)
        XCTAssertEqual(UserDefaults.standard.double(forKey: defaultsKey), 340)
    }

    func testPanePersistenceRestoresDividerPosition() {
        let persistenceIdentifier = "BufferTests.\(#function).\(UUID())"
        let defaultsKey = HistoryLayoutPersistence.paneListWidthDefaultsKey(
            for: persistenceIdentifier
        )
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let configuration = HistoryPaneSplitConfiguration(
            minimumListWidth: 260,
            preferredListWidth: 300,
            minimumDetailWidth: 360,
            dividerHitWidth: 9,
            persistenceIdentifier: persistenceIdentifier
        )
        let firstSplitView = makeSplitView(configuration: configuration)
        firstSplitView.setPosition(340, ofDividerAt: 0)

        XCTAssertEqual(UserDefaults.standard.double(forKey: defaultsKey), 340)

        let restoredSplitView = makeSplitView(configuration: configuration)
        XCTAssertEqual(restoredSplitView.arrangedSubviews[0].frame.width, 340)
    }

    func testResettingLoadedPanePersistencePersistsPreferredWidth() {
        let persistenceIdentifier = "BufferTests.\(#function).\(UUID())"
        let defaultsKey = HistoryLayoutPersistence.paneListWidthDefaultsKey(
            for: persistenceIdentifier
        )
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let paneConfiguration = HistoryPaneSplitConfiguration(
            minimumListWidth: 260,
            preferredListWidth: 300,
            minimumDetailWidth: 360,
            dividerHitWidth: 9,
            persistenceIdentifier: persistenceIdentifier
        )
        let windowConfiguration = HistoryWindowConfiguration(
            frameAutosaveName: nil,
            paneSplitConfiguration: paneConfiguration
        )
        let activeSplitView = makeSplitView(configuration: paneConfiguration)
        activeSplitView.setPosition(260, ofDividerAt: 0)

        HistoryLayoutPersistence.restoreDefaults(for: windowConfiguration)
        activeSplitView.setPosition(paneConfiguration.preferredListWidth, ofDividerAt: 0)

        let restoredSplitView = makeSplitView(configuration: paneConfiguration)
        XCTAssertEqual(
            restoredSplitView.arrangedSubviews[0].frame.width,
            paneConfiguration.preferredListWidth
        )
    }

    func testRestoreDefaultLayoutRemovesWindowAndPanePersistenceValues() throws {
        let frameAutosaveName = NSWindow.FrameAutosaveName(
            "BufferTests.\(#function).Frame.\(UUID())"
        )
        let panePersistenceIdentifier = "BufferTests.\(#function).Pane.\(UUID())"
        let defaultsSuiteName = "BufferTests.\(#function).Defaults.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defer {
            NSWindow.removeFrame(usingName: frameAutosaveName)
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let configuration = HistoryWindowConfiguration(
            frameAutosaveName: frameAutosaveName,
            paneSplitConfiguration: HistoryPaneSplitConfiguration(
                minimumListWidth: 260,
                preferredListWidth: 300,
                minimumDetailWidth: 360,
                dividerHitWidth: 9,
                persistenceIdentifier: panePersistenceIdentifier
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 900, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.saveFrame(usingName: frameAutosaveName)
        let listWidthDefaultsKey = HistoryLayoutPersistence.paneListWidthDefaultsKey(
            for: panePersistenceIdentifier
        )
        defaults.set(340, forKey: listWidthDefaultsKey)

        HistoryLayoutPersistence.restoreDefaults(
            for: configuration,
            defaults: defaults
        )

        XCTAssertFalse(window.setFrameUsingName(frameAutosaveName))
        XCTAssertNil(defaults.object(forKey: listWidthDefaultsKey))
    }

    private func makeEphemeralConfigurator() -> HistoryPanelConfigurator {
        HistoryPanelConfigurator(configuration: .ephemeral)
    }

    private func makeSplitView(
        configuration: HistoryPaneSplitConfiguration
    ) -> HistoryPaneNativeSplitView {
        let splitView = HistoryPaneNativeSplitView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 420)
        )
        let coordinator = HistoryPaneSplitCoordinator(configuration: configuration)
        retainedSplitCoordinators.append(coordinator)
        coordinator.install(
            in: splitView,
            leading: AnyView(Color.clear),
            trailing: AnyView(Color.clear)
        )
        return splitView
    }
}

@MainActor
private final class HistoryPaneScrollProbe {
    weak var scrollView: NSScrollView?
}

private struct HistoryPaneScrollProbeView: NSViewRepresentable {
    let probe: HistoryPaneScrollProbe

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 300, height: 420)
        )
        scrollView.documentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 300, height: 1_200)
        )
        scrollView.hasVerticalScroller = true
        probe.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {}
}

@MainActor
final class ClickModifierDetectorTests: XCTestCase {
    func testSingleClickRoutesOnlyPrimaryInteraction() throws {
        let view = ClickModifierDetector.ClickView()
        var primaryModifiers: NSEvent.ModifierFlags?
        var doubleClickCount = 0
        view.onClickWithModifiers = { primaryModifiers = $0 }
        view.onDoubleClick = { doubleClickCount += 1 }

        view.mouseDown(with: try mouseDownEvent(clickCount: 1, modifiers: .command))

        XCTAssertEqual(primaryModifiers, .command)
        XCTAssertEqual(doubleClickCount, 0)
    }

    func testDoubleClickRoutesOnlyCommitInteraction() throws {
        let view = ClickModifierDetector.ClickView()
        var primaryClickCount = 0
        var doubleClickCount = 0
        view.onClickWithModifiers = { _ in primaryClickCount += 1 }
        view.onDoubleClick = { doubleClickCount += 1 }

        view.mouseDown(with: try mouseDownEvent(clickCount: 2))

        XCTAssertEqual(primaryClickCount, 0)
        XCTAssertEqual(doubleClickCount, 1)
    }

    func testPointerMovementIsForwarded() throws {
        let view = ClickModifierDetector.ClickView()
        var pointerMoveCount = 0
        view.onPointerMoved = { pointerMoveCount += 1 }

        view.mouseMoved(with: try mouseEvent(type: .mouseMoved))

        XCTAssertEqual(pointerMoveCount, 1)
    }

    private func mouseDownEvent(
        clickCount: Int,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try mouseEvent(
            type: .leftMouseDown,
            clickCount: clickCount,
            modifiers: modifiers
        )
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        clickCount: Int = 0,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: clickCount,
                pressure: 1
            )
        )
    }
}

@MainActor
final class ClipboardPinnedRowDragBridgeHoverTests: XCTestCase {
    func testNativeInteractionViewForwardsHoverLifecycle() throws {
        let view = ClipboardPinnedRowDragBridge.InteractionView()
        var hoverStates: [Bool] = []
        var pointerMoveCount = 0
        view.onHoverChanged = { hoverStates.append($0) }
        view.onPointerMoved = { pointerMoveCount += 1 }

        let event = try mouseEvent(type: .mouseMoved)
        view.mouseEntered(with: event)
        view.mouseMoved(with: try mouseEvent(type: .mouseMoved))
        view.mouseExited(with: event)

        XCTAssertEqual(hoverStates, [true, false])
        XCTAssertEqual(pointerMoveCount, 1)
    }

    private func mouseEvent(type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )
    }
}

@MainActor
final class ClipboardListHoverCoordinatorTests: XCTestCase {
    func testScrollClearsActiveHoverAndSuppressesSyntheticEnterEvents() {
        let coordinator = ClipboardListHoverCoordinator()
        let firstItemID = UUID()
        let secondItemID = UUID()
        var clearedItemIDs: [UUID] = []

        XCTAssertTrue(
            coordinator.activate(itemID: firstItemID) {
                clearedItemIDs.append(firstItemID)
            }
        )

        coordinator.suppressUntilPointerMoves()

        XCTAssertEqual(clearedItemIDs, [firstItemID])
        XCTAssertFalse(
            coordinator.activate(itemID: secondItemID) {
                clearedItemIDs.append(secondItemID)
            }
        )
        XCTAssertEqual(clearedItemIDs, [firstItemID])
    }

    func testPointerMovementReenablesHoverAfterScroll() {
        let coordinator = ClipboardListHoverCoordinator()
        let itemID = UUID()
        var clearCount = 0

        coordinator.suppressUntilPointerMoves()

        XCTAssertTrue(
            coordinator.activateFromPointerMovement(itemID: itemID) {
                clearCount += 1
            }
        )

        coordinator.suppressUntilPointerMoves()
        XCTAssertEqual(clearCount, 1)
    }

    func testActivatingAnotherRowClearsOnlyPreviousHover() {
        let coordinator = ClipboardListHoverCoordinator()
        let firstItemID = UUID()
        let secondItemID = UUID()
        var firstClearCount = 0
        var secondClearCount = 0

        coordinator.activate(itemID: firstItemID) {
            firstClearCount += 1
        }
        coordinator.activate(itemID: secondItemID) {
            secondClearCount += 1
        }

        XCTAssertEqual(firstClearCount, 1)
        XCTAssertEqual(secondClearCount, 0)

        coordinator.deactivate(itemID: firstItemID)
        coordinator.suppressUntilPointerMoves()

        XCTAssertEqual(firstClearCount, 1)
        XCTAssertEqual(secondClearCount, 1)
    }
}
