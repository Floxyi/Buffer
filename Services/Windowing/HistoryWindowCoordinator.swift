import Foundation

enum HistoryWindowOpenTrigger: Equatable {
    case hotkey
    case reopen
    case startup
    case statusBar
}

struct HistoryWindowPresentationIntent: Equatable {
    let trigger: HistoryWindowOpenTrigger
    let focusSearch: Bool
    let activateApp: Bool

    var suppressQuickPasteUntilModifiersReleased: Bool {
        trigger == .hotkey
    }

    static func standard(for trigger: HistoryWindowOpenTrigger) -> HistoryWindowPresentationIntent {
        HistoryWindowPresentationIntent(
            trigger: trigger,
            focusSearch: true,
            activateApp: true
        )
    }
}

@MainActor
protocol HistoryWindowControlling: AnyObject {
    var isWindowVisible: Bool { get }
    func showHistoryWindow(
        focusSearch: Bool,
        activateApp: Bool,
        suppressQuickPasteUntilModifiersReleased: Bool
    )
    func close()
}

extension HistoryWindowController: HistoryWindowControlling {
    var isWindowVisible: Bool {
        window?.isVisible == true
    }

    func showHistoryWindow(
        focusSearch: Bool,
        activateApp: Bool,
        suppressQuickPasteUntilModifiersReleased: Bool
    ) {
        showWindow(
            nil,
            focusSearch: focusSearch,
            activateApp: activateApp,
            suppressQuickPasteUntilModifiersReleased: suppressQuickPasteUntilModifiersReleased
        )
    }
}

@MainActor
final class HistoryWindowCoordinator {
    private let controllerFactory: @MainActor () -> any HistoryWindowControlling
    private var historyWindowController: (any HistoryWindowControlling)?

    init(controllerFactory: @escaping @MainActor () -> any HistoryWindowControlling) {
        self.controllerFactory = controllerFactory
    }

    func toggle(trigger: HistoryWindowOpenTrigger) {
        let controller = resolveController()
        if controller.isWindowVisible {
            controller.close()
        } else {
            present(.standard(for: trigger))
        }
    }

    func present(_ intent: HistoryWindowPresentationIntent) {
        let controller = resolveController()
        controller.showHistoryWindow(
            focusSearch: intent.focusSearch,
            activateApp: intent.activateApp,
            suppressQuickPasteUntilModifiersReleased: intent.suppressQuickPasteUntilModifiersReleased
        )
    }

    private func resolveController() -> any HistoryWindowControlling {
        if let historyWindowController {
            return historyWindowController
        }

        let controller = controllerFactory()
        historyWindowController = controller
        return controller
    }
}
