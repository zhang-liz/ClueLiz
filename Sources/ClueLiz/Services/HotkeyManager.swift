import Foundation
import Carbon.HIToolbox

/// Global hotkey registration via Carbon — works without Accessibility/Input
/// Monitoring permissions, fires even when the app is not frontmost.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    /// Default Get Answer hotkey: ⌘⇧Return.
    static let defaultKeyCode = UInt32(kVK_Return)
    static let defaultModifiers = UInt32(cmdKey | shiftKey)

    /// Returns false when registration fails (e.g. the shortcut is already taken
    /// by another app) so the caller can warn instead of leaving the hotkey
    /// silently dead.
    @discardableResult
    func register(keyCode: UInt32 = HotkeyManager.defaultKeyCode,
                  modifiers: UInt32 = HotkeyManager.defaultModifiers,
                  handler: @escaping () -> Void) -> Bool {
        unregister()
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.handler?() }
            return noErr
        }, 1, &eventType, selfPointer, &eventHandlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C554C) /* "CLUL" */, id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        guard installStatus == noErr, registerStatus == noErr, hotKeyRef != nil else {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        hotKeyRef = nil
        eventHandlerRef = nil
        handler = nil
    }

    deinit { unregister() }
}
