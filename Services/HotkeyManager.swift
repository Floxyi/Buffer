import Carbon
import Cocoa

@MainActor
protocol HotkeyService: AnyObject {
    func register(callback: @escaping @MainActor () -> Void)
    func reregister()
    func unregister()
}

@MainActor
final class HotkeyManager: HotkeyService {
    private let settingsManager: SettingsManager
    private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?
    private var callback: (@MainActor () -> Void)?
    private var isSuspended = false

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    func register(callback: @escaping @MainActor () -> Void) {
        self.callback = callback
        unregister()
        installEventHandlerIfNeeded()

        let requiredKeyCode = UInt32(settingsManager.hotkeyKeyCode)
        let modifiers = carbonModifiers(for: settingsManager.hotkeyModifiers)
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4255_4646), id: 1)

        let registerStatus = RegisterEventHotKey(
            requiredKeyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            BufferLogger.hotkey.error("Failed to register hotkey: \(registerStatus)")
            return
        }

        self.hotKeyRef = hotKeyRef
    }

    func reregister() {
        guard let callback else { return }
        register(callback: callback)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
    }

    deinit {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, theEvent, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyPressed(theEvent)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            BufferLogger.hotkey.error("Failed to install event handler: \(status)")
        }
    }

    private func handleHotKeyPressed(_ event: EventRef?) -> OSStatus {
        guard let event else { return noErr }

        var hotKeyID = EventHotKeyID()
        GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard hotKeyID.id == 1, let callback, !isSuspended else { return noErr }

        Task { @MainActor in
            callback()
        }

        return noErr
    }

    private func carbonModifiers(for modifiers: HotkeyModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.shift { result |= UInt32(shiftKey) }
        if modifiers.command { result |= UInt32(cmdKey) }
        if modifiers.option { result |= UInt32(optionKey) }
        if modifiers.control { result |= UInt32(controlKey) }
        return result
    }
}
