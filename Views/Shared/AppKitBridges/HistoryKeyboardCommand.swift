import AppKit
import Foundation

enum HistoryKeyboardCommand: Equatable {
    case modifiersChanged(NSEvent.ModifierFlags)
    case moveUp(extendSelection: Bool)
    case moveDown(extendSelection: Bool)
    case moveToFirst(extendSelection: Bool)
    case moveToLast(extendSelection: Bool)
    case commitSelection(copyOnly: Bool)
    case dismiss
    case deleteSelection
    case copySelection
    case togglePinned
    case saveImage
    case quickPaste(Int)
}

struct HistoryKeyboardInput: Equatable {
    enum EventType: Equatable {
        case keyDown
        case flagsChanged
    }

    let eventType: EventType
    let keyCode: UInt16
    let modifierFlags: NSEvent.ModifierFlags
    let isTextInputFocused: Bool
}

enum HistoryKeyboardCommandResolver {
    static func resolve(_ input: HistoryKeyboardInput) -> HistoryKeyboardCommand? {
        let relevantFlags = input.modifierFlags.intersection([.command, .shift, .option, .control])
        let isCommandOnlyPressed = relevantFlags == .command
        let isCommandShiftOnlyPressed = relevantFlags == [.command, .shift]

        if input.eventType == .flagsChanged {
            return .modifiersChanged(input.modifierFlags)
        }

        switch input.keyCode {
        case 126:
            if isCommandShiftOnlyPressed {
                return .moveToFirst(extendSelection: true)
            }
            if isCommandOnlyPressed {
                return .moveToFirst(extendSelection: false)
            }
            return .moveUp(extendSelection: input.modifierFlags.contains(.shift))

        case 125:
            if isCommandShiftOnlyPressed {
                return .moveToLast(extendSelection: true)
            }
            if isCommandOnlyPressed {
                return .moveToLast(extendSelection: false)
            }
            return .moveDown(extendSelection: input.modifierFlags.contains(.shift))

        case 36:
            return .commitSelection(copyOnly: input.modifierFlags.contains(.option))

        case 53:
            return .dismiss

        case 51:
            guard input.modifierFlags.contains(.command) else { return nil }
            return .deleteSelection

        case 8:
            guard input.modifierFlags.contains(.command), !input.isTextInputFocused else { return nil }
            return .copySelection

        case 35:
            guard input.modifierFlags.contains(.command) else { return nil }
            return .togglePinned

        case 1:
            guard input.modifierFlags.contains(.command) else { return nil }
            return .saveImage

        case 18, 19, 20, 21, 22, 23, 25, 26, 28, 29:
            guard isCommandOnlyPressed else { return nil }
            let quickPasteIndexByKeyCode: [UInt16: Int] = [
                18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
                22: 5, 26: 6, 28: 7, 25: 8, 29: 9
            ]
            guard let quickPasteIndex = quickPasteIndexByKeyCode[input.keyCode] else { return nil }
            return .quickPaste(quickPasteIndex)

        default:
            return nil
        }
    }
}
