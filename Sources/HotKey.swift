import Carbon.HIToolbox

// Global shortcuts registered via Carbon: they require no Accessibility permission.
// A single event handler dispatches to the instances through the hotkey id.
final class HotKey {
    private static var registry: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    init?(id: UInt32, keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) {
        self.id = id
        if !Self.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
                var hkID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                DispatchQueue.main.async { HotKey.registry[hkID.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            guard status == noErr else { return nil }
            Self.handlerInstalled = true
        }
        Self.registry[id] = onPress
        let hkID = EventHotKeyID(signature: 0x50_41_53_54, id: id) // 'PAST'
        guard RegisterEventHotKey(keyCode, modifiers, hkID,
                                  GetEventDispatcherTarget(), 0, &hotKeyRef) == noErr else {
            Self.registry[id] = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        HotKey.registry[id] = nil
    }
}
