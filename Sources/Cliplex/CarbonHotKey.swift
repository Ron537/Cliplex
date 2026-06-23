import AppKit
import Carbon.HIToolbox

/// A thin wrapper around the Carbon `RegisterEventHotKey` API — the only
/// dependency-free way to register a system-wide hotkey that fires even when
/// Cliplex is not the active app. (A friendlier recorder UI via the
/// KeyboardShortcuts package is added with the Settings window later.)
final class CarbonHotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private let handler: () -> Void

    // Registry so the single process-wide Carbon event handler can route a
    // hotkey press back to the right Swift closure. Entries are held weakly so
    // releasing a CarbonHotKey runs `deinit` (which unregisters the system
    // hotkey) — important when a shortcut is later rebound.
    private final class WeakBox {
        weak var hotKey: CarbonHotKey?
        init(_ hotKey: CarbonHotKey) { self.hotKey = hotKey }
    }
    private static var registry: [UInt32: WeakBox] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        self.id = CarbonHotKey.nextID
        self.handler = handler
        CarbonHotKey.nextID += 1
        CarbonHotKey.registry[id] = WeakBox(self)
        CarbonHotKey.installEventHandlerIfNeeded()
        register(keyCode: keyCode, carbonModifiers: CarbonHotKey.carbonFlags(from: modifiers))
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        CarbonHotKey.registry[id] = nil
    }

    private func register(keyCode: UInt32, carbonModifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C5058 /* "CLPX" */), id: id)
        RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
    }

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr, let hk = CarbonHotKey.registry[hotKeyID.id]?.hotKey {
                    DispatchQueue.main.async { hk.handler() }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }

    private static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }
}
