#if os(macOS)
import AntiSlopCore
import AppKit
import Carbon

/// Registers the user's chosen trigger with the Carbon hot-key API, which
/// supports single keys and modified combinations without Accessibility or
/// Input Monitoring permission. The key is consumed system-wide while
/// registered; registration is suspended while Anti-slop itself is active so
/// the assigned key can be typed in Anti-slop's own fields. Used on the main
/// thread only (Carbon delivers application-target events there).
public final class HotKeyManager {
    public private(set) var binding: ShortcutBinding?
    public var onPress: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var isDown = false
    private var suspended = false
    private static let signature: OSType = 0x4153_4C50 // "ASLP"

    public init() {
        installHandler()
    }

    private func installHandler() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let kind = GetEventKind(event)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handle(kind: kind)
            return 0
        }, 2, &types, context, &handler)
    }

    private func handle(kind: UInt32) {
        if kind == UInt32(kEventHotKeyPressed) {
            // Holding the key produces one activation, not repeated requests.
            guard !isDown else { return }
            isDown = true
            onPress?()
        } else if kind == UInt32(kEventHotKeyReleased) {
            isDown = false
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
    /// conflict, and some system shortcuts may still take precedence.
    public func canRegister(_ b: ShortcutBinding) -> OSStatus {
        if b == binding && ref != nil { return 0 }
        let (status, testRef) = registerRaw(b, id: 99)
        if let testRef { UnregisterEventHotKey(testRef) }
        return status
    }

    /// Replace the active binding only after the new one registers; on failure
    /// the previous valid binding stays in place.
    @discardableResult
    public func apply(_ b: ShortcutBinding?) -> OSStatus {
        guard let b, b.enabled else {
            unregisterCurrent()
            binding = nil
            return 0
        }
        if b == binding && (ref != nil || suspended) { return 0 }
        if suspended {
            let status = canRegister(b)
            if status == 0 { binding = b }
            return status
        }
        let (status, newRef) = registerRaw(b, id: 1)
        guard status == 0, let newRef else { return status }
        if let ref { UnregisterEventHotKey(ref) }
        ref = newRef
        binding = b
        return 0
    }

    public func suspend() {
        guard !suspended else { return }
        suspended = true
        unregisterCurrent()
        isDown = false
    }

    /// Re-register the binding after a suspension; returns the registration status (0 when nothing to do).
    @discardableResult
    public func resume() -> OSStatus {
        guard suspended else { return 0 }
        suspended = false
        guard let b = binding else { return 0 }
        let (status, newRef) = registerRaw(b, id: 1)
        if status == 0 { ref = newRef }
        return status
    }

    private func unregisterCurrent() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
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
