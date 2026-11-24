import Carbon
import Cocoa

enum HotKeyPreset: Int, CaseIterable {
    case optionQ = 0
    case controlQ = 1
    case optionR = 2
    case option1 = 3
    case disabled = 99

    var title: String {
        switch self {
        case .optionQ: return "⌥Q（推荐）"
        case .controlQ: return "⌃Q"
        case .optionR: return "⌥R"
        case .option1: return "⌥1"
        case .disabled: return "关闭"
        }
    }

    var shortBadge: String {
        switch self {
        case .optionQ: return "⌥Q"
        case .controlQ: return "⌃Q"
        case .optionR: return "⌥R"
        case .option1: return "⌥1"
        case .disabled: return ""
        }
    }

    var carbonKeyCode: UInt32? {
        switch self {
        case .optionQ, .controlQ: return UInt32(kVK_ANSI_Q)
        case .optionR: return UInt32(kVK_ANSI_R)
        case .option1: return UInt32(kVK_ANSI_1)
        case .disabled: return nil
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionQ, .optionR, .option1: return UInt32(optionKey)
        case .controlQ: return UInt32(controlKey)
        case .disabled: return 0
        }
    }
}

/// Registers a system-wide 2-key hotkey via Carbon RegisterEventHotKey
/// (works globally without requiring macOS Accessibility permissions).
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var callback: (() -> Void)?

    private let signature: OSType = 0x51524E47 // 'QRNG'
    private let hotKeyId: UInt32 = 1

    func register(preset: HotKeyPreset, onTrigger: @escaping () -> Void) {
        self.callback = onTrigger
        unregister()

        guard let keyCode = preset.carbonKeyCode else { return }
        installHandlerIfNeeded()

        let hkID = EventHotKeyID(signature: signature, id: hotKeyId)
        RegisterEventHotKey(
            keyCode,
            preset.carbonModifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            if status == noErr {
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                if hkID.signature == manager.signature && hkID.id == manager.hotKeyId {
                    DispatchQueue.main.async {
                        manager.callback?()
                    }
                    return noErr
                }
            }
            return OSStatus(eventNotHandledErr)
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventSpec, selfPtr, &eventHandlerRef)
    }
}
