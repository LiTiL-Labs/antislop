#if os(macOS)
import AntiSlopCore
import AppKit
import Carbon

/// The two independently assigned triggers.
public enum HotKeyAction: UInt32, CaseIterable {
    case rewrite = 1
    case detect = 2

    var name: String { self == .rewrite ? "anti-slop key" : "slop-detection key" }
}

/// Registers the user's chosen triggers. Ordinary keys and combinations use the
/// Carbon hot-key API, which consumes the key system-wide and needs no extra
/// permission. A lone modifier (Right ⌥, Fn, Caps Lock…) can't be registered
/// that way, so it is watched with a global modifier-change monitor, which needs
/// the Accessibility access Anti-slop already requires; it types nothing, so
/// there is nothing to consume. Registration is suspended while Anti-slop itself
/// is active so its own fields and panel receive the keys (global monitors never
/// see Anti-slop's own events either). Used on the main thread only.
public final class HotKeyManager {
    public private(set) var bindings: [HotKeyAction: ShortcutBinding] = [:]
    public var onPress: ((HotKeyAction) -> Void)?

    private var refs: [HotKeyAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var down: Set<HotKeyAction> = []
    private var suspended = false
    private var loneDetectors: [HotKeyAction: LoneModifierDetector] = [:]
    private var loneMonitor: Any?
    private static let signature: OSType = 0x4153_4C50 // "ASLP"
    private static let probeID: UInt32 = 99

    public init() {
        installHandler()
    }

    public func binding(for action: HotKeyAction) -> ShortcutBinding? { bindings[action] }

    private func installHandler() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let kind = GetEventKind(event)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handle(kind: kind, id: id.id)
            return 0
        }, 2, &types, context, &handler)
    }

    private func handle(kind: UInt32, id: UInt32) {
        guard let action = HotKeyAction(rawValue: id) else { return }
        if kind == UInt32(kEventHotKeyPressed) {
            // Holding the key produces one activation, not repeated requests.
            guard !down.contains(action) else { return }
            down.insert(action)
            onPress?(action)
        } else if kind == UInt32(kEventHotKeyReleased) {
            down.remove(action)
        }
    }

    static func carbonModifiers(_ mods: Set<ShortcutModifier>) -> UInt32 {
        var m: UInt32 = 0
        if mods.contains(.command) { m |= UInt32(cmdKey) }
        if mods.contains(.option) { m |= UInt32(optionKey) }
        if mods.contains(.control) { m |= UInt32(controlKey) }
        if mods.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    private func registerRaw(_ b: ShortcutBinding, id: UInt32) -> (OSStatus, EventHotKeyRef?) {
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(b.keyCode), Self.carbonModifiers(b.modifierSet),
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &newRef)
        return (status, newRef)
    }

    /// Ask macOS whether this binding can be registered, without keeping it.
    /// Success means registration works; it cannot rule out an app-specific
    /// conflict, and some system shortcuts may still take precedence. A lone
    /// modifier is watched rather than registered, so it always succeeds here.
    public func canRegister(_ b: ShortcutBinding, for action: HotKeyAction) -> OSStatus {
        if b.isLoneModifier { return 0 }
        if b == bindings[action] && refs[action] != nil { return 0 }
        let (status, testRef) = registerRaw(b, id: Self.probeID)
        if let testRef { UnregisterEventHotKey(testRef) }
        return status
    }

    /// Replace one action's binding only after the new one registers; on failure
    /// the previous valid binding stays in place.
    @discardableResult
    public func apply(_ b: ShortcutBinding?, for action: HotKeyAction) -> OSStatus {
        guard let b, b.enabled else {
            unregister(action)
            bindings[action] = nil
            refreshLoneMonitor()
            return 0
        }
        if b == bindings[action] && (refs[action] != nil || suspended || b.isLoneModifier) { return 0 }
        if suspended || b.isLoneModifier {
            let status = canRegister(b, for: action)
            guard status == 0 else { return status }
            unregister(action)
            bindings[action] = b
            refreshLoneMonitor()
            return 0
        }
        let (status, newRef) = registerRaw(b, id: action.rawValue)
        guard status == 0, let newRef else { return status }
        unregister(action)
        refs[action] = newRef
        bindings[action] = b
        refreshLoneMonitor()
        return 0
    }

    public func suspend() {
        guard !suspended else { return }
        suspended = true
        for action in HotKeyAction.allCases { unregister(action) }
        down = []
        for key in loneDetectors.keys { loneDetectors[key]?.otherKeyDown() }
    }

    /// Re-register the bindings after a suspension; returns the first failing
    /// registration status (0 when all registered or nothing to do).
    @discardableResult
    public func resume() -> OSStatus {
        guard suspended else { return 0 }
        suspended = false
        var result: OSStatus = 0
        for (action, b) in bindings where !b.isLoneModifier {
            let (status, newRef) = registerRaw(b, id: action.rawValue)
            if status == 0 { refs[action] = newRef } else if result == 0 { result = status }
        }
        return result
    }

    private func unregister(_ action: HotKeyAction) {
        if let ref = refs[action] { UnregisterEventHotKey(ref) }
        refs[action] = nil
    }

    // MARK: Lone modifiers

    private func refreshLoneMonitor() {
        loneDetectors = [:]
        for (action, b) in bindings where b.isLoneModifier {
            loneDetectors[action] = LoneModifierDetector(keyCode: b.keyCode)
        }
        if loneDetectors.isEmpty {
            if let loneMonitor { NSEvent.removeMonitor(loneMonitor) }
            loneMonitor = nil
        } else if loneMonitor == nil {
            loneMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                self?.observe(event)
            }
        }
    }

    private func observe(_ event: NSEvent) {
        for action in Array(loneDetectors.keys) {
            if event.type == .keyDown {
                loneDetectors[action]?.otherKeyDown()
            } else if loneDetectors[action]?.flagsChanged(keyCode: Int(event.keyCode),
                                                          flags: event.modifierFlags.rawValue) == true,
                      !suspended {
                onPress?(action)
            }
        }
    }

    public static func describe(_ status: OSStatus) -> String {
        switch Int(status) {
        case 0: return "Registered."
        case -9878: return "Another app or macOS already uses this shortcut."
        case -9868: return "macOS rejected this key as a shortcut."
        default: return "macOS couldn't register this shortcut (error \(status))."
        }
    }
}

extension ShortcutBinding {
    /// True when a key-down event in Anti-slop's own windows is exactly this
    /// (non-lone) binding. A held Fn/Globe never counts as a modifier here.
    func matches(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !isLoneModifier, Int(event.keyCode) == keyCode else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var mods = Set<ShortcutModifier>()
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        return mods == modifierSet.subtracting([.function])
    }
}

/// Enabled macOS system shortcuts, for honest conflict feedback.
enum SystemShortcuts {
    static func enabled() -> [SystemHotKey] {
        var byID: [Int: SystemHotKey?] = [:]
        if let dict = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                "com.apple.symbolichotkeys" as CFString) as? [String: Any] {
            for (key, raw) in dict {
                guard let id = Int(key), let entry = raw as? [String: Any] else { continue }
                let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? false
                guard enabled,
                      let value = entry["value"] as? [String: Any],
                      let params = value["parameters"] as? [NSNumber], params.count >= 3,
                      params[1].intValue != 65535 else {
                    byID[id] = .some(nil)
                    continue
                }
                byID[id] = SystemHotKey(id: id, keyCode: params[1].intValue,
                                        modifiers: SystemHotKey.modifiers(fromMask: params[2].intValue))
            }
        }
        var out: [SystemHotKey] = byID.values.compactMap { $0 }
        // Defaults that the preferences file omits until the user changes them.
        for d in SystemHotKey.macOSDefaults where byID[d.id] == nil { out.append(d) }
        return out
    }
}

/// Opens a provider's official sign-in in Terminal. Anti-slop writes a small
/// launcher containing only the discovered runtime path and fixed arguments;
/// it never sees the password, code or token.
enum SignInLauncher {
    static func open(_ cmd: SignInCommand) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anti-slop-sign-in-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let script = dir.appendingPathComponent("Anti-slop sign-in.command")
        let command = ([cmd.executable] + cmd.arguments).map(shellQuote).joined(separator: " ")
        let body = """
        #!/bin/zsh
        clear
        echo "Anti-slop opened the provider's own sign-in. Anti-slop never sees your password or tokens."
        echo
        \(command)
        echo
        echo "When sign-in is finished, return to Anti-slop and choose Check again."
        """
        try Data(body.utf8).write(to: script, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        NSWorkspace.shared.open(script)
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
#endif
